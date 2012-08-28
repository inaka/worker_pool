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

-module(wpool_process).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

-record(state, {mod     :: atom(),
                state   :: term(),
                options :: [wpool:option()]}).

%% api
-export([start_link/4, call/2, cast/2]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link(wpool:name(), module(), term(), [wpool:option()]) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(Name, Module, InitArgs, Options) -> gen_server:start_link(Name, ?MODULE, {Module, InitArgs, Options}, []).

-spec call(wpool:name(), term()) -> term().
call(Process, Call) -> gen_server:call(Process, Call).

-spec cast(wpool:name(), term()) -> ok.
cast(Process, Cast) -> gen_server:cast(Process, Cast).

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================
-spec init({atom(), term(), [wpool:option()]}) -> {ok, #state{}}.
init({Mod, InitArgs, Options}) ->
  case Mod:init(InitArgs) of
    {ok, State} -> {ok, #state{mod = Mod, state = State, options = Options}};
    Error -> Error
  end.

-spec terminate(atom(), #state{}) -> term().
terminate(Reason, State) -> (State#state.mod):terminate(Reason, State#state.state).

-spec code_change(string(), #state{}, any()) -> {ok, {}} | {stop, term(), #state{}}.
code_change(OldVsn, State, Extra) ->
  case (State#state.mod):code_change(OldVsn, State#state.state, Extra) of
    {ok, NewState} -> {ok, State#state{state = NewState}};
    Error -> {stop, Error, State}
  end.

-spec handle_info(any(), #state{}) -> {noreply, #state{}} | {stop, term(), #state{}}.
handle_info(Info, State) ->
  try (State#state.mod):handle_info(Info, State#state.state) of
    {noreply, NewState} -> {noreply, State#state{state = NewState}};
    {noreply, NewState, Timeout} -> {noreply, State#state{state = NewState}, Timeout};
    {stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}}
  catch
    _:{noreply, NewState} -> {noreply, State#state{state = NewState}};
    _:{noreply, NewState, Timeout} -> {noreply, State#state{state = NewState}, Timeout};
    _:{stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}}
  end.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast(Cast, State) ->
  Task = task_init({cast, Cast},
                   proplists:get_value(time_checker, State#state.options, undefined),
                   proplists:get_value(timeout_warning, State#state.options, infinity)),
  Reply =
    try (State#state.mod):handle_cast(Cast, State#state.state) of
      {noreply, NewState} -> {noreply, State#state{state = NewState}};
      {noreply, NewState, Timeout} -> {noreply, State#state{state = NewState}, Timeout};
      {stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}}
    catch
      _:{noreply, NewState} -> {noreply, State#state{state = NewState}};
      _:{noreply, NewState, Timeout} -> {noreply, State#state{state = NewState}, Timeout};
      _:{stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}}
    end,
  task_end(Task),
  Reply.

-type from() :: {pid(), reference()}.
-spec handle_call(term(), from(), #state{}) -> {reply, term(), #state{}}.
handle_call(Call, From, State) ->
  Task = task_init({call, Call},
                   proplists:get_value(time_checker, State#state.options, undefined),
                   proplists:get_value(timeout_warning, State#state.options, infinity)),
  Reply =
    try (State#state.mod):handle_call(Call, From, State#state.state) of
      {noreply, NewState} -> {noreply, State#state{state = NewState}};
      {noreply, NewState, Timeout} -> {noreply, State#state{state = NewState}, Timeout};
      {reply, Response, NewState} -> {reply, Response, State#state{state = NewState}};
      {reply, Response, NewState, Timeout} -> {reply, Response, State#state{state = NewState}, Timeout};
      {stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}};
      {stop, Reason, Response, NewState} -> {stop, Reason, Response, State#state{state = NewState}}
    catch
      _:{noreply, NewState} -> {noreply, State#state{state = NewState}};
      _:{noreply, NewState, Timeout} -> {noreply, State#state{state = NewState}, Timeout};
      _:{reply, Response, NewState} -> {reply, Response, State#state{state = NewState}};
      _:{reply, Response, NewState, Timeout} -> {reply, Response, State#state{state = NewState}, Timeout};
      _:{stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}};
      _:{stop, Reason, Response, NewState} -> {stop, Reason, Response, State#state{state = NewState}}
    end,
  task_end(Task),
  Reply.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PRIVATE FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Marks Task as started in this worker
-spec task_init(term(), atom(), infinity | pos_integer()) -> undefined | reference().
task_init(Task, _TimeChecker, infinity) ->
  erlang:put(wpool_task, {undefined, calendar:datetime_to_gregorian_seconds(calendar:universal_time()), Task}),
  undefined;
task_init(Task, TimeChecker, Timeout) ->
  TaskId = erlang:make_ref(),
  erlang:put(wpool_task, {TaskId, calendar:datetime_to_gregorian_seconds(calendar:universal_time()), Task}),
  erlang:send_after(Timeout * 1000, TimeChecker, {check, self(), TaskId, Timeout}).

%% @doc Removes the current task from the worker
-spec task_end(undefined | reference()) -> ok.
task_end(undefined) -> ok;
task_end(TimerRef) ->
  erlang:cancel_timer(TimerRef),
  erlang:erase(wpool_task).