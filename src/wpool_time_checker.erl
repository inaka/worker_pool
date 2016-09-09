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
%%% @hidden
-module(wpool_time_checker).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

-type handler() :: {atom(), atom()}.

-record(state, { wpool    :: wpool:name()
               , handlers :: [handler()]
               }).
-type state() :: #state{}.

%% api
-export([ start_link/3
        , add_handler/2
        ]).

%% gen_server callbacks
-export([ init/1
        , terminate/2
        , code_change/3
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        ]).

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
%%% init, terminate, code_change, info callbacks
%%%===================================================================
%% @private
-spec init({wpool:name(), [{atom(), atom()}]}) -> {ok, state()}.
init({WPool, Handlers}) -> {ok, #state{wpool = WPool, handlers = Handlers}}.

%% @private
-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) -> ok.

%% @private
-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% @private
-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Cast, State) -> {noreply, State}.

-type from() :: {pid(), reference()}.
-spec handle_call({add_handler, handler()}, from(), state()) ->
        {reply, ok, state()}.
handle_call({add_handler, Handler}, _, State = #state{handlers = Handlers}) ->
  {reply, ok, State#state{handlers = [Handler | Handlers]}}.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
%% @private
-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info({check, Pid, TaskId, Runtime}, State) ->
  case erlang:process_info(Pid, dictionary) of
    {dictionary, Values} ->
      run_task(
        TaskId, proplists:get_value(wpool_task, Values), Pid,
        State#state.wpool, State#state.handlers, Runtime);
    _ -> ok
  end,
  {noreply, State};
handle_info(_Info, State) -> {noreply, State}.

run_task(TaskId, {TaskId, _, Task}, Pid, Pool, Handlers, Runtime) ->
  Args = [ {alert, overrun}, {pool, Pool}, {worker, Pid}, {task, Task}
         , {runtime, Runtime}],
  _ = [catch Mod:Fun(Args) || {Mod, Fun} <- Handlers],
  case 2 * Runtime of
    NewOverrunTime when NewOverrunTime =< 4294967295 ->
      erlang:send_after(
        Runtime, self(), {check, Pid, TaskId, NewOverrunTime}),
      ok;
    _ -> ok
  end;
run_task(_TaskId, _Value, _Pid, _Pool, _Handlers, _Runtime) -> ok.