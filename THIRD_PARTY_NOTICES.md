# Third-party notices and data provenance

The runnable Python/browser edition uses Python's standard library and browser APIs. It does not vendor third-party JavaScript or Python packages. Python is distributed separately under the Python Software Foundation license; no Python runtime is bundled.

The retained Swift components reference Apple's Foundation, SwiftUI, Combine, and platform APIs. Those frameworks are not redistributed in this repository. Some historical component versions refer to SDK integration types; those integrations are outside the offline targets and no SDK binaries, production configuration, or credentials are included.

All public example records are synthetic. No NBA logos, headshots, footage, downloaded datasets, or third-party player-value estimates are distributed. The project is not affiliated with a professional basketball league.

The contract and salary-matching implementation retains historical development rules for inspection. The example's league and cap table are invented; implementation constants are not a representation that current league rules have been fully verified.

## LDNOOBW word-list data

The retained [`FantasyNameRules.swift`](ios/NBATradeMachine/Models/FantasyNameRules.swift) contains a curated subset of the [List of Dirty, Naughty, Obscene, and Otherwise Bad Words](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words), copyright 2012–2020 Shutterstock, Inc. The upstream word-list data is licensed under **Creative Commons Attribution 4.0 International (CC BY 4.0)**. The complete upstream license notice is preserved in [`third_party/notices/LDNOOBW-LICENSE.txt`](third_party/notices/LDNOOBW-LICENSE.txt); the [upstream license](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/blob/master/LICENSE) and [CC BY 4.0 terms](https://creativecommons.org/licenses/by/4.0/) remain applicable.

Changes: the data was selected into compact Swift word sets and used with lowercase, character-substitution, token, and collapsed-string normalization. The original project is not represented as endorsing this application. This attribution applies to the word-list data in all retained historical versions as well as the current file. That third-party data retains its own license; the repository's original-code license status does not override it.
