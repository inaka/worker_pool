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
-module(wpool_SUITE).

-type config() :: [{atom(), term()}].

-export([ all/0
        ]).
-export([ init_per_suite/1
        , end_per_suite/1
        ]).
-export([ stats/1
        , stop_pool/1
        , overrun/1
        , too_much_overrun/1
        , default_strategy/1
        , overrun_handler/1
        , default_options/1
        , complete_coverage/1
        ]).

-spec all() -> [atom()].
all() ->
  [ Fun
  || {Fun, 1} <- module_info(exports)
   , Fun =/= init_per_suite
   , Fun =/= end_per_suite
   , Fun =/= module_info
   , Fun =/= overrun_handler
  ].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  ok = wpool:start(),
  Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
  wpool:stop(),
  Config.

-spec overrun_handler(M) -> M.
overrun_handler(M) -> overrun_handler ! {overrun, M}.

-spec too_much_overrun(config()) -> {comment, []}.
too_much_overrun(_Config) ->
  ct:comment("Receiving overruns here..."),
  true = register(overrun_handler, self()),
  {ok, PoolPid} =
    wpool:start_sup_pool(
      too_much_overrun,
      [ {workers, 1}
      , {overrun_warning, 1000}
      , {overrun_handler, {?MODULE, overrun_handler}}
      ]),

  ct:comment("Find the worker and the time checker..."),
  {ok, Worker} = wpool:call(too_much_overrun, {erlang, self, []}),
  TCPid = get_time_checker(PoolPid),

  ct:comment("Start a long running task..."),
  ok = wpool:cast(too_much_overrun, {timer, sleep, [5000]}),
  timer:sleep(100),
  {dictionary, Dict} = erlang:process_info(Worker, dictionary),
  {TaskId, _, _} = proplists:get_value(wpool_task, Dict),

  ct:comment("Simulate overrun warning..."),
  TCPid ! {check, Worker, TaskId, 9999999999}, % huge runtime… no more overruns

  ct:comment("Get overrun message..."),
  receive
    {overrun, Message} ->
      overrun = proplists:get_value(alert,  Message),
      too_much_overrun = proplists:get_value(pool,   Message),
      Worker  = proplists:get_value(worker,   Message),
      {cast, {timer, sleep, [5000]}} = proplists:get_value(task, Message),
      9999999999 = proplists:get_value(runtime,  Message)
  after 1500 ->
    throw(no_overrun)
  end,

  ct:comment("No more overruns..."),
  receive
  after 1500 -> ok
  end,

  ct:comment("Kill the worker..."),
  exit(Worker, kill),

  ct:comment("Simulate overrun warning..."),
  TCPid ! {check, Worker, TaskId, 100}, % tiny runtime, to check

  ct:comment("Nothing happens..."),
  receive
  after 1000 -> ok
  end,

  ct:comment("Stop pool..."),
  ok = wpool:stop_pool(too_much_overrun),

  {comment, []}.

-spec overrun(config()) -> {comment, []}.
overrun(_Config) ->
  true = register(overrun_handler, self()),
  {ok, _Pid} =
    wpool:start_sup_pool(
      ?MODULE,
      [ {workers, 1}
      , {overrun_warning, 1000}
      , {overrun_handler, {?MODULE, overrun_handler}}
      ]),
  ok = wpool:cast(?MODULE, {timer, sleep, [1500]}),
  receive
    {overrun, Message} ->
      overrun = proplists:get_value(alert,  Message),
      ?MODULE = proplists:get_value(pool,   Message),
      WPid  = proplists:get_value(worker,   Message),
      true  = is_pid(WPid),
      {cast, {timer, sleep, [1500]}} = proplists:get_value(task, Message),
      Runtime = proplists:get_value(runtime,  Message),
      true  = Runtime >= 1000
  after 1500 ->
    throw(no_overrun)
  end,
  receive
  after 1000 -> ok
  end,
  ok = wpool:stop_pool(?MODULE),

  {comment, []}.

-spec stop_pool(config()) -> {comment, []}.
stop_pool(_Config) ->
  {ok, PoolPid} = wpool:start_sup_pool(?MODULE, [{workers, 1}]),
  true = erlang:is_process_alive(PoolPid),
  ok = wpool:stop_pool(?MODULE),
  false = erlang:is_process_alive(PoolPid),
  ok = wpool:stop_pool(?MODULE),

  {comment, []}.

-spec stats(config()) -> {comment, []}.
stats(_Config) ->
  Get = fun proplists:get_value/2,

  try _ = wpool:stats(?MODULE), ok
  catch _:no_workers -> ok
  end,

  {ok, PoolPid} = wpool:start_sup_pool(?MODULE, [{workers, 10}]),
  true = is_process_alive(PoolPid),
  PoolPid = erlang:whereis(?MODULE),

  % Checks ...
  [InitStats] = wpool:stats(),
  ?MODULE = Get(pool, InitStats),
  PoolPid = Get(supervisor, InitStats),
  Options = Get(options, InitStats),
  infinity = Get(overrun_warning, Options),
  {error_logger, warning_report} = Get(overrun_handler, Options),
  10 = Get(workers, Options),
  10 = Get(size, InitStats),
  1 = Get(next_worker, InitStats),
  InitWorkers = Get(workers, InitStats),
  10 = length(InitWorkers),
  [ begin
      WorkerStats = Get(I, InitWorkers),
      0 = Get(message_queue_len, WorkerStats),
      [] =
        lists:keydelete(
          message_queue_len, 1, lists:keydelete(memory, 1, WorkerStats))
    end || I <- lists:seq(1, 10)],

  % Start a long task on every worker
  Sleep = {timer, sleep, [2000]},
  [wpool:cast(?MODULE, Sleep, next_worker) || _ <- lists:seq(1, 10)],

  timer:sleep(100),

  % Checks ...
  WorkingStats = wpool:stats(?MODULE),
  ?MODULE = Get(pool, WorkingStats),
  PoolPid = Get(supervisor, WorkingStats),
  Options = Get(options, WorkingStats),
  10 = Get(size, WorkingStats),
  1 = Get(next_worker, WorkingStats),
  WorkingWorkers = Get(workers, WorkingStats),
  10 = length(WorkingWorkers),
  [ begin
      WorkerStats = Get(I, WorkingWorkers),
      0 = Get(message_queue_len, WorkerStats),
      {timer, sleep, 1} = Get(current_function, WorkerStats),
      {timer, sleep, 1, _} = Get(current_location, WorkerStats),
      {cast, Sleep} = Get(task, WorkerStats),
      true = is_number(Get(runtime, WorkerStats))
    end || I <- lists:seq(1, 10)],

  wpool:stop_pool(?MODULE),

  timer:sleep(5000),

  no_workers =
    try wpool:stats(?MODULE)
    catch _:E -> E
    end,

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
  {ok, State} = wpool_time_checker:init({pool, {x, y}}),
  ok = wpool_time_checker:terminate(reason, State),
  {ok, State} = wpool_time_checker:code_change("oldvsn", State, extra),

  {ok, PoolPid} = wpool:start_pool(coverage, []),
  TCPid = get_time_checker(PoolPid),
  TCPid ! info,
  ok = gen_server:cast(TCPid, cast),
  ok = gen_server:call(TCPid, call),

  {comment, []}.

get_time_checker(PoolPid) ->
  [TCPid] =
    [ P
    || {_, P, worker, [wpool_time_checker]} <-
        supervisor:which_children(PoolPid)
    ],
  TCPid.
