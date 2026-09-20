import json
import threading
import unittest
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from http.server import ThreadingHTTPServer
from app import Handler
from core.engine import allowed_incoming, evaluate_trade, fixture, lineup, contract_example
from core.offseason_cba import bird_tier, min_salary, player_max, cap_hold

class DomainTests(unittest.TestCase):
    def test_contract_boundaries_and_clamping(self):
        rules = fixture()['contract_rules']
        self.assertEqual([bird_tier(n) for n in [0,1,2,3,10]], ['non','non','early','full','full'])
        self.assertEqual(min_salary(-1,rules), 1_000_000)
        self.assertEqual(min_salary(100,rules),2_000_000)
        self.assertEqual(player_max(40_000_000,10,rules),42_000_000)
        self.assertEqual(cap_hold(20_000_000,'early',8,rules),26_000_000)

    def test_salary_matching_tiers(self):
        self.assertEqual(allowed_incoming('underCap',10_000_000,5_000_000),15_250_000)
        self.assertEqual(allowed_incoming('underCap',10_000_000,-5_000_000),10_250_000)
        self.assertEqual(allowed_incoming('overCap',10_000_000,0),17_936_000)
        self.assertEqual(allowed_incoming('overTax',40_000_000,0),50_250_000)
        self.assertEqual(allowed_incoming('overFirstApron',10_000_000,0),10_000_000)
        self.assertEqual(allowed_incoming('overSecondApron',10_000_000,0),10_000_000)

    def test_trade_pass_and_failure(self):
        self.assertTrue(evaluate_trade('harbor-1','mesa-1')['salary_matching_passed'])
        self.assertFalse(evaluate_trade('harbor-6','mesa-1')['salary_matching_passed'])
        with self.assertRaises(ValueError): evaluate_trade('harbor-1','harbor-2')

    def test_lineup_positions_and_duplicate_guards(self):
        complete=lineup([f'harbor-{i}' for i in range(1,6)])
        self.assertTrue(complete['positions_covered'])
        guards=['harbor-1','harbor-6','mesa-1','mesa-6','valley-1']
        self.assertFalse(lineup(guards)['positions_covered'])
        with self.assertRaises(ValueError): lineup(['harbor-1']*5)
        with self.assertRaises(ValueError): lineup(['unknown']*5)

    def test_fixture_scope_and_contract(self):
        data=fixture()
        self.assertEqual((len(data['teams']),len(data['players'])),(4,24))
        self.assertEqual(data['data_kind'],'synthetic')
        self.assertEqual(contract_example('harbor-1')['resign_max'],25_000_000)

class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=ThreadingHTTPServer(('127.0.0.1',0), Handler)
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True)
        cls.thread.start()
        cls.base=f'http://127.0.0.1:{cls.server.server_port}'
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
    def test_page_fixture_and_actual_trade_request(self):
        with urlopen(self.base) as response:
            self.assertIn(b'Basketball Workbench',response.read())
        with urlopen(self.base+'/api/fixture') as response:
            self.assertEqual(len(json.load(response)['players']),24)
        request=Request(self.base+'/api/trade',data=json.dumps({'left':'harbor-1','right':'mesa-1'}).encode(),headers={'Content-Type':'application/json'})
        with urlopen(request) as response:
            self.assertTrue(json.load(response)['salary_matching_passed'])
    def test_invalid_input_and_path_do_not_read_files(self):
        for path in ('/../../app.py','/.git/config','/data/synthetic-league.json'):
            with self.assertRaises(HTTPError) as ctx: urlopen(self.base+path)
            self.assertEqual(ctx.exception.code,404)
        request=Request(self.base+'/api/trade',data=b'{"left":"bad","right":"mesa-1"}')
        with self.assertRaises(HTTPError) as ctx: urlopen(request)
        self.assertEqual(ctx.exception.code,400)

if __name__ == '__main__': unittest.main()
