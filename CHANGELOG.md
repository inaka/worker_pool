# Change Log

## [1.1.0](https://github.com/inaka/worker_pool/tree/1.1.0) (2016-04-28)
[Full Changelog](https://github.com/inaka/worker_pool/compare/1.0.4...1.1.0)

**Fixed bugs:**

- master is not working with rebar3 projects [\#58](https://github.com/inaka/worker_pool/pull/58) ([akalyaev](https://github.com/akalyaev))

**Closed issues:**

- Wrong typespec for strategy\(\) [\#48](https://github.com/inaka/worker_pool/issues/48)
- Add wpool\_fsm\_process tests [\#46](https://github.com/inaka/worker_pool/issues/46)
- Update README.md [\#45](https://github.com/inaka/worker_pool/issues/45)
- Possibility to create anonymous pools? [\#32](https://github.com/inaka/worker_pool/issues/32)
- gen\_fsm as workers [\#24](https://github.com/inaka/worker_pool/issues/24)
- Update Dependencies [\#23](https://github.com/inaka/worker_pool/issues/23)
- Worker recycling/expiration [\#20](https://github.com/inaka/worker_pool/issues/20)
- ability to provide custom strategies [\#16](https://github.com/inaka/worker_pool/issues/16)

**Merged pull requests:**

- Update README.md [\#55](https://github.com/inaka/worker_pool/pull/55) ([elbrujohalcon](https://github.com/elbrujohalcon))
- Ferigis.46.adding fsm tests [\#54](https://github.com/inaka/worker_pool/pull/54) ([ferigis](https://github.com/ferigis))
- Replacement for \#47 [\#53](https://github.com/inaka/worker_pool/pull/53) ([elbrujohalcon](https://github.com/elbrujohalcon))
- handle custom strategy functions [\#52](https://github.com/inaka/worker_pool/pull/52) ([benoitc](https://github.com/benoitc))
- Fail fast if there is no spare workers in the pool [\#51](https://github.com/inaka/worker_pool/pull/51) ([michalwski](https://github.com/michalwski))
- Updated wpool stats/0 type specification [\#50](https://github.com/inaka/worker_pool/pull/50) ([akalyaev](https://github.com/akalyaev))
- Fix the typespec for the hash\_worker strategy [\#49](https://github.com/inaka/worker_pool/pull/49) ([waisbrot](https://github.com/waisbrot))
- updating README and creating a default fsm worker [\#47](https://github.com/inaka/worker_pool/pull/47) ([ferigis](https://github.com/ferigis))
- Get the Project up to date regarding our internal rules [\#44](https://github.com/inaka/worker_pool/pull/44) ([igaray](https://github.com/igaray))
- Ferigis.24.gen fsm as a workers [\#43](https://github.com/inaka/worker_pool/pull/43) ([ferigis](https://github.com/ferigis))
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