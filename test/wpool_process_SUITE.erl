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
-module(wpool_process_SUITE).

-behaviour(ct_suite).

-type config() :: [{atom(), term()}].

-export_type([config/0]).

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([init/1, init_timeout/1, info/1, cast/1, send_request/1, call/1, continue/1,
         handle_info_missing/1, handle_info_fails/1, format_status/1, no_format_status/1, stop/1]).
-export([pool_restart_crash/1, pool_norestart_crash/1, complete_coverage/1]).

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
init_per_testcase(_TestCase, Config) ->
    process_flag(trap_exit, true),
    Config.

-spec end_per_testcase(atom(), config()) -> config().
end_per_testcase(_TestCase, Config) ->
    process_flag(trap_exit, false),
    receive after 0 ->
        ok
    end,
    Config.

-spec init(config()) -> {comment, []}.
init(_Config) ->
    {error, can_not_ignore} = wpool_process:start_link(?MODULE, echo_server, ignore, #{}),
    {error, ?MODULE} = wpool_process:start_link(?MODULE, echo_server, {stop, ?MODULE}, #{}),
    {ok, _Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, #{}),
    wpool_process:cast(?MODULE, {stop, normal, state}),

    {comment, []}.

-spec init_timeout(config()) -> {comment, []}.
init_timeout(_Config) ->
    {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state, 0}, #{}),
    timeout = get_state(?MODULE),
    Pid ! {stop, normal, state},
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

    {comment, []}.

-spec info(config()) -> {comment, []}.
info(_Config) ->
    {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, #{}),
    Pid ! {noreply, newstate},
    newstate = get_state(?MODULE),
    Pid ! {noreply, newerstate, 1},
    timeout = ktn_task:wait_for(fun() -> get_state(?MODULE) end, timeout),
    Pid ! {stop, normal, state},
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

    {comment, []}.

-spec cast(config()) -> {comment, []}.
cast(_Config) ->
    {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, #{}),
    wpool_process:cast(Pid, {noreply, newstate}),
    newstate = get_state(?MODULE),
    wpool_process:cast(Pid, {noreply, newerstate, 0}),
    timeout = ktn_task:wait_for(fun() -> get_state(?MODULE) end, timeout),
    wpool_process:cast(Pid, {stop, normal, state}),
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

    {comment, []}.

-spec send_request(config()) -> {comment, []}.
send_request(_Config) ->
    {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, #{}),
    Req1 = wpool_process:send_request(Pid, {reply, ok1, newstate}),
    ok1 = wait_response(Req1),
    Req2 = wpool_process:send_request(Pid, {reply, ok2, newerstate, 1}),
    ok2 = wait_response(Req2),
    Req3 = wpool_process:send_request(Pid, {stop, normal, ok3, state}),
    ok3 = wait_response(Req3),
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

    {comment, []}.

wait_response(ReqId) ->
    case gen_server:wait_response(ReqId, 5000) of
        {reply, Reply} ->
            Reply;
        timeout ->
            ct:fail("no response")
    end.

-spec continue(config()) -> {comment, []}.
continue(_Config) ->
    C = fun(ContinueState) -> {noreply, ContinueState} end,
    %% init/1 returns {continue, continue_state}
    {ok, Pid} =
        wpool_process:start_link(?MODULE,
                                 echo_server,
                                 {ok, state, {continue, C(continue_state)}},
                                 #{}),
    continue_state = get_state(Pid),

    %% handle_call/3 returns {continue, ...}
    ok = wpool_process:call(Pid, {reply, ok, state, {continue, C(continue_state_b)}}, 5000),
    continue_state_b = get_state(Pid),
    try wpool_process:call(Pid, {noreply, state, {continue, C(continue_state_c)}}, 100) of
        Result ->
            ct:fail("Unexpected Result: ~p", [Result])
    catch
        _:{timeout, _} ->
            continue_state_c = get_state(Pid)
    end,

    %% handle_cast/2 returns {continue, ...}
    wpool_process:cast(Pid, {noreply, state, {continue, C(continue_state_d)}}),
    continue_state_d = get_state(Pid),

    %% handle_continue/2 returns {continue, ...}
    SecondContinueResponse = C(continue_state_e),
    FirstContinueResponse = {noreply, another_state, {continue, SecondContinueResponse}},
    CastResponse = {noreply, state, {continue, FirstContinueResponse}},
    wpool_process:cast(Pid, CastResponse),
    continue_state_e = get_state(Pid),

    %% handle_info/2 returns {continue, ...}
    Pid ! {noreply, state, {continue, C(continue_state_f)}},
    continue_state_f = get_state(Pid),

    %% handle_continue/2 returns {continue, ...}
    SecondContinueResponse = C(continue_state_e),
    FirstContinueResponse = {noreply, another_state, {continue, SecondContinueResponse}},
    CastResponse = {noreply, state, {continue, FirstContinueResponse}},
    wpool_process:cast(Pid, CastResponse),
    continue_state_e = get_state(Pid),

    %% handle_continue/2 returns timeout = 0
    wpool_process:cast(Pid, {noreply, state, {continue, {noreply, continue_state_g, 0}}}),
    timeout = ktn_task:wait_for(fun() -> get_state(?MODULE) end, timeout),

    %% handle_continue/2 returns {stop, normal, state}
    wpool_process:cast(Pid, {noreply, state, {continue, {stop, normal, state}}}),
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

    {comment, []}.

-spec handle_info_missing(config()) -> {comment, []}.
handle_info_missing(_Config) ->
    %% sleepy_server does not implement handle_info/2
    {ok, Pid} = wpool_process:start_link(?MODULE, sleepy_server, 1, #{}),
    Pid ! test,
    {comment, []}.

-spec handle_info_fails(config()) -> {comment, []}.
handle_info_fails(_Config) ->
    %% sleepy_server does not implement handle_info/2
    {ok, Pid} = wpool_process:start_link(?MODULE, crashy_server, {ok, state}, #{}),
    Pid ! undef,
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),
    {comment, []}.

-spec format_status(config()) -> {comment, []}.
format_status(_Config) ->
    %% echo_server implements format_status/1
    {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, #{}),
    %% therefore it returns State as its status
    state = get_state(Pid),
    {comment, []}.

-spec no_format_status(config()) -> {comment, []}.
no_format_status(_Config) ->
    %% crashy_server doesn't implement format_status/1
    {ok, Pid} = wpool_process:start_link(?MODULE, crashy_server, state, #{}),
    %% therefore it uses the default format for the stauts (but with the status of
    %% the gen_server, not wpool_process)
    state = get_state(Pid),
    {comment, []}.

-spec call(config()) -> {comment, []}.
call(_Config) ->
    {ok, Pid} = wpool_process:start_link(?MODULE, echo_server, {ok, state}, #{}),
    ok1 = wpool_process:call(Pid, {reply, ok1, newstate}, 5000),
    newstate = get_state(?MODULE),
    ok2 = wpool_process:call(Pid, {reply, ok2, newerstate, 1}, 5000),
    timeout = ktn_task:wait_for(fun() -> get_state(?MODULE) end, timeout),
    ok3 = wpool_process:call(Pid, {stop, normal, ok3, state}, 5000),
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

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

    ct:log("Check that the pool didn't die"),
    {error, {timeout, {badmatch, true}}} =
        ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),
    hello = wpool:call(Pool, hello),

    {comment, []}.

-spec pool_norestart_crash(config()) -> {comment, []}.
pool_norestart_crash(_Config) ->
    Pool = pool_norestart_crash,
    PoolOptions =
        [{workers, 2},
         {worker, {crashy_server, []}},
         {strategy, {one_for_all, 0, 10}},
         {pool_sup_intensity, 0},
         {pool_sup_period, 10}],
    {ok, Pid} = wpool:start_pool(Pool, PoolOptions),

    ct:log("Check that the pool is working"),
    true = erlang:is_process_alive(Pid),
    hello = wpool:call(Pool, hello),

    ct:log("Crash a worker"),
    wpool:cast(Pool, crash),

    ct:log("Check that the pool is not working"),
    false = ktn_task:wait_for(fun() -> erlang:is_process_alive(Pid) end, false),

    {comment, []}.

-spec stop(config()) -> {comment, []}.
stop(_Config) ->
    ct:comment("cast_call with stop/reply"),
    {ok, Pid1} = wpool_process:start_link(stopper, echo_server, {ok, state}, #{}),
    ReqId1 = wpool_process:send_request(stopper, {stop, reason, response, state}),
    case gen_server:wait_response(ReqId1, 5000) of
        {reply, response} ->
            ok;
        timeout ->
            ct:fail("no response")
    end,
    receive
        {'EXIT', Pid1, reason} ->
            ok
    after 500 ->
        ct:fail("Missing exit signal")
    end,

    ct:comment("cast_call with regular stop"),
    {ok, Pid2} = wpool_process:start_link(stopper, echo_server, {ok, state}, #{}),
    ReqId2 = wpool_process:send_request(stopper, {stop, reason, state}),
    case gen_server:wait_response(ReqId2, 500) of
        {error, {reason, Pid2}} ->
            ok;
        {reply, _} ->
            ct:fail("unexpected response")
    end,
    receive
        {'EXIT', Pid2, reason} ->
            ok
    after 500 ->
        ct:fail("Missing exit signal")
    end,

    ct:comment("call with regular stop"),
    {ok, Pid3} = wpool_process:start_link(stopper, echo_server, {ok, state}, #{}),
    try wpool_process:call(stopper, {noreply, state}, 100) of
        _ ->
            ct:fail("unexpected response")
    catch
        _:{timeout, _} ->
            ok
    end,
    receive
        {'EXIT', Pid3, _} ->
            ct:fail("Unexpected process crash")
    after 500 ->
        ok
    end,

    ct:comment("call with timeout stop"),
    try wpool_process:call(stopper, {noreply, state, hibernate}, 100) of
        _ ->
            ct:fail("unexpected response")
    catch
        _:{timeout, _} ->
            ok
    end,
    receive
        {'EXIT', Pid3, _} ->
            ct:fail("Unexpected process crash")
    after 500 ->
        ok
    end,

    {comment, []}.

-spec complete_coverage(config()) -> {comment, []}.
complete_coverage(_Config) ->
    ct:comment("Code Change"),
    {ok, State} = wpool_process:init({complete_coverage, echo_server, {ok, state}, []}),
    {ok, _} = wpool_process:code_change("oldvsn", State, {ok, state}),
    {error, bad} = wpool_process:code_change("oldvsn", State, {error, bad}),

    {comment, []}.

%% @doc We can use this function in tests since echo_server implements
%%      format_status/1 by returning the status as a map S.
%%      We can safely grab it from the result of sys:get_status/1
%% @see gen_server:format_status/1
%% @see sys:get_status/2
get_state(Atom) when is_atom(Atom) ->
    get_state(whereis(Atom));
get_state(Pid) ->
    {status, Pid, {module, gen_server}, [_PDict, _SysState, _Parent, _Dbg, Misc]} =
        sys:get_status(Pid),
    [State] =
        lists:filtermap(fun ({data, [{"State", State}]}) ->
                                {true, State};
                            (_) ->
                                false
                        end,
                        Misc),
    wpool_process:get_state(State).
