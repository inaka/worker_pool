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
%%% @private
-module(wpool_time_checker).

-behaviour(gen_server).

-type handler() :: {atom(), atom()}.

-export_type([handler/0]).

-record(state, {wpool :: wpool:name(), handlers :: [handler()]}).

-opaque state() :: #state{}.

-export_type([state/0]).

-type from() :: {pid(), reference()}.

-export_type([from/0]).

%% api
-export([start_link/3, add_handler/2]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-elvis([{elvis_style, no_catch_expressions, disable}]).

%%%===================================================================
%%% API
%%%===================================================================
%% @private
-spec start_link(wpool:name(), atom(), handler() | [handler()]) ->
                    {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name, Handlers) when is_list(Handlers) ->
    gen_server:start_link({local, Name}, ?MODULE, {WPool, Handlers}, []);
start_link(WPool, Name, Handler) when is_tuple(Handler) ->
    start_link(WPool, Name, [Handler]).

%% @private
-spec add_handler(atom(), handler()) -> ok.
add_handler(Name, Handler) ->
    gen_server:call(Name, {add_handler, Handler}).

%%%===================================================================
%%% simple callbacks
%%%===================================================================
%% @private
-spec init({wpool:name(), [{atom(), atom()}]}) -> {ok, state()}.
init({WPool, Handlers}) ->
    {ok, #state{wpool = WPool, handlers = Handlers}}.

%% @private
-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Cast, State) ->
    {noreply, State}.

-spec handle_call({add_handler, handler()}, from(), state()) -> {reply, ok, state()}.
handle_call({add_handler, Handler}, _, #state{handlers = Handlers} = State) ->
    {reply, ok, State#state{handlers = [Handler | Handlers]}}.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
%% @private
-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info({check, Pid, TaskId, Runtime, WarningsLeft}, State) ->
    case erlang:process_info(Pid, dictionary) of
        {dictionary, Values} ->
            run_task(TaskId,
                     proplists:get_value(wpool_task, Values),
                     Pid,
                     State#state.wpool,
                     State#state.handlers,
                     Runtime,
                     WarningsLeft);
        _ ->
            ok
    end,
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

run_task(TaskId, {TaskId, _, Task}, Pid, Pool, Handlers, Runtime, 1) ->
    send_reports(Handlers, max_overrun_limit, Pool, Pid, Task, Runtime),
    exit(Pid, kill),
    ok;
run_task(TaskId, {TaskId, _, Task}, Pid, Pool, Handlers, Runtime, WarningsLeft) ->
    send_reports(Handlers, overrun, Pool, Pid, Task, Runtime),
    case new_overrun_time(Runtime, WarningsLeft) of
        NewOverrunTime when NewOverrunTime =< 4294967295 ->
            erlang:send_after(Runtime,
                              self(),
                              {check,
                               Pid,
                               TaskId,
                               NewOverrunTime,
                               decrease_warnings(WarningsLeft)}),
            ok;
        _ ->
            ok
    end;
run_task(_TaskId, _Value, _Pid, _Pool, _Handlers, _Runtime, _WarningsLeft) ->
    ok.

-spec new_overrun_time(pos_integer(), pos_integer() | infinity) -> pos_integer().
new_overrun_time(Runtime, infinity) ->
    Runtime;
new_overrun_time(Runtime, _) ->
    Runtime * 2.

-spec decrease_warnings(pos_integer() | infinity) -> non_neg_integer() | infinity.
decrease_warnings(infinity) ->
    infinity;
decrease_warnings(N) ->
    N - 1.

-spec send_reports([{atom(), atom()}],
                   atom(),
                   atom(),
                   pid(),
                   term(),
                   infinity | pos_integer()) ->
                      ok.
send_reports(Handlers, Alert, Pool, Pid, Task, Runtime) ->
    Args = [{alert, Alert}, {pool, Pool}, {worker, Pid}, {task, Task}, {runtime, Runtime}],
    _ = [catch Mod:Fun(Args) || {Mod, Fun} <- Handlers],
    ok.
