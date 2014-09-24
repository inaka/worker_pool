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

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([stats/1, stop_pool/1, overrun/1]).
-export([overrun_handler/1]).

-spec all() -> [atom()].
all() ->
  [Fun 
   || {Fun, 1} <- module_info(exports)
    , Fun =/= init_per_suite
    , Fun =/= end_per_suite
    , Fun =/= module_info
    , Fun =/= overrun_handler
  ].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  wpool:start(),
  Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
  wpool:stop(),
  Config.

-spec overrun_handler(M) -> M.
overrun_handler(M) -> overrun_handler ! {overrun, M}.

-spec overrun(config()) -> _.
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
  ok = wpool:stop_pool(?MODULE).

-spec stop_pool(config()) -> _.
stop_pool(_Config) ->
  {ok, PoolPid} = wpool:start_sup_pool(?MODULE, [{workers, 1}]),
  true = erlang:is_process_alive(PoolPid),
  ok = wpool:stop_pool(?MODULE),
  false = erlang:is_process_alive(PoolPid),
  ok = wpool:stop_pool(?MODULE).

-spec stats(config()) -> _.
stats(_Config) ->
  Get = fun proplists:get_value/2,

  try wpool:stats(?MODULE)
  catch _:no_workers -> ok
  end,

  {ok, PoolPid} = wpool:start_pool(?MODULE, [{workers, 10}]),
  true = is_pid(PoolPid),

  % Checks ...
  InitStats = wpool:stats(?MODULE),
  ?MODULE = Get(pool, InitStats),
  PoolPid = Get(supervisor, InitStats),
  Options = Get(options, InitStats),
  infinity = Get(overrun_warning, Options),
  {error_logger, warning_report} = Get(overrun_handler, Options),
  10 = Get(workers, Options),
  10 = Get(size, InitStats),
  1 = Get(next_worker, InitStats),
  {wpool_worker, undefined} = Get(worker, Options),
  InitWorkers = Get(workers, InitStats),
  10 = length(InitWorkers),
  [begin
    WorkerStats = Get(I, InitWorkers),
    0 = Get(message_queue_len, WorkerStats),
    [] = lists:keydelete(
          message_queue_len, 1, lists:keydelete(memory, 1, WorkerStats))
   end || I <- lists:seq(1, 10)],

  % Start a long task on every worker
  Sleep = {timer, sleep, [10000]},
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
  [begin
    WorkerStats = Get(I, WorkingWorkers),
    0 = Get(message_queue_len, WorkerStats),
    {timer, sleep, 1} = Get(current_function, WorkerStats),
    {timer, sleep, 1, _} = Get(current_location, WorkerStats),
    {cast, Sleep} = Get(task, WorkerStats),
    true = is_number(Get(runtime, WorkerStats))
   end || I <- lists:seq(1, 10)],

  wpool:stop_pool(?MODULE),
  try wpool:stats(?MODULE)
  catch _:no_workers -> ok
  end.
