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
%% @doc Decorator over {@link gen_server} that lets {@link wpool_pool}
%%      control certain aspects of the execution
-module(wpool_process).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

-record(state, {name    :: atom(),
                mod     :: atom(),
                state   :: term(),
                options :: [{time_checker|queue_manager, atom()} | wpool:option()],
                born = os:timestamp() :: erlang:timestamp()
               }).

%% api
-export([start_link/4, call/3, cast/2, age/1]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Starts a named process
-spec start_link(wpool:name(), module(), term(), [wpool:option()]) -> {ok, pid()} | ignore | {error, {already_started, pid()} | term()}.
start_link(Name, Module, InitArgs, Options) -> gen_server:start_link({local, Name}, ?MODULE, {Name, Module, InitArgs, Options}, []).

%% @equiv gen_server:call(Process, Call, Timeout)
-spec call(wpool:name() | pid(), term(), timeout()) -> term().
call(Process, Call, Timeout) -> gen_server:call(Process, Call, Timeout).

%% @equiv gen_server:cast(Process, Cast)
-spec cast(wpool:name() | pid(), term()) -> ok.
cast(Process, Cast) -> gen_server:cast(Process, Cast).

%% @doc Report how old a process is.
-spec age(wpool:name() | pid()) -> non_neg_integer().
age(Process) -> gen_server:call(Process, age).

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================
%% @private
-spec init({atom(), atom(), term(), [wpool:option()]}) -> {ok, #state{}}.
init({Name, Mod, InitArgs, Options}) ->
  case Mod:init(InitArgs) of
    {ok, Mod_State} ->
      ok = notify_queue_manager(new_worker, Name, Options),
      {ok, #state{name = Name, mod = Mod, state = Mod_State, options = Options}};
    ignore -> {stop, can_not_ignore};
    Error -> Error
  end.

%% @private
-spec terminate(atom(), #state{}) -> term().
terminate(Reason, #state{mod=Mod, state=Mod_State, name=Name, options=Options} = _State) ->
  ok = notify_queue_manager(worker_dead, Name, Options),
  Mod:terminate(Reason, Mod_State).

%% @private
-spec code_change(string(), #state{}, any()) -> {ok, #state{}} | {error, term()}.
code_change(OldVsn, State, Extra) ->
  case (State#state.mod):code_change(OldVsn, State#state.state, Extra) of
    {ok, NewState} -> {ok, State#state{state = NewState}};
    Error -> {error, Error}
  end.

%% @private
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
%% @private
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast(Cast, State) ->
  Task = task_init({cast, Cast},
                   proplists:get_value(time_checker, State#state.options, undefined),
                   proplists:get_value(overrun_warning, State#state.options, infinity)),
  ok = notify_queue_manager(worker_busy, State#state.name, State#state.options),
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
  ok = notify_queue_manager(worker_ready, State#state.name, State#state.options),
  Reply.

-type from() :: {pid(), reference()}.
%% @private
-spec handle_call(term(), from(), #state{}) -> {reply, term(), #state{}}.
handle_call(age, _From, #state{born=Born} = State) ->
    {reply, timer:now_diff(os:timestamp(), Born), State};
handle_call(Call, From, State) ->
  Task = task_init({call, Call},
                   proplists:get_value(time_checker, State#state.options, undefined),
                   proplists:get_value(overrun_warning, State#state.options, infinity)),
  ok = notify_queue_manager(worker_busy, State#state.name, State#state.options),
  Reply =
    try (State#state.mod):handle_call(Call, From, State#state.state) of
      {noreply, NewState} -> {stop, can_not_hold_a_reply, State#state{state = NewState}};
      {noreply, NewState, _Timeout} -> {stop, can_not_hold_a_reply, State#state{state = NewState}};
      {reply, Response, NewState} -> {reply, Response, State#state{state = NewState}};
      {reply, Response, NewState, Timeout} -> {reply, Response, State#state{state = NewState}, Timeout};
      {stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}};
      {stop, Reason, Response, NewState} -> {stop, Reason, Response, State#state{state = NewState}}
    catch
      _:{noreply, NewState} -> {stop, can_not_hold_a_reply, State#state{state = NewState}};
      _:{noreply, NewState, _Timeout} -> {stop, can_not_hold_a_reply, State#state{state = NewState}};
      _:{reply, Response, NewState} -> {reply, Response, State#state{state = NewState}};
      _:{reply, Response, NewState, Timeout} -> {reply, Response, State#state{state = NewState}, Timeout};
      _:{stop, Reason, NewState} -> {stop, Reason, State#state{state = NewState}};
      _:{stop, Reason, Response, NewState} -> {stop, Reason, Response, State#state{state = NewState}}
    end,
  task_end(Task),
  ok = notify_queue_manager(worker_ready, State#state.name, State#state.options),
  Reply.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PRIVATE FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Marks Task as started in this worker
-spec task_init(term(), atom(), infinity | pos_integer()) -> undefined | reference().
task_init(Task, _TimeChecker, infinity) ->
  erlang:put(wpool_task, {undefined, calendar:datetime_to_gregorian_seconds(calendar:universal_time()), Task}),
  undefined;
task_init(Task, TimeChecker, OverrunTime) ->
  TaskId = erlang:make_ref(),
  erlang:put(wpool_task, {TaskId, calendar:datetime_to_gregorian_seconds(calendar:universal_time()), Task}),
  erlang:send_after(OverrunTime, TimeChecker, {check, self(), TaskId, OverrunTime}).

%% @doc Removes the current task from the worker
-spec task_end(undefined | reference()) -> ok.
task_end(undefined) -> erlang:erase(wpool_task);
task_end(TimerRef) ->
  _ = erlang:cancel_timer(TimerRef),
  erlang:erase(wpool_task).

notify_queue_manager(Function, Name, Options) ->
  case proplists:get_value(queue_manager, Options) of
    undefined -> ok;
    QueueManager -> wpool_queue_manager:Function(QueueManager, Name)
  end.
