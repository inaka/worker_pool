% This file is licensed to you under the Apache License,
% Version 2.0 (the "License"); you may not use this file
% except in compliance with the License.  You may obtain
% a copy of the License at
%
% https://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing,
% software distributed under the License is distributed on an
% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
% KIND, either express or implied.  See the License for the
% specific language governing permissions and limitations
% under the License.

%% @hidden
-module(wpool_SUITE).

-behaviour(ct_suite).

-elvis([{elvis_style, atom_naming_convention, disable}]).

-type config() :: [{atom(), term()}].

-export_type([config/0]).

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([stats/1, stop_pool/1, non_brutal_shutdown/1, brutal_worker_shutdown/1, overrun/1,
         kill_on_overrun/1, too_much_overrun/1, default_strategy/1, overrun_handler1/1,
         overrun_handler2/1, default_options/1, complete_coverage/1, broadcast/1, send_request/1,
         worker_killed_stats/1]).

-elvis([{elvis_style, no_block_expressions, disable}]).

-dialyzer({no_underspecs, all/0}).

-spec all() -> [atom()].
all() ->
    [too_much_overrun,
     overrun,
     stop_pool,
     non_brutal_shutdown,
     brutal_worker_shutdown,
     stats,
     default_strategy,
     default_options,
     complete_coverage,
     broadcast,
     send_request,
     kill_on_overrun,
     worker_killed_stats].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
    ok = wpool:start(),
    Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
    wpool:stop(),
    Config.

-spec overrun_handler1(M) -> {overrun1, M}.
overrun_handler1(M) ->
    overrun_handler ! {overrun1, M}.

-spec overrun_handler2(M) -> {overrun2, M}.
overrun_handler2(M) ->
    overrun_handler ! {overrun2, M}.

-spec too_much_overrun(config()) -> {comment, []}.
too_much_overrun(_Config) ->
    ct:comment("Receiving overruns here..."),
    true = register(overrun_handler, self()),
    {ok, PoolPid} =
        wpool:start_sup_pool(wpool_SUITE_too_much_overrun,
                             [{workers, 1},
                              {overrun_warning, 999},
                              {overrun_handler, {?MODULE, overrun_handler1}}]),

    %% Sadly, the function that autogenerates this name is private.
    CheckerName = 'wpool_pool-wpool_SUITE_too_much_overrun-time-checker',

    ok = wpool_time_checker:add_handler(CheckerName, {?MODULE, overrun_handler2}),

    ct:comment("Find the worker and the time checker..."),
    {ok, Worker} = wpool:call(wpool_SUITE_too_much_overrun, {erlang, self, []}),
    TCPid = get_time_checker(PoolPid),

    ct:comment("Start a long running task..."),
    ok = wpool:cast(wpool_SUITE_too_much_overrun, {timer, sleep, [5000]}),
    TaskId =
        ktn_task:wait_for_success(fun() ->
                                     {dictionary, Dict} = erlang:process_info(Worker, dictionary),
                                     {TId, _, _} = proplists:get_value(wpool_task, Dict),
                                     TId
                                  end),

    ct:comment("Simulate overrun warning..."),
    % huge runtime => no more overruns
    TCPid ! {check, Worker, TaskId, 9999999999, infinity},

    ct:comment("Get overrun message..."),
    _ = receive
            {overrun1, Message1} ->
                overrun = proplists:get_value(alert, Message1),
                wpool_SUITE_too_much_overrun = proplists:get_value(pool, Message1),
                Worker = proplists:get_value(worker, Message1),
                {cast, {timer, sleep, [5000]}} = proplists:get_value(task, Message1),
                9999999999 = proplists:get_value(runtime, Message1)
        after 100 ->
            ct:fail(no_overrun)
        end,

    ct:comment("Get overrun message..."),
    _ = receive
            {overrun2, Message2} ->
                overrun = proplists:get_value(alert, Message2),
                wpool_SUITE_too_much_overrun = proplists:get_value(pool, Message2),
                Worker = proplists:get_value(worker, Message2),
                {cast, {timer, sleep, [5000]}} = proplists:get_value(task, Message2),
                9999999999 = proplists:get_value(runtime, Message2)
        after 100 ->
            ct:fail(no_overrun)
        end,

    ct:comment("No more overruns..."),
    _ = case get_messages(100) of
            [] ->
                ok;
            Msgs1 ->
                ct:fail({unexpected_messages, Msgs1})
        end,

    ct:comment("Kill the worker..."),
    exit(Worker, kill),

    ct:comment("Simulate overrun warning..."),
    TCPid ! {check, Worker, TaskId, 100}, % tiny runtime, to check

    ct:comment("Nothing happens..."),
    ok = no_messages(),

    ct:comment("Stop pool..."),
    ok = wpool:stop_sup_pool(wpool_SUITE_too_much_overrun),

    {comment, []}.

-spec overrun(config()) -> {comment, []}.
overrun(_Config) ->
    true = register(overrun_handler, self()),
    {ok, _Pid} =
        wpool:start_sup_pool(wpool_SUITE_overrun_pool,
                             [{workers, 1},
                              {overrun_warning, 1000},
                              {overrun_handler, {?MODULE, overrun_handler1}}]),
    ok = wpool:cast(wpool_SUITE_overrun_pool, {timer, sleep, [1500]}),
    _ = receive
            {overrun1, Message} ->
                overrun = proplists:get_value(alert, Message),
                wpool_SUITE_overrun_pool = proplists:get_value(pool, Message),
                WPid = proplists:get_value(worker, Message),
                true = is_pid(WPid),
                {cast, {timer, sleep, [1500]}} = proplists:get_value(task, Message),
                Runtime = proplists:get_value(runtime, Message),
                true = Runtime >= 1000
        after 1500 ->
            ct:fail(no_overrun)
        end,

    ok = no_messages(),

    ok = wpool:stop_sup_pool(wpool_SUITE_overrun_pool),

    {comment, []}.

-spec kill_on_overrun(config()) -> {comment, []}.
kill_on_overrun(_Config) ->
    true = register(overrun_handler, self()),
    {ok, _Pid} =
        wpool:start_sup_pool(wpool_SUITE_kill_on_overrun_pool,
                             [{workers, 1},
                              {overrun_warning, 500},
                              {max_overrun_warnings,
                               2}, %% The worker must be killed after 2 overrun
                                   %% warnings, which is after 1 secs with this
                                   %% configuration
                              {overrun_handler, {?MODULE, overrun_handler1}}]),
    ok = wpool:cast(wpool_SUITE_kill_on_overrun_pool, {timer, sleep, [2000]}),
    _ = receive
            {overrun1, Message} ->
                overrun = proplists:get_value(alert, Message),
                wpool_SUITE_kill_on_overrun_pool = proplists:get_value(pool, Message),
                WPid = proplists:get_value(worker, Message),
                true = is_pid(WPid),
                true = erlang:is_process_alive(WPid)
        after 2000 ->
            ct:fail(no_overrun)
        end,

    _ = receive
            {overrun1, Message2} ->
                max_overrun_limit = proplists:get_value(alert, Message2),
                wpool_SUITE_kill_on_overrun_pool = proplists:get_value(pool, Message2),
                WPid2 = proplists:get_value(worker, Message2),
                true = is_pid(WPid2),
                false = erlang:is_process_alive(WPid2)
        after 2000 ->
            ct:fail(no_overrun)
        end,
    ok = no_messages(),

    ok = wpool:stop_sup_pool(wpool_SUITE_overrun_pool),

    {comment, []}.

-spec stop_pool(config()) -> {comment, []}.
stop_pool(_Config) ->
    {ok, PoolPid} = wpool:start_sup_pool(wpool_SUITE_stop_pool, [{workers, 1}]),
    true = erlang:is_process_alive(PoolPid),
    ok = wpool:stop_sup_pool(wpool_SUITE_stop_pool),
    false = erlang:is_process_alive(PoolPid),
    ok = wpool:stop_sup_pool(wpool_SUITE_stop_pool),

    {comment, []}.

-spec non_brutal_shutdown(config()) -> {comment, []}.
non_brutal_shutdown(_Config) ->
    {ok, PoolPid} =
        wpool:start_sup_pool(wpool_SUITE_non_brutal_shutdown,
                             [{workers, 1}, {pool_sup_shutdown, 100}]),
    true = erlang:is_process_alive(PoolPid),
    Stats = wpool:stats(wpool_SUITE_non_brutal_shutdown),
    {workers, [{WorkerId, _}]} = lists:keyfind(workers, 1, Stats),
    Worker = wpool_pool:worker_name(wpool_SUITE_non_brutal_shutdown, WorkerId),
    monitor(process, Worker),
    ok = wpool:stop_sup_pool(wpool_SUITE_non_brutal_shutdown),
    receive
        {'DOWN', _, process, {Worker, _}, Reason} ->
            shutdown = Reason
    after 200 ->
        ct:fail(worker_not_stopped)
    end,

    {comment, []}.

-spec brutal_worker_shutdown(config()) -> {comment, []}.
brutal_worker_shutdown(_Config) ->
    {ok, PoolPid} =
        wpool:start_sup_pool(wpool_SUITE_non_brutal_shutdown,
                             [{workers, 1},
                              {pool_sup_shutdown, 100},
                              {worker_shutdown, brutal_kill}]),
    true = erlang:is_process_alive(PoolPid),
    Stats = wpool:stats(wpool_SUITE_non_brutal_shutdown),
    {workers, [{WorkerId, _}]} = lists:keyfind(workers, 1, Stats),
    Worker = wpool_pool:worker_name(wpool_SUITE_non_brutal_shutdown, WorkerId),
    monitor(process, Worker),
    ok = wpool:stop_sup_pool(wpool_SUITE_non_brutal_shutdown),
    receive
        {'DOWN', _, process, {Worker, _}, Reason} ->
            killed = Reason
    after 200 ->
        ct:fail(worker_not_stopped)
    end,

    {comment, []}.

-spec stats(config()) -> {comment, []}.
stats(_Config) ->
    Get = fun proplists:get_value/2,

    ok =
        try
            _ = wpool:stats(?MODULE),
            ok
        catch
            _:no_workers ->
                ok
        end,

    {ok, PoolPid} = wpool:start_sup_pool(wpool_SUITE_stats_pool, [{workers, 10}]),
    true = is_process_alive(PoolPid),
    PoolPid = erlang:whereis(wpool_SUITE_stats_pool),

    % Checks ...
    [InitStats] = wpool:stats(),
    wpool_SUITE_stats_pool = Get(pool, InitStats),
    PoolPid = Get(supervisor, InitStats),
    Options = Get(options, InitStats),
    infinity = Get(overrun_warning, Options),
    {error_logger, warning_report} = Get(overrun_handler, Options),
    10 = Get(workers, Options),
    10 = Get(size, InitStats),
    1 = Get(next_worker, InitStats),
    InitWorkers = Get(workers, InitStats),
    10 = length(InitWorkers),
    _ = [begin
             WorkerStats = Get(I, InitWorkers),
             0 = Get(message_queue_len, WorkerStats),
             [] = lists:keydelete(message_queue_len, 1, lists:keydelete(memory, 1, WorkerStats))
         end
         || I <- lists:seq(1, 10)],

    % Start a long task on every worker
    Sleep = {timer, sleep, [2000]},
    [wpool:cast(wpool_SUITE_stats_pool, Sleep, next_worker) || _ <- lists:seq(1, 10)],

    ok =
        ktn_task:wait_for_success(fun() ->
                                     WorkingStats = wpool:stats(wpool_SUITE_stats_pool),
                                     wpool_SUITE_stats_pool = Get(pool, WorkingStats),
                                     PoolPid = Get(supervisor, WorkingStats),
                                     Options = Get(options, WorkingStats),
                                     10 = Get(size, WorkingStats),
                                     1 = Get(next_worker, WorkingStats),
                                     WorkingWorkers = Get(workers, WorkingStats),
                                     10 = length(WorkingWorkers),
                                     [begin
                                          WorkerStats = Get(I, WorkingWorkers),
                                          0 = Get(message_queue_len, WorkerStats),
                                          {timer, sleep, 1} = Get(current_function, WorkerStats),
                                          {timer, sleep, 1, _} = Get(current_location, WorkerStats),
                                          {cast, Sleep} = Get(task, WorkerStats),
                                          true = is_number(Get(runtime, WorkerStats))
                                      end
                                      || I <- lists:seq(1, 10)],
                                     ok
                                  end),

    wpool:stop_sup_pool(wpool_SUITE_stats_pool),

    no_workers =
        ktn_task:wait_for(fun() ->
                             try
                                 wpool:stats(wpool_SUITE_stats_pool)
                             catch
                                 _:E ->
                                     E
                             end
                          end,
                          no_workers,
                          100,
                          50),

    {comment, []}.

-spec default_strategy(config()) -> {comment, []}.
default_strategy(_Config) ->
    application:unset_env(worker_pool, default_strategy),
    available_worker = wpool:default_strategy(),
    application:set_env(worker_pool, default_strategy, best_worker),
    best_worker = wpool:default_strategy(),
    application:unset_env(worker_pool, default_strategy),
    available_worker = wpool:default_strategy(),
    {comment, []}.

-spec default_options(config()) -> {comment, []}.
default_options(_Config) ->
    ct:comment("Starts a pool with default options"),
    {ok, PoolPid} = wpool:start_pool(default_pool),
    true = is_pid(PoolPid),

    ct:comment("Starts a supervised pool with default options"),
    {ok, SupPoolPid} = wpool:start_sup_pool(default_sup_pool),
    true = is_pid(SupPoolPid),

    {comment, []}.

-spec complete_coverage(config()) -> {comment, []}.
complete_coverage(_Config) ->
    ct:comment("Time checker"),
    {ok, _} = wpool_time_checker:init({pool, [{x, y}]}),

    {ok, PoolPid} = wpool:start_pool(coverage, []),
    TCPid = get_time_checker(PoolPid),
    TCPid ! info,
    ok = gen_server:cast(TCPid, cast),

    ct:comment("Queue Manager"),
    QMPid = get_queue_manager(PoolPid),
    QMPid ! info,
    {ok, _} = wpool_queue_manager:init([{pool, pool}]),

    {comment, []}.

-spec broadcast(config()) -> {comment, []}.
broadcast(_Config) ->
    Pool = broadcast,
    WorkersCount = 19,
    {ok, _Pid} = wpool:start_pool(Pool, [{workers, WorkersCount}]),

    ct:comment("Check mecked function is called ~p times.", [WorkersCount]),
    meck:new(x, [non_strict]),
    meck:expect(x, x, fun() -> ok end),
    % Broadcast x:x() execution to workers.
    wpool:broadcast(Pool, {x, x, []}),
    % Give some time for the workers to perform the calls.
    WorkersCount = ktn_task:wait_for(fun() -> meck:num_calls(x, x, '_') end, WorkersCount),

    ct:comment("Check they all are \"working\""),
    % Make all the workers sleep for 1.5 seconds
    wpool:broadcast(Pool, {timer, sleep, [1500]}),
    % check they all are actually busy (executing timer:sleep/1 function).
    try
        wpool:call(Pool, {io, format, ["I am awake.~n"]}, next_available_worker),
        ct:fail("There was at least 1 worker available")
    catch
        _:no_available_workers ->
            ok
    end,

    meck:unload(x),
    {comment, []}.

-spec send_request(config()) -> {comment, []}.
send_request(_Config) ->
    Pool = send_request,
    {ok, _Pid} = wpool:start_pool(Pool, []),

    ct:comment("Check that the request can be placed"),
    send_request_to_worker(Pool),

    ct:comment("Check the hash_worker strategy"),
    send_request_to_worker(Pool, {hash_worker, key}),

    ct:comment("Check the random_worker strategy"),
    send_request_to_worker(Pool, random_worker),

    {comment, []}.

-spec worker_killed_stats(config()) -> {comment, []}.
worker_killed_stats(_Config) ->
    %% Each server will take 100ms to start, but the start_sup_pool/2 call is synchronous anyway
    {ok, PoolPid} =
        wpool:start_sup_pool(wpool_SUITE_worker_killed_stats,
                             [{workers, 3}, {worker, {sleepy_server, 500}}]),
    true = erlang:is_process_alive(PoolPid),

    Workers =
        fun() -> lists:keyfind(workers, 1, wpool:stats(wpool_SUITE_worker_killed_stats)) end,
    WorkerName = wpool_pool:worker_name(wpool_SUITE_worker_killed_stats, 1),

    ct:comment("wpool:stats/1 should work normally"),
    {workers, [_, _, _]} = Workers(),

    ct:comment("wpool:stats/1 should work even if a process just dies and it's not yet back alive"),
    exit(whereis(WorkerName), kill),
    {workers, [_, _]} = Workers(),

    ct:comment("Once the process is alive again, we should see it at the stats"),
    true = ktn_task:wait_for(fun() -> is_pid(whereis(WorkerName)) end, true, 10, 75),
    {workers, [_, _, _]} = Workers(),

    {comment, []}.

%% =============================================================================
%% Helpers
%% =============================================================================
get_time_checker(PoolPid) ->
    [TCPid] =
        [P || {_, P, worker, [wpool_time_checker]} <- supervisor:which_children(PoolPid)],
    TCPid.

get_queue_manager(PoolPid) ->
    [QMPid] =
        [P || {_, P, worker, [wpool_queue_manager]} <- supervisor:which_children(PoolPid)],
    QMPid.

get_messages(MaxTimeout) ->
    get_messages(MaxTimeout, []).

get_messages(MaxTimeout, Acc) ->
    receive
        Any ->
            get_messages(MaxTimeout, [Any | Acc])
    after MaxTimeout ->
        Acc
    end.

no_messages() ->
    case get_messages(1000) of
        [] ->
            ok;
        Msgs2 ->
            ct:fail({unexpected_messages, Msgs2})
    end.

send_request_to_worker(Pool) ->
    ReqId = wpool:send_request(Pool, {erlang, self, []}),
    wait_response(ReqId).

send_request_to_worker(Pool, Strategy) ->
    ReqId = wpool:send_request(Pool, {erlang, self, []}, Strategy),
    wait_response(ReqId).

wait_response(ReqId) ->
    case gen_server:wait_response(ReqId, 5000) of
        {reply, {ok, _}} ->
            ok;
        timeout ->
            ct:fail("no response")
    end.
