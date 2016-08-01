% This file is licensed to you under the Apache License,
% Version 2.0 (the "License"); you may not use this file
% except in compliance with the License.  You may obtain
% a copy of the License at
%
% http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing,
% software distributed under the License is distributed on an
% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
% KIND, either express or implied.  See the License for the
% specific language governing permissions and limitations
% under the License.

%% @hidden
-module(wpool_pool_SUITE).

-type config() :: [{atom(), term()}].

-define(WORKERS, 6).

-export([ all/0
        ]).
-export([ init_per_suite/1
        , end_per_suite/1
        , init_per_testcase/2
        , end_per_testcase/2
        ]).
-export([ best_worker/1
        , next_worker/1
        , random_worker/1
        , available_worker/1
        , hash_worker/1
        , custom_worker/1
        , next_available_worker/1
        , wpool_record/1
        ]).
-export([ wait_and_self/1
        ]).
-export([ manager_crash/1
        , super_fast/1
        , ets_mess_up/1
        ]).

-spec all() -> [atom()].
all() ->
  [Fun || {Fun, 1} <- module_info(exports),
          not lists:member( Fun
                          , [ init_per_suite
                            , end_per_suite
                            , module_info
                            , wait_and_self
                            ]
                          )].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  ok = wpool:start(),
  Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
  wpool:stop(),
  Config.

-spec init_per_testcase(atom(), config()) -> config().
init_per_testcase(TestCase, Config) ->
  {ok, _} = wpool:start_pool(TestCase, [{workers, ?WORKERS}]),
  Config.

-spec end_per_testcase(atom(), config()) -> config().
end_per_testcase(TestCase, Config) ->
  catch wpool:stop_pool(TestCase),
  Config.

-spec wait_and_self(pos_integer()) -> pid().
wait_and_self(Time) ->
  timer:sleep(Time),
  {registered_name, Self} = process_info(self(), registered_name),
  Self.

-spec available_worker(config()) -> {comment, []}.
available_worker(_Config) ->
  Pool = available_worker,
  try wpool:call(not_a_pool, x) of
    Result -> no_result = Result
  catch
    _:no_workers -> ok
  end,

  ct:log(
    "Put them all to work, each request should go to a different worker"),
  [wpool:cast(Pool, {timer, sleep, [5000]}) || _ <- lists:seq(1, ?WORKERS)],
  timer:sleep(500),
  [0] = sets:to_list(
      sets:from_list(
        [proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),

  ct:log(
    "Now send another round of messages,
     the workers queues should still be empty"),
  [wpool:cast(Pool, {timer, sleep, [100 * I]}) || I <- lists:seq(1, ?WORKERS)],
  timer:sleep(500),
  Stats1 = wpool:stats(Pool),
  [0] = sets:to_list(
      sets:from_list(
        [proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, Stats1)])),
  % Check that we have ?WORKERS pending tasks
  ?WORKERS = proplists:get_value(total_message_queue_len, Stats1),
  ct:log("If we can't wait we get no workers"),
  try wpool:call(Pool, {erlang, self, []}, available_worker, 100) of
    R -> should_fail = R
  catch
    _:Error -> timeout = Error
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
  timer:sleep(1000),
  Stats3 = wpool:stats(Pool),
  ct:log(error, "~p", [Stats3]),
  0 = proplists:get_value(total_message_queue_len, Stats3),

  ct:log(
    "We run tons of calls, and none is blocked,
     because all of them are handled by different workers"),
  Workers =
    [ wpool:call(Pool, {erlang, self, []}, available_worker, 5000)
     || _ <- lists:seq(1, 20 * ?WORKERS)],
  UniqueWorkers = sets:to_list(sets:from_list(Workers)),
  {?WORKERS, UniqueWorkers, true} =
    {?WORKERS, UniqueWorkers, (?WORKERS/2) >= length(UniqueWorkers)},

  {comment, []}.

-spec best_worker(config()) -> {comment, []}.
best_worker(_Config) ->
  Pool = best_worker,
  try wpool:call(not_a_pool, x, best_worker) of
    Result -> no_result = Result
  catch
    _:no_workers -> ok
  end,

  %% Fill up their message queues...
  [ wpool:cast(Pool, {timer, sleep, [60000]}, next_worker)
   || _ <- lists:seq(1, ?WORKERS)],
  timer:sleep(1500),
  [0] = sets:to_list(
      sets:from_list(
        [proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),
  [ wpool:cast(Pool, {timer, sleep, [60000]}, best_worker)
   || _ <- lists:seq(1, ?WORKERS)],
  timer:sleep(500),
  [1] = sets:to_list(
      sets:from_list(
        [proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),
  %% Now try best worker once per worker
  [ wpool:cast(Pool, {timer, sleep, [60000]}, best_worker)
   || _ <- lists:seq(1, ?WORKERS)],
  %% The load should be evenly distributed...
  [2] = sets:to_list(
      sets:from_list(
        [proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),

  {comment, []}.

-spec next_available_worker(config()) -> {comment, []}.
next_available_worker(_Config) ->
  Pool = next_available_worker,
  ct:log("not_a_pool is not a pool"),
  try wpool:call(not_a_pool, x, next_available_worker) of
    Result -> no_result = Result
  catch
    _:no_workers -> ok
  end,

  ct:log("Put them all to work..."),
  [ wpool:cast(Pool, {timer, sleep, [1500 + I]}, next_available_worker)
   || I <- lists:seq(0, (?WORKERS - 1) * 60000, 60000)],
  timer:sleep(500),

  AvailableWorkers =
    fun() ->
      [proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))
           , proplists:get_value(task, WS) == undefined]
    end,

  ct:log("All busy..."),
  [] = AvailableWorkers(),

  ct:log("No available workers..."),
  try wpool:cast(Pool, {timer, sleep, [60000]}, next_available_worker) of
    ok -> ct:fail("Exception expected")
  catch
    _:no_available_workers -> ok
  end,

  ct:log("Wait until the first frees up..."),
  timer:sleep(1000),
  [_] = AvailableWorkers(),

  ok = wpool:cast(Pool, {timer, sleep, [60000]}, next_available_worker),

  ct:log("No more available workers..."),
  try wpool:cast(Pool, {timer, sleep, [60000]}, next_available_worker) of
    ok -> ct:fail("Exception expected")
  catch
    _:no_available_workers -> ok
  end,

  {comment, []}.

-spec next_worker(config()) -> {comment, []}.
next_worker(_Config) ->
  Pool = next_worker,

  try wpool:call(not_a_pool, x, next_worker) of
    Result -> no_result = Result
  catch
    _:no_workers -> ok
  end,

  Res0 = [begin
            Stats = wpool:stats(Pool),
            I = proplists:get_value(next_worker, Stats),
            wpool:call(Pool, {erlang, self, []}, next_worker, infinity)
          end || I <- lists:seq(1, ?WORKERS)],
  ?WORKERS = sets:size(sets:from_list(Res0)),
  Res0 = [begin
            Stats = wpool:stats(Pool),
            I = proplists:get_value(next_worker, Stats),
            wpool:call(Pool, {erlang, self, []}, next_worker)
          end || I <- lists:seq(1, ?WORKERS)],

  {comment, []}.

-spec random_worker(config()) -> {comment, []}.
random_worker(_Config) ->
  Pool = random_worker,

  try wpool:call(not_a_pool, x, random_worker) of
  Result -> no_result = Result
  catch
      _:no_workers -> ok
  end,

  %% Ask for a random worker's identity 20x more than the number of workers
  %% and expect to get an answer from every worker at least once.
  Serial =
    [ wpool:call(Pool, {erlang, self, []}, random_worker)
     || _ <- lists:seq(1, 20 * ?WORKERS)],
  ?WORKERS = sets:size(sets:from_list(Serial)),

  %% Now do the same with a freshly spawned process for each request to ensure
  %% randomness isn't reset with each spawn of the process_dictionary
  Self = self(),
  _ = [spawn(fun() ->
               WorkerId = wpool:call(Pool, {erlang, self, []}, random_worker),
               Self ! {worker, WorkerId}
             end) || _ <- lists:seq(1, 20 * ?WORKERS)],
  Concurrent = collect_results(20 * ?WORKERS, []),
  ?WORKERS = sets:size(sets:from_list(Concurrent)),

  {comment, []}.

-spec hash_worker(config()) -> {comment, []}.
hash_worker(_Config) ->
  Pool = hash_worker,

  try wpool:call(not_a_pool, x, {hash_worker, 1}) of
  Result -> no_result = Result
  catch
      _:no_workers -> ok
  end,

  %% Use two hash keys that have different values (0, 1) to target only
  %% two workers. Other workers should be missing.
  Targeted =
    [ wpool:call(Pool, {erlang, self, []}, {hash_worker, I rem 2})
     || I <- lists:seq(1, 20 * ?WORKERS)],
  2 = sets:size(sets:from_list(Targeted)),

  %% Now use many different hash keys. All workers should be hit.
  Spread =
    [ wpool:call(Pool, {erlang, self, []}, {hash_worker, I})
     || I <- lists:seq(1, 20 * ?WORKERS)],
  ?WORKERS = sets:size(sets:from_list(Spread)),

  %% Fill up their message queues...
  [ wpool:cast(Pool, {timer, sleep, [60000]}, {hash_worker, I})
    || I <- lists:seq(1, 20 * ?WORKERS)],
  timer:sleep(1500),
  false =
    lists:member(
      0, [ proplists:get_value(message_queue_len, WS)
          || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))]),

  {comment, []}.

-spec custom_worker(config()) -> {comment, []}.
custom_worker(_Config) ->
  Pool = custom_worker,

  Strategy = fun wpool_pool:best_worker/1,

  try wpool:call(not_a_pool, x, Strategy) of
    Result -> no_result = Result
  catch
    _:no_workers -> ok
  end,

  %% Fill up their message queues...
  [ wpool:cast(Pool, {timer, sleep, [60000]}, Strategy)
    || _ <- lists:seq(1, ?WORKERS)],
  timer:sleep(1500),
  [0] = sets:to_list(
    sets:from_list(
      [proplists:get_value(message_queue_len, WS)
        || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),
  [ wpool:cast(Pool, {timer, sleep, [60000]}, Strategy)
    || _ <- lists:seq(1, ?WORKERS)],
  timer:sleep(500),
  [1] = sets:to_list(
    sets:from_list(
      [proplists:get_value(message_queue_len, WS)
        || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),
  %% Now try best worker once per worker
  [ wpool:cast(Pool, {timer, sleep, [60000]}, Strategy)
    || _ <- lists:seq(1, ?WORKERS)],
  %% The load should be evenly distributed...
  [2] = sets:to_list(
    sets:from_list(
      [proplists:get_value(message_queue_len, WS)
        || {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),

  {comment, []}.

-spec manager_crash(config()) -> {comment, []}.
manager_crash(_Config) ->
  Pool = manager_crash,
  QueueManager = 'wpool_pool-manager_crash-queue-manager',

  ct:log("Check that the pool is working"),
  {ok, ok} = send_io_format(Pool),
  true = undefined =/= whereis(QueueManager),

  ct:log("Crash the pool manager"),
  exit(whereis(QueueManager), kill),
  timer:sleep(100),
  true = undefined =/= whereis(QueueManager),

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
  try wpool:call(
        Pool, {erlang, send, [Self, something]}, available_worker, 0) of
    R -> ct:fail("Unexpected ~p", [R])
  catch
    _:timeout -> ok
  end,

  ct:log("Wait a second"),
  timer:sleep(1000),

  ct:log("Nothing gets here"),
  receive
    X -> ct:fail("Unexpected ~p", [X])
  after 0 ->
    ok
  end,

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


-spec ets_mess_up(config()) -> {comment, []}.
ets_mess_up(_Config) ->
  Pool = ets_mess_up,

  ct:comment("Mess up with ets table..."),
  true = ets:delete(wpool_pool, Pool),

  ct:comment("Rebuild stats"),
  1 = proplists:get_value(next_worker, wpool:stats(Pool)),

  ct:comment("Mess up with ets table again..."),
  true = ets:delete(wpool_pool, Pool),
  {ok, ok} = wpool:call(Pool, {io, format, ["1!~n"]}, random_worker),

  ct:comment("Mess up with ets table once more..."),
  {ok, ok} = wpool:call(Pool, {io, format, ["2!~n"]}, next_worker),
  2 = proplists:get_value(next_worker, wpool:stats(Pool)),
  true = ets:delete(wpool_pool, Pool),
  {ok, ok} = wpool:call(Pool, {io, format, ["3!~n"]}, next_worker),
  1 = proplists:get_value(next_worker, wpool:stats(Pool)),

  ct:comment("Mess up with ets table one final time..."),
  true = ets:delete(wpool_pool, Pool),
  _ = wpool_pool:find_wpool(Pool),

  ct:comment("Now, delete the pool"),
  Flag = process_flag(trap_exit, true),
  exit(whereis(Pool), kill),
  timer:sleep(100),
  try wpool:call(Pool, {io, format, ["1!~n"]}, random_worker) of
    X -> ct:fail("Unexpected ~p", [X])
  catch
    _:no_workers -> ok
  end,

  true = process_flag(trap_exit, Flag),

  ct:comment("And now delete the ets table altogether"),
  true = ets:delete(wpool_pool),
  _ = wpool_pool:find_wpool(Pool),

  wpool:stop(),
  ok = wpool:start(),

  {comment, []}.

collect_results(0, Results) -> Results;
collect_results(N, Results) ->
  receive {worker, WorkerId} -> collect_results(N-1, [WorkerId | Results])
  after 100 -> timeout
  end.

send_io_format(Pool) ->
  {ok, ok} = wpool:call(Pool, {io, format, ["ok!~n"]}, available_worker).
