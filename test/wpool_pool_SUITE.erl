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
-module(wpool_pool_SUITE).

-behaviour(ct_suite).

-type config() :: [{atom(), term()}].

-export_type([config/0]).

-define(WORKERS, 6).

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([stop_worker/1, best_worker/1, next_worker/1, random_worker/1, available_worker/1,
         hash_worker/1, custom_worker/1, next_available_worker/1, wpool_record/1,
         queue_type_fifo/1, queue_type_lifo/1, get_workers/1]).
-export([manager_crash/1, super_fast/1, mess_up_with_store/1]).

-elvis([{elvis_style, no_block_expressions, disable}]).
-elvis([{elvis_style, no_catch_expressions, disable}]).

-spec all() -> [atom()].
all() ->
    [Fun
     || {Fun, 1} <- module_info(exports),
        not lists:member(Fun, [init_per_suite, end_per_suite, module_info])].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
    ok = wpool:start(),
    Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
    wpool:stop(),
    Config.

-spec init_per_testcase(atom(), config()) -> config().
init_per_testcase(queue_type_lifo = TestCase, Config) ->
    {ok, _} = wpool:start_pool(TestCase, [{workers, 1}, {queue_type, lifo}]),
    Config;
init_per_testcase(queue_type_fifo = TestCase, Config) ->
    {ok, _} = wpool:start_pool(TestCase, [{workers, 1}, {queue_type, fifo}]),
    Config;
init_per_testcase(TestCase, Config) ->
    {ok, _} = wpool:start_pool(TestCase, [{workers, ?WORKERS}]),
    Config.

-spec end_per_testcase(atom(), config()) -> config().
end_per_testcase(TestCase, Config) ->
    catch wpool:stop_sup_pool(TestCase),
    Config.

-spec stop_worker(config()) -> {comment, []}.
stop_worker(_Config) ->
    true = undefined /= wpool_pool:find_wpool(stop_worker),
    true = wpool:stop_pool(stop_worker),
    undefined = ktn_task:wait_for(fun() -> wpool_pool:find_wpool(stop_worker) end, undefined),
    true = wpool:stop_pool(stop_worker),
    undefined = wpool_pool:find_wpool(stop_worker),
    {comment, ""}.

-spec available_worker(config()) -> {comment, []}.
available_worker(_Config) ->
    Pool = available_worker,
    try wpool:call(not_a_pool, x) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    ct:log("Put them all to work, each request should go to a different worker"),
    [wpool:cast(Pool, {timer, sleep, [5000]}) || _ <- lists:seq(1, ?WORKERS)],

    [0] = ktn_task:wait_for(fun() -> worker_msg_queue_lengths(Pool) end, [0]),

    ct:log("Now send another round of messages,
     the workers queues should still be empty"),
    [wpool:cast(Pool, {timer, sleep, [100 * I]}) || I <- lists:seq(1, ?WORKERS)],

    % Check that we have ?WORKERS pending tasks
    ?WORKERS =
        ktn_task:wait_for(fun() ->
                             Stats1 = wpool:stats(Pool),
                             [0] =
                                 lists:usort([proplists:get_value(message_queue_len, WS)
                                              || {_, WS} <- proplists:get_value(workers, Stats1)]),
                             proplists:get_value(total_message_queue_len, Stats1)
                          end,
                          ?WORKERS),

    ct:log("If we can't wait we get no workers"),
    try wpool:call(Pool, {erlang, self, []}, available_worker, 100) of
        R ->
            should_fail = R
    catch
        _:Error ->
            timeout = Error
    end,

    ct:log("Let's wait until all workers are free"),
    wpool:call(Pool, {erlang, self, []}, available_worker, infinity),

    % Check we have no pending tasks
    Stats2 = wpool:stats(Pool),
    0 = proplists:get_value(total_message_queue_len, Stats2),

    ct:log("Now they all should be free"),
    ct:log("We get half of them working for a while"),
    [wpool:cast(Pool, {timer, sleep, [60000]}) || _ <- lists:seq(1, ?WORKERS, 2)],

    % Check we have no pending tasks
    0 =
        ktn_task:wait_for(fun() -> proplists:get_value(total_message_queue_len, wpool:stats(Pool))
                          end,
                          0),

    ct:log("We run tons of calls, and none is blocked,
     because all of them are handled by different workers"),
    Workers =
        [wpool:call(Pool, {erlang, self, []}, available_worker, 5000)
         || _ <- lists:seq(1, 20 * ?WORKERS)],
    UniqueWorkers =
        sets:to_list(
            sets:from_list(Workers)),
    {?WORKERS, UniqueWorkers, true} =
        {?WORKERS, UniqueWorkers, ?WORKERS / 2 >= length(UniqueWorkers)},

    {comment, []}.

-spec best_worker(config()) -> {comment, []}.
best_worker(_Config) ->
    Pool = best_worker,
    try wpool:call(not_a_pool, x, best_worker) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    %% Fill up their message queues...
    [wpool:cast(Pool, {timer, sleep, [60000]}, next_worker) || _ <- lists:seq(1, ?WORKERS)],
    [0] = ktn_task:wait_for(fun() -> worker_msg_queue_lengths(Pool) end, [0]),

    [wpool:cast(Pool, {timer, sleep, [60000]}, best_worker) || _ <- lists:seq(1, ?WORKERS)],

    [1] = ktn_task:wait_for(fun() -> worker_msg_queue_lengths(Pool) end, [1]),

    %% Now try best worker once per worker
    [wpool:cast(Pool, {timer, sleep, [60000]}, best_worker) || _ <- lists:seq(1, ?WORKERS)],
    %% The load should be evenly distributed...
    [2] = ktn_task:wait_for(fun() -> worker_msg_queue_lengths(Pool) end, [2]),

    {comment, []}.

-spec next_available_worker(config()) -> {comment, []}.
next_available_worker(_Config) ->
    Pool = next_available_worker,
    ct:log("not_a_pool is not a pool"),
    try wpool:call(not_a_pool, x, next_available_worker) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    ct:log("Put them all to work..."),
    [wpool:cast(Pool, {timer, sleep, [1500 + I]}, next_available_worker)
     || I <- lists:seq(0, (?WORKERS - 1) * 60000, 60000)],

    AvailableWorkers =
        fun() ->
           length([a_worker
                   || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool)),
                      proplists:get_value(task, WS) == undefined])
        end,

    ct:log("All busy..."),
    0 = ktn_task:wait_for(AvailableWorkers, 0),

    ct:log("No available workers..."),
    try wpool:cast(Pool, {timer, sleep, [60000]}, next_available_worker) of
        ok ->
            ct:fail("Exception expected")
    catch
        _:no_available_workers ->
            ok
    end,

    ct:log("Wait until the first frees up..."),
    1 = ktn_task:wait_for(AvailableWorkers, 1),

    ok = wpool:cast(Pool, {timer, sleep, [60000]}, next_available_worker),

    ct:log("No more available workers..."),
    try wpool:cast(Pool, {timer, sleep, [60000]}, next_available_worker) of
        ok ->
            ct:fail("Exception expected")
    catch
        _:no_available_workers ->
            ok
    end,

    {comment, []}.

-spec next_worker(config()) -> {comment, []}.
next_worker(_Config) ->
    Pool = next_worker,

    try wpool:call(not_a_pool, x, next_worker) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    Res0 =
        [begin
             Stats = wpool:stats(Pool),
             I = proplists:get_value(next_worker, Stats),
             wpool:call(Pool, {erlang, self, []}, next_worker, infinity)
         end
         || I <- lists:seq(1, ?WORKERS)],
    ?WORKERS =
        sets:size(
            sets:from_list(Res0)),
    Res0 =
        [begin
             Stats = wpool:stats(Pool),
             I = proplists:get_value(next_worker, Stats),
             wpool:call(Pool, {erlang, self, []}, next_worker)
         end
         || I <- lists:seq(1, ?WORKERS)],

    {comment, []}.

-spec random_worker(config()) -> {comment, []}.
random_worker(_Config) ->
    Pool = random_worker,

    try wpool:call(not_a_pool, x, random_worker) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    %% Ask for a random worker's identity 20x more than the number of workers
    %% and expect to get an answer from every worker at least once.
    Serial =
        [wpool:call(Pool, {erlang, self, []}, random_worker) || _ <- lists:seq(1, 20 * ?WORKERS)],
    ?WORKERS =
        sets:size(
            sets:from_list(Serial)),

    %% Now do the same with a freshly spawned process for each request to ensure
    %% randomness isn't reset with each spawn of the process_dictionary
    Self = self(),
    _ = [spawn(fun() ->
                  WorkerId = wpool:call(Pool, {erlang, self, []}, random_worker),
                  Self ! {worker, WorkerId}
               end)
         || _ <- lists:seq(1, 20 * ?WORKERS)],
    Concurrent = collect_results(20 * ?WORKERS, []),
    ?WORKERS =
        sets:size(
            sets:from_list(Concurrent)),

    {comment, []}.

-spec hash_worker(config()) -> {comment, []}.
hash_worker(_Config) ->
    Pool = hash_worker,

    try wpool:call(not_a_pool, x, {hash_worker, 1}) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    %% Use two hash keys that have different values (0, 1) to target only
    %% two workers. Other workers should be missing.
    Targeted =
        [wpool:call(Pool, {erlang, self, []}, {hash_worker, I rem 2})
         || I <- lists:seq(1, 20 * ?WORKERS)],
    2 =
        sets:size(
            sets:from_list(Targeted)),

    %% Now use many different hash keys. All workers should be hit.
    Spread =
        [wpool:call(Pool, {erlang, self, []}, {hash_worker, I})
         || I <- lists:seq(1, 20 * ?WORKERS)],
    ?WORKERS =
        sets:size(
            sets:from_list(Spread)),

    %% Fill up their message queues...
    [wpool:cast(Pool, {timer, sleep, [60000]}, {hash_worker, I})
     || I <- lists:seq(1, 20 * ?WORKERS)],

    false =
        ktn_task:wait_for(fun() -> lists:member(0, worker_msg_queue_lengths(Pool)) end, false),

    {comment, []}.

-spec custom_worker(config()) -> {comment, []}.
custom_worker(_Config) ->
    Pool = custom_worker,

    Strategy = fun wpool_pool:next_worker/1,

    try wpool:call(not_a_pool, x, Strategy) of
        Result ->
            no_result = Result
    catch
        _:no_workers ->
            ok
    end,

    _ = [begin
             Stats = wpool:stats(Pool),
             I = proplists:get_value(next_worker, Stats),
             wpool:cast(Pool, {io, format, ["ok!"]}, Strategy)
         end
         || I <- lists:seq(1, ?WORKERS)],

    Res0 =
        [begin
             Stats = wpool:stats(Pool),
             I = proplists:get_value(next_worker, Stats),
             wpool:call(Pool, {erlang, self, []}, Strategy, infinity)
         end
         || I <- lists:seq(1, ?WORKERS)],
    ?WORKERS =
        sets:size(
            sets:from_list(Res0)),
    Res0 =
        [begin
             Stats = wpool:stats(Pool),
             I = proplists:get_value(next_worker, Stats),
             wpool:call(Pool, {erlang, self, []}, Strategy)
         end
         || I <- lists:seq(1, ?WORKERS)],

    {comment, []}.

-spec manager_crash(config()) -> {comment, []}.
manager_crash(_Config) ->
    Pool = manager_crash,
    QueueManager = 'wpool_pool-manager_crash-queue-manager',

    ct:log("Check that the pool is working"),
    {ok, ok} = send_io_format(Pool),

    OldPid = whereis(QueueManager),

    ct:log("Crash the pool manager"),
    exit(whereis(QueueManager), kill),

    false =
        ktn_task:wait_for(fun() -> lists:member(whereis(QueueManager), [OldPid, undefined]) end,
                          false),

    ct:log("Check that the pool is working again"),
    {ok, ok} = send_io_format(Pool),

    {comment, []}.

-spec super_fast(config()) -> {comment, []}.
super_fast(_Config) ->
    Pool = super_fast,

    ct:log("Check that the pool is working"),
    {ok, ok} = send_io_format(Pool),

    ct:log("Impossible task"),
    Self = self(),
    try wpool:call(Pool, {erlang, send, [Self, something]}, available_worker, 0) of
        R ->
            ct:fail("Unexpected ~p", [R])
    catch
        _:timeout ->
            ok
    end,

    ct:log("Wait a second and nothing gets here"),
    receive
        X ->
            ct:fail("Unexpected ~p", [X])
    after 1000 ->
        ok
    end,

    {comment, []}.

-spec queue_type_fifo(config()) -> {comment, []}.
queue_type_fifo(_Config) ->
    Pool = queue_type_fifo,
    Self = self(),
    TasksNumber = 10,
    Tasks = lists:seq(1, TasksNumber),

    ct:log("Pretend worker is busy"),
    wpool:cast(Pool, {timer, sleep, [timer:seconds(2)]}),

    ct:log("Cast 10 enumerated tasks. Tasks should be queued because worker is busy."),
    cast_tasks(Pool, TasksNumber, Self),

    ct:log("Collect task results"),
    Result = collect_tasks(TasksNumber),

    ct:log("Check if tasks were performd in FIFO order."),
    Result = Tasks,

    {comment, []}.

-spec queue_type_lifo(config()) -> {comment, []}.
queue_type_lifo(_Config) ->
    Pool = queue_type_lifo,
    Self = self(),
    TasksNumber = 10,
    Tasks = lists:seq(1, TasksNumber),

    ct:log("Pretend worker is busy"),
    wpool:cast(Pool, {timer, sleep, [timer:seconds(4)]}),

    ct:log("Cast 10 enumerated tasks. Tasks should be queued because worker is busy."),
    cast_tasks(Pool, TasksNumber, Self),

    ct:log("Collect task results"),
    Result = collect_tasks(TasksNumber),

    ct:log("Check if tasks were performd in LIFO order."),
    Result = lists:reverse(Tasks),

    {comment, []}.

-spec get_workers(config()) -> {comment, []}.
get_workers(_Config) ->
    Pool = get_workers,

    ct:log("Verify that there's the correct number of workers"),
    Workers = wpool:get_workers(Pool),
    ?WORKERS = length(Workers),

    ct:log("All workers are alive"),
    true = lists:all(fun(Whereis) -> Whereis =/= undefined end, Workers),

    {comment, []}.

-spec wpool_record(config()) -> {comment, []}.
wpool_record(_Config) ->
    WPool = wpool_pool:find_wpool(wpool_record),
    wpool_record = wpool_pool:wpool_get(name, WPool),
    6 = wpool_pool:wpool_get(size, WPool),
    [_, _, _, _] = wpool_pool:wpool_get([next, opts, qmanager, born], WPool),

    WPool2 = wpool_pool:next(3, WPool),
    3 = wpool_pool:wpool_get(next, WPool2),

    {comment, []}.

-spec mess_up_with_store(config()) -> {comment, []}.
mess_up_with_store(_Config) ->
    Pool = mess_up_with_store,

    ct:comment("Mess up with ets table..."),
    store_mess_up(Pool),

    ct:comment("Rebuild stats"),
    1 = proplists:get_value(next_worker, wpool:stats(Pool)),

    ct:comment("Mess up with ets table again..."),
    store_mess_up(Pool),
    {ok, ok} = wpool:call(Pool, {io, format, ["1!~n"]}, random_worker),

    ct:comment("Mess up with ets table once more..."),
    {ok, ok} = wpool:call(Pool, {io, format, ["2!~n"]}, next_worker),
    2 = proplists:get_value(next_worker, wpool:stats(Pool)),
    store_mess_up(Pool),
    {ok, ok} = wpool:call(Pool, {io, format, ["3!~n"]}, next_worker),
    2 = proplists:get_value(next_worker, wpool:stats(Pool)),

    ct:comment("Mess up with ets table one final time..."),
    store_mess_up(Pool),
    _ = wpool_pool:find_wpool(Pool),

    ct:comment("Now, delete the pool"),
    Flag = process_flag(trap_exit, true),
    exit(whereis(Pool), kill),
    ok =
        ktn_task:wait_for(fun() ->
                             try wpool:call(Pool, {io, format, ["1!~n"]}, random_worker) of
                                 X ->
                                     {unexpected, X}
                             catch
                                 _:no_workers ->
                                     ok
                             end
                          end,
                          ok),

    true = process_flag(trap_exit, Flag),

    ct:comment("And now delete the ets table altogether"),
    store_mess_up(Pool),
    _ = wpool_pool:find_wpool(Pool),

    wpool:stop(),
    ok = wpool:start(),

    {comment, []}.

cast_tasks(Pool, TasksNumber, ReplyTo) ->
    lists:foreach(fun(N) -> wpool:cast(Pool, {erlang, send, [ReplyTo, {task, N}]}) end,
                  lists:seq(1, TasksNumber)).

collect_tasks(TasksNumber) ->
    lists:map(fun(_) ->
                 receive
                     {task, N} ->
                         N
                 end
              end,
              lists:seq(1, TasksNumber)).

collect_results(0, Results) ->
    Results;
collect_results(N, Results) ->
    receive
        {worker, WorkerId} ->
            collect_results(N - 1, [WorkerId | Results])
    after 100 ->
        timeout
    end.

send_io_format(Pool) ->
    {ok, ok} = wpool:call(Pool, {io, format, ["ok!~n"]}, available_worker).

worker_msg_queue_lengths(Pool) ->
    lists:usort([proplists:get_value(message_queue_len, WS)
                 || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))]).

store_mess_up(Pool) ->
    true = persistent_term:erase({wpool_pool, Pool}).
