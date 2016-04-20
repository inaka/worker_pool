-module(wpool_meta_SUITE).

-include_lib("mixer/include/mixer.hrl").
-mixin([ktn_meta_SUITE]).

-export([init_per_suite/1]).

-type config() :: [{atom(), term()}].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) -> [{application, worker_pool} | Config].
