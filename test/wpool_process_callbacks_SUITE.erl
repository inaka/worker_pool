-module(wpool_process_callbacks_SUITE).

-behaviour(ct_suite).

-type config() :: [{atom(), term()}].

-export_type([config/0]).

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([complete_callback_passed_when_starting_pool/1,
         partial_callback_passed_when_starting_pool/1,
         callback_can_be_added_and_removed_after_pool_is_started/1,
         crashing_callback_does_not_affect_others/1, non_existsing_module_does_not_affect_others/1,
         complete_coverage/1]).

-dialyzer({no_underspecs, all/0}).

-spec all() -> [atom()].
all() ->
    [complete_callback_passed_when_starting_pool,
     partial_callback_passed_when_starting_pool,
     callback_can_be_added_and_removed_after_pool_is_started,
     crashing_callback_does_not_affect_others,
     non_existsing_module_does_not_affect_others].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
    ok = wpool:start(),
    Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
    wpool:stop(),
    Config.

-spec complete_callback_passed_when_starting_pool(config()) -> ok.
complete_callback_passed_when_starting_pool(_Config) ->
    Pool = callbacks_test,
    WorkersCount = 13,
    meck:new(callbacks, [non_strict]),
    meck:expect(callbacks, handle_init_start, fun(_AWorkerName) -> ok end),
    meck:expect(callbacks, handle_worker_creation, fun(_AWorkerName) -> ok end),
    meck:expect(callbacks, handle_worker_death, fun(_AWName, _Reason) -> ok end),
    {ok, _Pid} =
        wpool:start_pool(Pool,
                         [{workers, WorkersCount},
                          {enable_callbacks, true},
                          {worker, {crashy_server, []}},
                          {callbacks, [callbacks]}]),

    WorkersCount =
        ktn_task:wait_for(function_calls(callbacks, handle_init_start, ['_']), WorkersCount),
    WorkersCount =
        ktn_task:wait_for(function_calls(callbacks, handle_worker_creation, ['_']), WorkersCount),
    Worker = wpool_pool:random_worker(Pool),
    Worker ! crash,
    1 = ktn_task:wait_for(function_calls(callbacks, handle_worker_death, ['_', '_']), 1),
    wpool:stop_pool(Pool),
    meck:unload(callbacks),

    ok.

-spec partial_callback_passed_when_starting_pool(config) -> ok.
partial_callback_passed_when_starting_pool(_Config) ->
    Pool = partial_callbacks_test,
    WorkersCount = 7,
    meck:new(callbacks, [non_strict]),
    meck:expect(callbacks, handle_worker_creation, fun(_AWorkerName) -> ok end),
    meck:expect(callbacks, handle_worker_death, fun(_AWName, _Reason) -> ok end),
    {ok, _Pid} =
        wpool:start_pool(Pool,
                         [{workers, WorkersCount},
                          {enable_callbacks, true},
                          {callbacks, [callbacks]}]),
    WorkersCount =
        ktn_task:wait_for(function_calls(callbacks, handle_worker_creation, ['_']), WorkersCount),
    wpool:stop_pool(Pool),
    meck:unload(callbacks),

    ok.

-spec callback_can_be_added_and_removed_after_pool_is_started(config()) -> ok.
callback_can_be_added_and_removed_after_pool_is_started(_Config) ->
    Pool = after_start_callbacks_test,
    WorkersCount = 3,
    meck:new(callbacks, [non_strict]),
    meck:expect(callbacks, handle_worker_death, fun(_AWName, _Reason) -> ok end),
    meck:new(callbacks2, [non_strict]),
    meck:expect(callbacks2, handle_worker_death, fun(_AWName, _Reason) -> ok end),
    {ok, _Pid} =
        wpool:start_pool(Pool,
                         [{workers, WorkersCount},
                          {worker, {crashy_server, []}},
                          {enable_callbacks, true}]),
    %% Now we are adding 2 callback modules
    _ = wpool_pool:add_callback_module(Pool, callbacks),
    _ = wpool_pool:add_callback_module(Pool, callbacks2),
    Worker = wpool_pool:random_worker(Pool),
    Worker ! crash,

    %% they both are called
    1 = ktn_task:wait_for(function_calls(callbacks, handle_worker_death, ['_', '_']), 1),
    1 = ktn_task:wait_for(function_calls(callbacks2, handle_worker_death, ['_', '_']), 1),

    %% then the first module is removed
    _ = wpool_pool:remove_callback_module(Pool, callbacks),
    Worker2 = wpool_pool:random_worker(Pool),
    Worker2 ! crash,

    %% and only the scond one is called
    1 = ktn_task:wait_for(function_calls(callbacks, handle_worker_death, ['_', '_']), 1),
    2 = ktn_task:wait_for(function_calls(callbacks2, handle_worker_death, ['_', '_']), 2),

    wpool:stop_pool(Pool),
    meck:unload(callbacks),
    meck:unload(callbacks2),

    ok.

-spec crashing_callback_does_not_affect_others(config()) -> ok.
crashing_callback_does_not_affect_others(_Config) ->
    Pool = crashing_callbacks_test,
    WorkersCount = 3,
    meck:new(callbacks, [non_strict]),
    meck:expect(callbacks, handle_worker_creation, fun(_AWorkerName) -> ok end),
    meck:new(callbacks2, [non_strict]),
    meck:expect(callbacks2,
                handle_worker_creation,
                fun(AWorkerName) -> {not_going_to_work} = AWorkerName end),
    {ok, _Pid} =
        wpool:start_pool(Pool,
                         [{workers, WorkersCount},
                          {worker, {crashy_server, []}},
                          {enable_callbacks, true},
                          {callbacks, [callbacks, callbacks2]}]),

    WorkersCount =
        ktn_task:wait_for(function_calls(callbacks, handle_worker_creation, ['_']), WorkersCount),
    WorkersCount =
        ktn_task:wait_for(function_calls(callbacks2, handle_worker_creation, ['_']),
                          WorkersCount),

    wpool:stop_pool(Pool),
    meck:unload(callbacks),
    meck:unload(callbacks2),

    ok.

-spec non_existsing_module_does_not_affect_others(config()) -> ok.
non_existsing_module_does_not_affect_others(_Config) ->
    Pool = non_existing_callbacks_test,
    WorkersCount = 4,
    meck:new(callbacks, [non_strict]),
    meck:expect(callbacks, handle_worker_creation, fun(_AWorkerName) -> ok end),
    {ok, _Pid} =
        wpool:start_pool(Pool,
                         [{workers, WorkersCount},
                          {worker, {crashy_server, []}},
                          {enable_callbacks, true},
                          {callbacks, [callbacks, non_existing_m]}]),

    {error, nofile} = wpool_pool:add_callback_module(Pool, non_existing_m2),

    WorkersCount =
        ktn_task:wait_for(function_calls(callbacks, handle_worker_creation, ['_']), WorkersCount),

    wpool:stop_pool(Pool),
    meck:unload(callbacks),

    ok.

function_calls(Module, Function, MeckMatchSpec) ->
    fun() -> meck:num_calls(Module, Function, MeckMatchSpec) end.

-spec complete_coverage(config()) -> ok.
complete_coverage(_Config) ->
    {ok, EventManager} = gen_event:start_link(),
    gen_event:add_handler(EventManager, {wpool_process_callbacks, ?MODULE}, ?MODULE),
    {error, {unexpected_call, call}} =
        gen_event:call(EventManager, {wpool_process_callbacks, ?MODULE}, call),
    ok.
