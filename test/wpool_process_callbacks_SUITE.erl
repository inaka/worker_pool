-module(wpool_process_callbacks_SUITE).

-type config() :: [{atom(), term()}].

-export([ all/0
        ]).
-export([ init_per_suite/1
        , end_per_suite/1
        ]).
-export([ complete_callback_passed_when_starting_pool/1
        , partial_callback_passed_when_starting_pool/1
        ]).

-spec all() -> [atom()].
all() ->
  [ complete_callback_passed_when_starting_pool
  , partial_callback_passed_when_starting_pool].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  ok = wpool:start(),
  Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
  wpool:stop(),
  Config.


-spec complete_callback_passed_when_starting_pool(config) -> ok.
complete_callback_passed_when_starting_pool(_Config) ->
  Pool = callbacks_test,
  WorkersCount = 13,
  meck:new(callbacks, [non_strict]),
  meck:expect(callbacks, on_init_start, fun(_AWorkerName) -> ok end),
  meck:expect(callbacks, on_new_worker, fun(_AWorkerName) -> ok end),
  meck:expect(callbacks, on_worker_dead, fun(_AWorkerName, _Reason) -> ok end),
  %meck:new(only_new_worker_callback, [non_strict]),
  %meck:expect(only_new_worker_callback, on_new_worker, fun(_AWorkerName) -> ok end),
  {ok, _Pid} = wpool:start_pool(Pool, [{workers, WorkersCount},
                                       {worker, {crashy_server, []}},
                                       {callbacks, [callbacks]}]),
  timer:sleep(100),
  WorkersCount = meck:num_calls(callbacks, on_init_start, ['_']),
  WorkersCount = meck:num_calls(callbacks, on_new_worker, ['_']),
  Worker = wpool_pool:random_worker(Pool),
  Worker ! crash,
  timer:sleep(100),
  1 = meck:num_calls(callbacks, on_worker_dead, ['_', '_']),
  wpool:stop_pool(Pool),
  meck:unload(callbacks),

  ok.

-spec partial_callback_passed_when_starting_pool(config) -> ok.
partial_callback_passed_when_starting_pool(_Config) ->
  Pool = partial_callbacks_test,
  WorkersCount = 7,
  meck:new(callbacks, [non_strict]),
  meck:expect(callbacks, on_new_worker, fun(_AWorkerName) -> ok end),
  meck:expect(callbacks, on_worker_dead, fun(_AWorkerName, _Reason) -> ok end),
  {ok, _Pid} = wpool:start_pool(Pool, [{workers, WorkersCount},
                                       {worker, {crashy_server, []}},
                                       {callbacks, [callbacks]}]),
  timer:sleep(100),
  WorkersCount = meck:num_calls(callbacks, on_new_worker, ['_']),
  wpool:stop_pool(Pool),
  meck:unload(callbacks),

  ok.

