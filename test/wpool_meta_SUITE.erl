-module(wpool_meta_SUITE).

-include_lib("mixer/include/mixer.hrl").
-mixin([{ktn_meta_SUITE, [dialyzer/1, elvis/1]}]).

-export([init_per_suite/1, end_per_suite/1]).

-type config() :: [{atom(), term()}].

-export([all/0]).

-spec all() -> [dialyzer | elvis].
all() -> [dialyzer, elvis].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) -> [{application, worker_pool} | Config].

-spec end_per_suite(config()) -> config().
end_per_suite(Config) -> Config.
