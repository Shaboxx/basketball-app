"""Local, synthetic-data basketball workbench. Python 3.12+, standard library only."""
from __future__ import annotations
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json
from urllib.parse import urlparse
from core.engine import evaluate_trade, fixture, lineup, contract_example

ROOT = Path(__file__).resolve().parent

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/api/fixture':
            self.respond(200, fixture())
        elif path in ('/', '/index.html'):
            data = (ROOT / 'web/index.html').read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.respond(404, {'error': 'Not found'})

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 16_384:
                raise ValueError('Request must contain a small JSON object')
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError('Expected a JSON object')
            if self.path == '/api/trade':
                result = evaluate_trade(body.get('left'), body.get('right'))
            elif self.path == '/api/lineup':
                result = lineup(body.get('players'))
            elif self.path == '/api/contract':
                result = contract_example(body.get('player'))
            else:
                return self.respond(404, {'error': 'Not found'})
            self.respond(200, result)
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            self.respond(400, {'error': str(exc)})

    def respond(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

def demo():
    result = {
        'data': {'kind': 'synthetic', 'teams': len(fixture()['teams']), 'players': len(fixture()['players'])},
        'balanced_trade': evaluate_trade('harbor-1', 'mesa-1'),
        'salary_mismatch': evaluate_trade('harbor-6', 'mesa-1'),
        'lineup': lineup([f'harbor-{n}' for n in range(1, 6)]),
        'contract': contract_example('harbor-1'),
    }
    output = ROOT / 'examples/demo-report.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--demo', action='store_true', help='Write and print a deterministic report; no server')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    if args.demo:
        demo()
    else:
        print(f'Basketball Workbench: http://127.0.0.1:{args.port} — synthetic fixture, local only', flush=True)
        ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
