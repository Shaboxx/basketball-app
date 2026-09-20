# Offline data contract

`data/synthetic-league.json` is a version-1 fixture created for this repository. It contains exactly four invented teams and 24 invented players. There is no real-player data or evaluation split.

| Entity | Required fields | Meaning |
| --- | --- | --- |
| Team | `id`, `name`, `payroll`, `color` | Stable fixture key, invented display label, fictional whole-roster payroll in dollars, display color |
| Player | `id`, `name`, `team`, `positions`, `salary`, `offense`, `defense`, `years_of_service`, `tenure` | Stable fixture key, invented name, known team key, eligible PG/SG/SF/PF/C positions, annual dollars, invented contribution inputs, service and tenure years |
| Cap levels | `salary_cap`, `tax`, `first_apron`, `second_apron` | Ordered fictional thresholds, in dollars |
| Contract rules | minimum table, maximum tiers, cap-hold multipliers, average salary | Explicit inputs to the original contract-calculation module |

`GET /api/fixture` returns the fixture. `POST /api/trade` accepts `left` and `right` player IDs from different teams. It returns per-team salaries, tier, incoming limit, and salary-match outcome. It is not a comprehensive trade validator.

`POST /api/lineup` accepts exactly five distinct known `players` IDs. A backtracking search assigns a different eligible player to each of the five positions, or returns no assignment. Contribution means are simple arithmetic summaries.

`POST /api/contract` accepts a known `player` ID and returns derived amounts using the fixture rule table. Invalid requests receive HTTP 400 and a visible error message. Arbitrary local files are not served.

The command `python app.py --demo` produces `examples/demo-report.json` deterministically from the current fixture and core. Changing the fixture changes the output; there are no canned API success results.
