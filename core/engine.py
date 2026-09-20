"""Public offline adapter: original contract logic and a Swift salary-matching port.

The fixture is invented and the outputs are demonstrations, not player forecasts
or a comprehensive ruling on any real transaction.
"""
from __future__ import annotations
from functools import lru_cache
import json
from pathlib import Path
from .offseason_cba import bird_tier, cap_hold, player_max, resign_max_first_year

ROOT = Path(__file__).resolve().parents[1]

@lru_cache(maxsize=1)
def fixture():
    return json.loads((ROOT / 'data/synthetic-league.json').read_text(encoding='utf-8'))

def get_player(identifier):
    if not isinstance(identifier, str):
        raise ValueError('Select a player')
    for player in fixture()['players']:
        if player['id'] == identifier:
            return player
    raise ValueError('Player is not in the synthetic fixture')

def allowed_incoming(tier: str, outgoing: int, cap_room: int) -> int:
    """Direct port of TradeCompliance.allowedIncoming, with integer arithmetic."""
    if tier == 'underCap':
        return max(cap_room, 0) + outgoing + 250_000
    if tier in ('overCap', 'overTax'):
        return max(min(2 * outgoing + 250_000, outgoing + 7_936_000), outgoing * 125 // 100 + 250_000)
    if tier in ('overFirstApron', 'overSecondApron'):
        return outgoing
    raise ValueError('Unknown cap tier')

def evaluate_trade(left_id, right_id):
    left, right = get_player(left_id), get_player(right_id)
    if left['team'] == right['team']:
        raise ValueError('A trade needs players from two different teams')
    teams = {team['id']: team for team in fixture()['teams']}
    sides = []
    for outgoing, incoming in ((left, right), (right, left)):
        team = teams[outgoing['team']]
        before = team['payroll']
        after = before - outgoing['salary'] + incoming['salary']
        rules = fixture()['cap_levels']
        tier = 'underCap' if after < rules['salary_cap'] else 'overCap'
        for key, name in (('tax','overTax'), ('first_apron','overFirstApron'), ('second_apron','overSecondApron')):
            if after >= rules[key]:
                tier = name
        cap_room = rules['salary_cap'] - before
        limit = allowed_incoming(tier, outgoing['salary'], cap_room)
        passed = incoming['salary'] <= limit
        sides.append({'team': team['name'], 'outgoing': outgoing['salary'], 'incoming': incoming['salary'],
                      'post_trade_payroll': after, 'tier': tier, 'incoming_limit': limit, 'salary_match': passed,
                      'offense_delta': round(incoming['offense']-outgoing['offense'],2),
                      'defense_delta': round(incoming['defense']-outgoing['defense'],2)})
    return {'salary_matching_passed': all(side['salary_match'] for side in sides), 'sides': sides,
            'scope': 'One-for-one salary matching only. Pick protections, exceptions, timing and all other eligibility rules are not evaluated.',
            'data_kind': 'synthetic'}

def lineup(identifiers):
    if not isinstance(identifiers, list) or len(identifiers) != 5 or any(not isinstance(i,str) for i in identifiers) or len(set(identifiers)) != 5:
        raise ValueError('Choose exactly five different fixture players')
    players = [get_player(identifier) for identifier in identifiers]
    slots = ('PG','SG','SF','PF','C')
    def assign(index, used):
        if index == len(slots): return []
        for player in players:
            if player['id'] not in used and slots[index] in player['positions']:
                tail = assign(index+1, used | {player['id']})
                if tail is not None: return [{'position': slots[index], 'player': player['name']}] + tail
        return None
    assignment = assign(0,set())
    return {'players': [p['name'] for p in players], 'positions_covered': assignment is not None,
            'assignment': assignment, 'salary': sum(p['salary'] for p in players),
            'mean_offense': round(sum(p['offense'] for p in players)/5,2),
            'mean_defense': round(sum(p['defense'] for p in players)/5,2),
            'interpretation': 'Arithmetic summaries of invented inputs. No interaction effects or prediction claim.'}

def contract_example(identifier):
    player = get_player(identifier)
    rules = fixture()['contract_rules']
    tier = bird_tier(player['tenure'])
    return {'player': player['name'], 'bird_tier': tier,
            'max_first_year': player_max(player['salary'],player['years_of_service'],rules),
            'resign_max': resign_max_first_year(player['salary'],tier,player['years_of_service'],rules),
            'cap_hold': cap_hold(player['salary'],tier,player['years_of_service'],rules),
            'scope': 'Synthetic rule inputs demonstrating contract calculations. Not a current league contract offer.'}
