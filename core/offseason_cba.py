"""Pure contract calculations; callers supply the season-specific rule table."""
from __future__ import annotations


def bird_tier(team_tenure: int) -> str:
    """full (>=3 consecutive seasons with the team) / early (==2) / non (<2).

    The 3/2 thresholds mirror leagueRules.birdRights.{fullBird,earlyBird}.requiresYearsWithTeam;
    they are inline rather than read from `rules` because nonBird's value there is prose, not
    numeric, and Bird continuity exceptions (trade / waiver claim) are handled upstream in the
    tenure scraper, not here."""
    if team_tenure >= 3:
        return "full"
    if team_tenure == 2:
        return "early"
    return "non"


def min_salary(yos: int, rules: dict) -> int:
    """YOS-tiered minimum salary from leagueRules (table keyed "0".."10"; YOS clamped to that range)."""
    table = rules["minimumSalaryByYearsOfService"]
    return int(table[str(min(max(yos, 0), 10))])


def max_salary_tier(yos: int, rules: dict) -> dict:
    """{pct_of_cap, amount} for the player's YOS bracket (25/30/35%)."""
    m = rules["maximumSalary"]
    if yos <= 6:
        t = m["yearsOfService_0_to_6"]
    elif yos <= 9:
        t = m["yearsOfService_7_to_9"]
    else:
        t = m["yearsOfService_10_plus"]
    return {"pct_of_cap": t["percentOfCap"] / 100.0, "amount": int(t["amount"])}


def player_max(prior_salary: int, yos: int, rules: dict) -> int:
    """The YOS max-tier amount, or 105% of prior salary if higher (the
    maximumSalary.alternativeFormula)."""
    tier_amt = max_salary_tier(yos, rules)["amount"]
    return max(tier_amt, int(round(1.05 * (prior_salary or 0))))


def cap_hold(prior_salary: int, tier: str, yos: int, rules: dict,
             rookie_scale_completion: bool = False) -> int:
    """Free-agent cap hold ('Free Agent Amount', CBA Art. VII Sec. 4(d)) = a multiple
    of prior salary from leagueRules.capHolds, floored at the YOS minimum for
    sub-minimum players, capped at the player max. Multiples by tier:
      full (Qualifying Veteran FA): 150% if prior >= averagePlayerSalary else 190%
      early (Early Qualifying Veteran FA): FLAT 130% (the 150/190 split does NOT apply)
      non (Non-Qualifying): 120%
    A Qualifying Veteran FA following the 2nd option year of a rookie-scale deal uses
    250/300 (pass rookie_scale_completion=True; the assembler sets it once it can flag
    rookie-scale completers)."""
    ch = rules["capHolds"]
    avg = int(rules["systemLevels"]["averagePlayerSalary"])
    floor = min_salary(yos, rules)
    prior = prior_salary or 0
    if prior <= floor:
        return floor
    if tier == "early":
        mult = ch["earlyBird"]
    elif tier == "full" and rookie_scale_completion:
        mult = ch["rookieScaleCompletionAboveAvg"] if prior >= avg else ch["rookieScaleCompletionBelowAvg"]
    elif tier == "full":
        mult = ch["birdAboveAvg"] if prior >= avg else ch["birdBelowAvg"]
    else:
        mult = ch["nonBird"]
    return min(int(round(mult * prior)), player_max(prior, yos, rules))


def resign_max_first_year(prior_salary: int, tier: str, yos: int, rules: dict,
                          qualifying_offer: int | None = None) -> int:
    """First-year salary the PRIOR team may offer its own FA, by Bird tier
    (leagueRules.birdRights), capped at the player max. The 175%/105%/120%
    multipliers are inline because birdRights states them as prose, not numbers
    (same convention as bird_tier / player_max)."""
    pmax = player_max(prior_salary, yos, rules)
    avg = int(rules["systemLevels"]["averagePlayerSalary"])
    prior = prior_salary or 0
    if tier == "full":
        return pmax
    if tier == "early":
        return min(max(int(round(1.75 * prior)), int(round(1.05 * avg))), pmax)
    cands = [int(round(1.20 * prior)), int(round(1.20 * min_salary(yos, rules)))]
    if qualifying_offer:
        cands.append(int(qualifying_offer))
    return min(max(cands), pmax)


def is_free_agent_2026(salary_by_year: list) -> bool:
    """A 2026 free agent has no guaranteed 2026-27 salary (the y2 column).
    Option-based FAs (a player/team option for 2026-27 that gets declined) are
    a DECISION the state engine makes, not a data fact — the engine reads
    `option_final_year` for that; here we flag only contracts ending after 2025-26."""
    return not (len(salary_by_year) > 1 and salary_by_year[1])


def fa_type(yos: int, is_fa: bool) -> str | None:
    """UFA / RFA, or None if under contract. RFA approximated as YOS <= 3 (a
    player coming off a rookie-scale deal); the qualifying-offer / required-tender
    nuance is deferred to the state engine."""
    if not is_fa:
        return None
    return "RFA" if yos <= 3 else "UFA"
