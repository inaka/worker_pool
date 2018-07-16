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
-module(wpool_process_SUITE).

-type config() :: [{atom(), term()}].

-export([ all/0
        ]).
-export([ init_per_suite/1
        , end_per_suite/1
        , init_per_testcase/2
        , end_per_testcase/2
        ]).
-export([ init/1
        , init_timeout/1
        , info/1
        , cast/1
        , call/1
        , continue/1
        , no_format_status/1
        , stop/1
        ]).
-export([ pool_restart_crash/1
        , pool_norestart_crash/1
        , complete_coverage/1
        ]).


-spec all() -> [atom()].
all() ->
  [Fun || {Fun, 1} <- module_info(exports),
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
init_per_testcase(_TestCase, Config) ->
  process_flag(trap_exit, true),
  Config.

-spec end_per_testcase(atom(), config()) -> config().
end_per_testcase(_TestCase, Config) ->
  process_flag(trap_exit, false),
  receive after 0 -> ok end,
  Config.

-spec init(config()) -> {comment, []}.
init(_Config) ->
  {error, can_not_ignore} =
    wpool_process:start_link(?MODULE, echo_server, ignore, []),
  {error, ?MODULE} =
    wpool_process:start_link(?MODULE, echo_server, {stop, ?MODULE}, []),
  {ok, _Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, []),
  wpool_process:cast(?MODULE, {stop, normal, state}),

  {comment, []}.

-spec init_timeout(config()) -> {comment, []}.
init_timeout(_Config) ->
  {ok, Pid} =
    wpool_process:start_link(?MODULE, echo_server, {ok, state, 0}, []),
  timer:sleep(1),
  timeout = get_state(?MODULE),
  Pid ! {stop, normal, state},
  timer:sleep(1000),
  false = erlang:is_process_alive(Pid),

  {comment, []}.

-spec info(config()) -> {comment, []}.
info(_Config) ->
  {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, []),
  Pid ! {noreply, newstate},
  newstate = get_state(?MODULE),
  Pid ! {noreply, newerstate, 1},
  timer:sleep(1),
  timeout = get_state(?MODULE),
  Pid ! {stop, normal, state},
  timer:sleep(1000),
  false = erlang:is_process_alive(Pid),

  {comment, []}.

-spec cast(config()) -> {comment, []}.
cast(_Config) ->
  {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, []),
  wpool_process:cast(Pid, {noreply, newstate}),
  newstate = get_state(?MODULE),
  wpool_process:cast(Pid, {noreply, newerstate, 0}),
  timer:sleep(100),
  timeout = get_state(?MODULE),
  wpool_process:cast(Pid, {stop, normal, state}),
  timer:sleep(1000),
  false = erlang:is_process_alive(Pid),

  {comment, []}.

-spec continue(config()) -> {comment, []}.
continue(_Config) ->
  C = fun(ContinueState) -> {noreply, ContinueState} end,
  %% init/1 returns {continue, continue_state}
  {ok, Pid} =
    wpool_process:start_link(
      ?MODULE, echo_server, {ok, state, {continue, C(continue_state)}}, []),
  continue_state = get_state(Pid),

  %% handle_call/3 returns {continue, ...}
  ok = wpool_process:call(Pid, {reply, ok, state, {continue, C(continue_state_2)}}, 5000),
  continue_state_2 = get_state(Pid),
  try wpool_process:call(Pid, {noreply, state, {continue, C(continue_state_3)}}, 100) of
    Result -> ct:fail("Unexpected Result: ~p", [Result])
  catch
    _:{timeout, _} ->
      continue_state_3 = get_state(Pid)
  end,

  %% handle_cast/2 returns {continue, ...}
  wpool_process:cast(Pid, {noreply, state, {continue, C(continue_state_4)}}),
  continue_state_4 = get_state(Pid),

  %% handle_continue/2 returns {continue, ...}
  SecondContinueResponse = C(continue_state_5),
  FirstContinueResponse = {noreply, another_state, {continue, SecondContinueResponse}},
  CastResponse = {noreply, state, {continue, FirstContinueResponse}},
  wpool_process:cast(Pid, CastResponse),
  continue_state_5 = get_state(Pid),

  %% handle_info/2 returns {continue, ...}
  Pid ! {noreply, state, {continue, C(continue_state_6)}},
  continue_state_6 = get_state(Pid),

  %% handle_continue/2 returns {continue, ...}
  SecondContinueResponse = C(continue_state_5),
  FirstContinueResponse = {noreply, another_state, {continue, SecondContinueResponse}},
  CastResponse = {noreply, state, {continue, FirstContinueResponse}},
  wpool_process:cast(Pid, CastResponse),
  continue_state_5 = get_state(Pid),

  %% handle_continue/2 returns timeout = 0
  wpool_process:cast(Pid, {noreply, state, {continue, {noreply, continue_state_7, 0}}}),
  timer:sleep(100),
  timeout = get_state(Pid),

  %% handle_continue/2 returns {stop, normal, state}
  wpool_process:cast(Pid, {noreply, state, {continue, {stop, normal, state}}}),
  timer:sleep(1000),
  false = erlang:is_process_alive(Pid),

  {comment, []}.

-spec no_format_status(config()) -> {comment, []}.
no_format_status(_Config) ->
  %% crashy_server doesn't implement format_status/2
  {ok, Pid} = wpool_process:start_link(?MODULE, crashy_server, state, []),
  %% therefore it uses the default format for the stauts (but with the status of the gen_server,
  %% not wpool_process)
  {status, Pid, {module, gen_server}, SItems} = sys:get_status(Pid),
  [state] = [S || SItemList = [_|_] <- SItems, {data, Data} <- SItemList, {"State", S} <- Data],
  {comment, []}.

-spec call(config()) -> {comment, []}.
call(_Config) ->
  {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, []),
  ok1 = wpool_process:call(Pid, {reply, ok1, newstate}, 5000),
  newstate = get_state(?MODULE),
  ok2 = wpool_process:call(Pid, {reply, ok2, newerstate, 1}, 5000),
  timer:sleep(1),
  timeout = get_state(?MODULE),
  ok3 = wpool_process:call(Pid, {stop, normal, ok3, state}, 5000),
  timer:sleep(1000),
  false = erlang:is_process_alive(Pid),

  {comment, []}.

-spec pool_restart_crash(config()) -> {comment, []}.
pool_restart_crash(_Config) ->
  Pool = pool_restart_crash,
  PoolOptions = [{workers, 2}, {worker, {crashy_server, []}}],
  {ok, Pid} = wpool:start_pool(Pool, PoolOptions),
  ct:log("Check that the pool is working"),
  true = erlang:is_process_alive(Pid),
  hello = wpool:call(Pool, hello),

  ct:log("Crash a worker"),
  wpool:cast(Pool, crash),

  ct:log("Check that the pool wouldn't crash"),
  wpool:cast(Pool, crash, best_worker),

  timer:sleep(500),

  ct:log("Check that the pool is working"),
  true = erlang:is_process_alive(Pid),
  hello = wpool:call(Pool, hello),

  {comment, []}.

-spec pool_norestart_crash(config()) -> {comment, []}.
pool_norestart_crash(_Config) ->
  Pool = pool_norestart_crash,
  PoolOptions = [ {workers, 2}
                , {worker, {crashy_server, []}}
                , {strategy, {one_for_all, 0, 10}}
                , {pool_sup_intensity, 0}
                , {pool_sup_period, 10}
                ],
  {ok, Pid} = wpool:start_pool(Pool, PoolOptions),

  ct:log("Check that the pool is working"),
  true = erlang:is_process_alive(Pid),
  hello = wpool:call(Pool, hello),

  ct:log("Crash a worker"),
  wpool:cast(Pool, crash),
  timer:sleep(500),

  ct:log("Check that the pool is working"),
  false = erlang:is_process_alive(Pid),

  {comment, []}.

-spec stop(config()) -> {comment, []}.
stop(_Config) ->
  From = {self(), Ref = make_ref()},

  ct:comment("cast_call with stop/reply"),
  {ok, Pid1} = wpool_process:start_link(stopper, echo_server, {ok, state}, []),
  ok = wpool_process:cast_call(stopper, From, {stop, reason, response, state}),
  receive
    {Ref, response} -> ok
  after 5000 ->
    ct:fail("no response")
  end,
  receive
    {'EXIT', Pid1, reason} -> ok
  after 500 ->
    ct:fail("Missing exit signal")
  end,

  ct:comment("cast_call with regular stop"),
  {ok, Pid2} = wpool_process:start_link(stopper, echo_server, {ok, state}, []),
  ok = wpool_process:cast_call(stopper, From, {stop, reason, state}),
  receive
    {Ref, _} -> ct:fail("unexpected response");
    {'EXIT', Pid2, reason} -> ok
  after 500 ->
    ct:fail("Missing exit signal")
  end,

  ct:comment("call with regular stop"),
  {ok, Pid3} = wpool_process:start_link(stopper, echo_server, {ok, state}, []),
  try wpool_process:call(stopper, {noreply, state}, 100) of
    _ -> ct:fail("unexpected response")
  catch
    _:{timeout, _} -> ok
  end,
  receive
    {'EXIT', Pid3, _} -> ct:fail("Unexpected process crash")
  after 500 ->
    ok
  end,

  ct:comment("call with timeout stop"),
  try wpool_process:call(stopper, {noreply, state, hibernate}, 100) of
    _ -> ct:fail("unexpected response")
  catch
    _:{timeout, _} -> ok
  end,
  receive
    {'EXIT', Pid3, _} -> ct:fail("Unexpected process crash")
  after 500 ->
    ok
  end,

  {comment, []}.


-spec complete_coverage(config()) -> {comment, []}.
complete_coverage(_Config) ->
  ct:comment("Code Change"),
  {ok, State} =
    wpool_process:init({complete_coverage, echo_server, {ok, state}, []}),
  {ok, _} = wpool_process:code_change("oldvsn", State, {ok, state}),
  {error, bad} = wpool_process:code_change("oldvsn", State, bad),

  {comment, []}.

get_state(Atom) when is_atom(Atom) ->
  get_state(whereis(Atom));
get_state(Pid) ->
  {status, Pid, {module, gen_server}, SItems} = sys:get_status(Pid),
  [State] = [S || SItemList = [_|_] <- SItems, {formatted_state, S} <- SItemList],
  State.
