# Change Log

## [3.1.0](https://github.com/inaka/worker_pool/tree/3.1.0) (2017-08-15)
[Full Changelog](https://github.com/inaka/worker_pool/compare/3.0.0...3.1.0)

**Closed issues:**

- \[Feature\] Question about possible feature [\#125](https://github.com/inaka/worker_pool/issues/125)
- Project rebar.config file [\#124](https://github.com/inaka/worker_pool/issues/124)
- Sync the names of start/stop functions better [\#113](https://github.com/inaka/worker_pool/issues/113)
- Feature request: worker broadcast [\#105](https://github.com/inaka/worker_pool/issues/105)

**Merged pull requests:**

- add queue\_type parameter for starting pool to choose whether requests… [\#123](https://github.com/inaka/worker_pool/pull/123) ([jakud](https://github.com/jakud))
- \[Fix \#105\] Add message broadcast feature [\#118](https://github.com/inaka/worker_pool/pull/118) ([harenson](https://github.com/harenson))

## [3.0.0](https://github.com/inaka/worker_pool/tree/3.0.0) (2017-07-24)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.3.0...3.0.0)

**Closed issues:**

- Bump version to 3.0.0 [\#116](https://github.com/inaka/worker_pool/issues/116)
- Does it really work if simple\_one\_for\_one is used for the supervisor over the individual workers? [\#104](https://github.com/inaka/worker_pool/issues/104)
- wpool:stop\(my\_pool\) returns ok. but nothing exits [\#103](https://github.com/inaka/worker_pool/issues/103)

**Merged pull requests:**

- \[Close \#116\] Bump version to 3.0.0 [\#117](https://github.com/inaka/worker_pool/pull/117) ([Euen](https://github.com/Euen))
- \[\#113\] add stop\_sup function [\#115](https://github.com/inaka/worker_pool/pull/115) ([Euen](https://github.com/Euen))
- Euen.113.sync names of start stop functions [\#114](https://github.com/inaka/worker_pool/pull/114) ([Euen](https://github.com/Euen))

## [2.3.0](https://github.com/inaka/worker_pool/tree/2.3.0) (2017-07-19)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.2.3...2.3.0)

**Closed issues:**

- adding travis [\#109](https://github.com/inaka/worker_pool/issues/109)
- when worker process gen\_server:cast\(self\(\), {connect\_apns}\), it send to wpool\_process [\#108](https://github.com/inaka/worker_pool/issues/108)
- New release to hex.pm [\#101](https://github.com/inaka/worker_pool/issues/101)

**Merged pull requests:**

- Remove gen\_fsm support [\#112](https://github.com/inaka/worker_pool/pull/112) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Publish latest version to hex? [\#111](https://github.com/inaka/worker_pool/pull/111) ([puzza007](https://github.com/puzza007))
- \[\#109\] Adding Travis [\#110](https://github.com/inaka/worker_pool/pull/110) ([ferigis](https://github.com/ferigis))
- Remove warnings\_as\_errors compile opt. [\#106](https://github.com/inaka/worker_pool/pull/106) ([kzemek](https://github.com/kzemek))

## [2.2.3](https://github.com/inaka/worker_pool/tree/2.2.3) (2017-04-03)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.2.2...2.2.3)

**Fixed bugs:**

- wpool fails to handle temporarily dead workers [\#94](https://github.com/inaka/worker_pool/issues/94)

**Closed issues:**

- available\_worker doesn't handle worker exit [\#93](https://github.com/inaka/worker_pool/issues/93)
- can\_not\_hold\_a\_reply error for handle\_call with {noreply, State} result [\#78](https://github.com/inaka/worker_pool/issues/78)

**Merged pull requests:**

- Version Bump to 2.2.3 [\#102](https://github.com/inaka/worker_pool/pull/102) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Misuse of throw\(\) in the interface code [\#100](https://github.com/inaka/worker_pool/pull/100) ([ElectronicRU](https://github.com/ElectronicRU))
- Update Dependencies [\#99](https://github.com/inaka/worker_pool/pull/99) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Added monitoring to sync calls & made all sync calls the same scheme. [\#97](https://github.com/inaka/worker_pool/pull/97) ([ElectronicRU](https://github.com/ElectronicRU))
- Got rid of can\_not\_hold\_a\_reply error. [\#96](https://github.com/inaka/worker_pool/pull/96) ([ElectronicRU](https://github.com/ElectronicRU))
- Prevent wpool\_pool from crashing on dead workers with best\_worker strategy. [\#95](https://github.com/inaka/worker_pool/pull/95) ([ElectronicRU](https://github.com/ElectronicRU))

## [2.2.2](https://github.com/inaka/worker_pool/tree/2.2.2) (2017-01-24)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.2.1...2.2.2)

**Closed issues:**

- Version Bump to 2.2.2 [\#91](https://github.com/inaka/worker_pool/issues/91)
- last version is not on hex [\#89](https://github.com/inaka/worker_pool/issues/89)
- update the state of each workers? [\#70](https://github.com/inaka/worker_pool/issues/70)

**Merged pull requests:**

- \[\#91\] Version Bump to 2.2.2 [\#92](https://github.com/inaka/worker_pool/pull/92) ([ferigis](https://github.com/ferigis))
- Add pool\_sup\_shutdown option to customize shutdown. [\#90](https://github.com/inaka/worker_pool/pull/90) ([kzemek](https://github.com/kzemek))
- Remove useless ets creation info message [\#88](https://github.com/inaka/worker_pool/pull/88) ([juise](https://github.com/juise))

## [2.2.1](https://github.com/inaka/worker_pool/tree/2.2.1) (2016-09-20)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.2.0...2.2.1)

**Merged pull requests:**

- Bumped to 2.2.1 [\#87](https://github.com/inaka/worker_pool/pull/87) ([HernanRivasAcosta](https://github.com/HernanRivasAcosta))
- Added support for multiple overrun handlers and fixed the tests [\#86](https://github.com/inaka/worker_pool/pull/86) ([HernanRivasAcosta](https://github.com/HernanRivasAcosta))

## [2.2.0](https://github.com/inaka/worker_pool/tree/2.2.0) (2016-08-18)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.1.0...2.2.0)

**Closed issues:**

- Version Bump to 2.2.0 [\#84](https://github.com/inaka/worker_pool/issues/84)
- pool becomes unresponsive [\#81](https://github.com/inaka/worker_pool/issues/81)
- Implement common functions in the gen\_server or gen\_fsm way in a single shared module [\#80](https://github.com/inaka/worker_pool/issues/80)
- Complete coverage for wpool\_fsm\_process [\#79](https://github.com/inaka/worker_pool/issues/79)
- Replace \#wpool by a map [\#77](https://github.com/inaka/worker_pool/issues/77)

**Merged pull requests:**

- \[close \#84\] Version bump 2.2.0 [\#85](https://github.com/inaka/worker_pool/pull/85) ([ferigis](https://github.com/ferigis))
- \[\#80\] Implemented shared functions in shared module. \[Fix \#80\] [\#83](https://github.com/inaka/worker_pool/pull/83) ([ferigis](https://github.com/ferigis))
- fsm coverage \[\#79\] [\#82](https://github.com/inaka/worker_pool/pull/82) ([ferigis](https://github.com/ferigis))

## [2.1.0](https://github.com/inaka/worker_pool/tree/2.1.0) (2016-08-03)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.0.1...2.1.0)

**Fixed bugs:**

- Tests are unstable [\#56](https://github.com/inaka/worker_pool/pull/56) ([elbrujohalcon](https://github.com/elbrujohalcon))

**Merged pull requests:**

- Added a function to retrieve the stats for all pools [\#76](https://github.com/inaka/worker_pool/pull/76) ([HernanRivasAcosta](https://github.com/HernanRivasAcosta))
- We no longer have support for erlang.mk [\#75](https://github.com/inaka/worker_pool/pull/75) ([HernanRivasAcosta](https://github.com/HernanRivasAcosta))
- Version Bump to 2.1.0 [\#69](https://github.com/inaka/worker_pool/pull/69) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Standarize code style [\#68](https://github.com/inaka/worker_pool/pull/68) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Remove wpool\_shutdown [\#67](https://github.com/inaka/worker_pool/pull/67) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Remove wpool:call/5 [\#57](https://github.com/inaka/worker_pool/pull/57) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Complete Test Coverage [\#10](https://github.com/inaka/worker_pool/pull/10) ([elbrujohalcon](https://github.com/elbrujohalcon))

## [2.0.1](https://github.com/inaka/worker_pool/tree/2.0.1) (2016-06-27)
[Full Changelog](https://github.com/inaka/worker_pool/compare/2.0.0...2.0.1)

**Closed issues:**

- one\_for\_all strategy with the worker pool supervisor [\#64](https://github.com/inaka/worker_pool/issues/64)

**Merged pull requests:**

- Version Bump to 2.0.1 [\#74](https://github.com/inaka/worker_pool/pull/74) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Remove compiler warnings about random module [\#73](https://github.com/inaka/worker_pool/pull/73) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Actually remove the usage of random module if we're on OTP18+ [\#72](https://github.com/inaka/worker_pool/pull/72) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Upgrade katana-test [\#66](https://github.com/inaka/worker_pool/pull/66) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Add config options pool\_sup\_intensity and pool\_sup\_period [\#65](https://github.com/inaka/worker_pool/pull/65) ([waisbrot](https://github.com/waisbrot))

## [2.0.0](https://github.com/inaka/worker_pool/tree/2.0.0) (2016-05-26)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.1.0...2.0.0)

**Closed issues:**

- Version Bump to 2.0.0 [\#62](https://github.com/inaka/worker_pool/issues/62)
- Move from erlang.mk to rebar3 [\#60](https://github.com/inaka/worker_pool/issues/60)

**Merged pull requests:**

- \[Close \#62\] update to 2.0.0 version [\#63](https://github.com/inaka/worker_pool/pull/63) ([Euen](https://github.com/Euen))
- \[Close \#60\] Euen.60.rebar3 [\#61](https://github.com/inaka/worker_pool/pull/61) ([Euen](https://github.com/Euen))

## [1.1.0](https://github.com/inaka/worker_pool/tree/1.1.0) (2016-04-28)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.0.4...1.1.0)

**Fixed bugs:**

- master is not working with rebar3 projects [\#58](https://github.com/inaka/worker_pool/pull/58) ([melekes](https://github.com/melekes))

**Closed issues:**

- Wrong typespec for strategy\(\) [\#48](https://github.com/inaka/worker_pool/issues/48)
- Add wpool\_fsm\_process tests [\#46](https://github.com/inaka/worker_pool/issues/46)
- Update README.md [\#45](https://github.com/inaka/worker_pool/issues/45)
- gen\_fsm as workers [\#24](https://github.com/inaka/worker_pool/issues/24)
- Update Dependencies [\#23](https://github.com/inaka/worker_pool/issues/23)
- ability to provide custom strategies [\#16](https://github.com/inaka/worker_pool/issues/16)
- Possibility to create anonymous pools? [\#32](https://github.com/inaka/worker_pool/issues/32)
- Worker recycling/expiration [\#20](https://github.com/inaka/worker_pool/issues/20)

**Merged pull requests:**

- Update README.md [\#55](https://github.com/inaka/worker_pool/pull/55) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Ferigis.46.adding fsm tests [\#54](https://github.com/inaka/worker_pool/pull/54) ([ferigis](https://github.com/ferigis))
- Replacement for \#47 [\#53](https://github.com/inaka/worker_pool/pull/53) ([elbrujohalcon](https://github.com/elbrujohalcon))
- handle custom strategy functions [\#52](https://github.com/inaka/worker_pool/pull/52) ([benoitc](https://github.com/benoitc))
- Updated wpool stats/0 type specification [\#50](https://github.com/inaka/worker_pool/pull/50) ([melekes](https://github.com/melekes))
- Fix the typespec for the hash\_worker strategy [\#49](https://github.com/inaka/worker_pool/pull/49) ([waisbrot](https://github.com/waisbrot))
- updating README and creating a default fsm worker [\#47](https://github.com/inaka/worker_pool/pull/47) ([ferigis](https://github.com/ferigis))
- Ferigis.24.gen fsm as a workers [\#43](https://github.com/inaka/worker_pool/pull/43) ([ferigis](https://github.com/ferigis))
- Version Bump to 1.1.0 [\#59](https://github.com/inaka/worker_pool/pull/59) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Fail fast if there is no spare workers in the pool [\#51](https://github.com/inaka/worker_pool/pull/51) ([michalwski](https://github.com/michalwski))
- Get the Project up to date regarding our internal rules [\#44](https://github.com/inaka/worker_pool/pull/44) ([igaray](https://github.com/igaray))
- Properly change the random implementation for R18 [\#27](https://github.com/inaka/worker_pool/pull/27) ([elbrujohalcon](https://github.com/elbrujohalcon))

## [1.0.4](https://github.com/inaka/worker_pool/tree/1.0.4) (2015-12-05)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.0.3...1.0.4)

**Closed issues:**

- wpool\_queue\_manager may leak workers [\#37](https://github.com/inaka/worker_pool/issues/37)

**Merged pull requests:**

- \[\#37\] Allocate a worker and send the job at the same time [\#42](https://github.com/inaka/worker_pool/pull/42) ([jfacorro](https://github.com/jfacorro))
- Handle gen\_server:init return with timeout [\#40](https://github.com/inaka/worker_pool/pull/40) ([dvaergiller](https://github.com/dvaergiller))
- Reduce the list of maintainers in .app.src [\#39](https://github.com/inaka/worker_pool/pull/39) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Release on Hex? [\#38](https://github.com/inaka/worker_pool/pull/38) ([waisbrot](https://github.com/waisbrot))
- wpool\_queue\_manager crash cripples worker pool [\#36](https://github.com/inaka/worker_pool/pull/36) ([marcsugiyama](https://github.com/marcsugiyama))
- worker pools do not restart after hitting the restart intensity limit [\#35](https://github.com/inaka/worker_pool/pull/35) ([marcsugiyama](https://github.com/marcsugiyama))
- Allow setting `gen\_server` options in workers [\#34](https://github.com/inaka/worker_pool/pull/34) ([X4lldux](https://github.com/X4lldux))
- Add suport for distributing work based on a hashed term [\#33](https://github.com/inaka/worker_pool/pull/33) ([JoshRagem](https://github.com/JoshRagem))
- Rebased from TT and improved dialyzation [\#31](https://github.com/inaka/worker_pool/pull/31) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Completely remove lager [\#30](https://github.com/inaka/worker_pool/pull/30) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Version Bump to 1.0.4 [\#41](https://github.com/inaka/worker_pool/pull/41) ([elbrujohalcon](https://github.com/elbrujohalcon))

## [1.0.3](https://github.com/inaka/worker_pool/tree/1.0.3) (2015-08-26)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.0.2...1.0.3)

**Closed issues:**

- R18 deprecation warning [\#25](https://github.com/inaka/worker_pool/issues/25)

**Merged pull requests:**

- Version Bump to 1.0.3 [\#29](https://github.com/inaka/worker_pool/pull/29) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Fix platform\_define string to 18 and calling timestamp\(\). [\#28](https://github.com/inaka/worker_pool/pull/28) ([joaohf](https://github.com/joaohf))
- added support for R18 and the deprecation of 'now' [\#26](https://github.com/inaka/worker_pool/pull/26) ([HernanRivasAcosta](https://github.com/HernanRivasAcosta))

## [1.0.2](https://github.com/inaka/worker_pool/tree/1.0.2) (2015-03-16)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.0.1...1.0.2)

**Merged pull requests:**

- Changelog Added [\#22](https://github.com/inaka/worker_pool/pull/22) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Remove lager runtime dependency [\#21](https://github.com/inaka/worker_pool/pull/21) ([schlagert](https://github.com/schlagert))

## [1.0.1](https://github.com/inaka/worker_pool/tree/1.0.1) (2015-02-18)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.0...1.0.1)

**Closed issues:**

- Add documentation for overrun\_warning and related config options [\#13](https://github.com/inaka/worker_pool/issues/13)
- Fulfill the open-source checklist [\#7](https://github.com/inaka/worker_pool/issues/7)

**Merged pull requests:**

- version bump [\#19](https://github.com/inaka/worker_pool/pull/19) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Respect the git://… guideline [\#18](https://github.com/inaka/worker_pool/pull/18) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Use ./rebar and $REBAR instead of just rebar [\#17](https://github.com/inaka/worker_pool/pull/17) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Contributions from @funbox [\#15](https://github.com/inaka/worker_pool/pull/15) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Fixed rebar.config to not use the git account for github. [\#14](https://github.com/inaka/worker_pool/pull/14) ([AxisOfEval](https://github.com/AxisOfEval))
- New hidden modules :ghost: [\#12](https://github.com/inaka/worker_pool/pull/12) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Enable default\_strategy customization [\#11](https://github.com/inaka/worker_pool/pull/11) ([elbrujohalcon](https://github.com/elbrujohalcon))

## [1.0](https://github.com/inaka/worker_pool/tree/1.0) (2014-09-25)
**Merged pull requests:**

- Indentation!! [\#9](https://github.com/inaka/worker_pool/pull/9) ([elbrujohalcon](https://github.com/elbrujohalcon))
- elvis config for @elvisinaka [\#8](https://github.com/inaka/worker_pool/pull/8) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Run elvis. [\#6](https://github.com/inaka/worker_pool/pull/6) ([igaray](https://github.com/igaray))
- Fulfill the open-source checklist [\#5](https://github.com/inaka/worker_pool/pull/5) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Less restrictive lager version requirement [\#4](https://github.com/inaka/worker_pool/pull/4) ([jfacorro](https://github.com/jfacorro))
- R17 ready [\#3](https://github.com/inaka/worker_pool/pull/3) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Lager update [\#2](https://github.com/inaka/worker_pool/pull/2) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Modified rebar.config to pull lager 2.0.0rc1. [\#1](https://github.com/inaka/worker_pool/pull/1) ([igaray](https://github.com/igaray))



\* *This Change Log was automatically generated by [github_changelog_generator](https://github.com/skywinder/Github-Changelog-Generator)*