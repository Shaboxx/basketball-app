# User needs and development evidence

These stories organize real implementation work for the public release on September 20, 2026. They are retrospective explanations, not original dated planning documents, customer interview claims, or fabricated issue history.

| User need | Implemented response | Inspectable development evidence |
| --- | --- | --- |
| As a roster analyst, I want player contract context so I can distinguish present salary from future flexibility. | Optional contract fields and explicit decoding; absent information remains absent. | [May 25: contract fields](https://github.com/Shaboxx/basketball-app/commit/4992550d610744d9e3e57bbe6de0ebe4fef66d8e) |
| As someone exploring a trade, I want the constraint explained so I can revise the proposal. | Tier-aware incoming-salary limits and named constraint findings. | [May 31: salary matching](https://github.com/Shaboxx/basketball-app/commit/6a8bf8973cc97aa61a0054b96fb68d8b20ad7c67) |
| As a team builder, I want position coverage without counting a player twice. | Eligibility-based depth-chart placement and subsequent lineup work. | [June 1: eligibility depth chart](https://github.com/Shaboxx/basketball-app/commit/fc4d36f321a2c62688f79d1b762f19bf26f20f65) |
| As a reviewer, I want to inspect the explanation behind a lineup. | Lineup labeling engine and a navigable breakdown. | [June 2: lineup breakdown](https://github.com/Shaboxx/basketball-app/commit/84d19d468684528a5e4ef0894a31ebedfa904841) |
| As a basketball fan, I want repeatable interactive challenges. | Deterministic guess, quiz, and survivor engines. | [August 27: knowledge-game engines](https://github.com/Shaboxx/basketball-app/commit/5326771c8f6b858c231d5b7c0af80228ca97db0b) |
| As a portfolio reviewer, I want to run the project without data-access credentials. | A local browser workbench, synthetic fixture, reproducible report, and tests. | Current public release: [`app.py`](../app.py), [`web/index.html`](../web/index.html), and [`tests/test_app.py`](../tests/test_app.py) |

The historical links refer to the filtered public history. Their dates are original; their hashes differ from the unfiltered history. Application features described in older commits are not automatically claims about what is enabled in the public browser edition.
