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
%%% @author Fernando Benavides <elbrujohalcon@inaka.net>
%%% @doc Decorator over {@link gen_server} that lets {@link wpool_pool}
%%%      control certain aspects of the execution
-module(wpool_process).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

-record(state, {name    :: atom(),
                mod     :: atom(),
                state   :: term(),
                options :: [ {time_checker|queue_manager, atom()}
                           | wpool:option()
                           ]
               }).
-type state() :: #state{}.

-type from() :: {pid(), reference()}.

%% api
-export([ start_link/4
        , call/3
        , cast/2
        , cast_call/3
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
%% @doc Starts a named process
-spec start_link(wpool:name(), module(), term(), [wpool:option()]) ->
        {ok, pid()} | ignore | {error, {already_started, pid()} | term()}.
start_link(Name, Module, InitArgs, Options) ->
  WorkerOpt = proplists:get_value(worker_opt, Options, []),
  gen_server:start_link(
    {local, Name}, ?MODULE, {Name, Module, InitArgs, Options}, WorkerOpt).

%% @equiv gen_server:call(Process, Call, Timeout)
-spec call(wpool:name() | pid(), term(), timeout()) -> term().
call(Process, Call, Timeout) -> gen_server:call(Process, Call, Timeout).

%% @equiv gen_server:cast(Process, {cast, Cast})
-spec cast(wpool:name() | pid(), term()) -> ok.
cast(Process, Cast) -> gen_server:cast(Process, {cast, Cast}).

%% @equiv gen_server:cast(Process, {call, From, Call})
-spec cast_call(wpool:name() | pid(), from(), term()) -> ok.
cast_call(Process, From, Call) ->
  gen_server:cast(Process, {call, From, Call}).

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================
%% @private
-spec init({atom(), atom(), term(), [wpool:option()]}) -> {ok, state()}.
init({Name, Mod, InitArgs, Options}) ->
  case Mod:init(InitArgs) of
    {ok, ModState} ->
      ok = wpool_utils:notify_queue_manager(new_worker, Name, Options),
      {ok, #state{ name = Name
                 , mod = Mod
                 , state = ModState
                 , options = Options
                 }};
    {ok, ModState, Timeout} ->
      ok = wpool_utils:notify_queue_manager(new_worker, Name, Options),
      {ok, #state{ name = Name
                 , mod = Mod
                 , state = ModState
                 , options = Options
                 }, Timeout};
    ignore -> {stop, can_not_ignore};
    Error -> Error
  end.

%% @private
-spec terminate(atom(), state()) -> term().
terminate(Reason, State) ->
  #state{mod=Mod, state=ModState, name=Name, options=Options} = State,
  ok = wpool_utils:notify_queue_manager(worker_dead, Name, Options),
  Mod:terminate(Reason, ModState).

%% @private
-spec code_change(string(), state(), any()) -> {ok, state()} | {error, term()}.
code_change(OldVsn, State, Extra) ->
  case (State#state.mod):code_change(OldVsn, State#state.state, Extra) of
    {ok, NewState} -> {ok, State#state{state = NewState}};
    Error -> {error, Error}
  end.

%% @private
-spec handle_info(any(), state()) ->
        {noreply, state()} | {stop, term(), state()}.
handle_info(Info, State) ->
  case wpool_utils:do_try(
        fun() -> (State#state.mod):handle_info(Info, State#state.state) end) of
    {noreply, NewState} ->
      {noreply, State#state{state = NewState}};
    {noreply, NewState, Timeout} ->
      {noreply, State#state{state = NewState}, Timeout};
    {stop, Reason, NewState} ->
      {stop, Reason, State#state{state = NewState}}
  end.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
%% @private
-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({call, From, Call}, State) ->
  case handle_call(Call, From, State) of
    {reply, Response, NewState} ->
      gen_server:reply(From, Response),
      {noreply, NewState};
    {reply, Response, NewState, Timeout} ->
      gen_server:reply(From, Response),
      {noreply, NewState, Timeout};
    {stop, Reason, Response, NewState} ->
      gen_server:reply(From, Response),
      {stop, Reason, NewState};
    Reply -> Reply
  end;
handle_cast({cast, Cast}, State) ->
  Task =
    wpool_utils:task_init(
      {cast, Cast},
      proplists:get_value(time_checker, State#state.options, undefined),
      proplists:get_value(overrun_warning, State#state.options, infinity)),
  ok = wpool_utils:notify_queue_manager(worker_busy
                                        , State#state.name
                                        , State#state.options),
  Reply =
    case wpool_utils:do_try(
        fun() -> (State#state.mod):handle_cast(Cast, State#state.state) end) of
      {noreply, NewState} ->
        {noreply, State#state{state = NewState}};
      {noreply, NewState, Timeout} ->
        {noreply, State#state{state = NewState}, Timeout};
      {stop, Reason, NewState} ->
        {stop, Reason, State#state{state = NewState}}
    end,
  wpool_utils:task_end(Task),
  ok =
    wpool_utils:notify_queue_manager(worker_ready
                                    , State#state.name
                                    , State#state.options),
  Reply.

%% @private
-spec handle_call(term(), from(), state()) ->
        {reply, term(), state()}
      | {reply, term(), state(), timeout() | hibernate}
      | {noreply, state()}
      | {noreply, state(), timeout() | hibernate}
      | {stop, term(), term(), state()}
      | {stop, term(), state()}.
handle_call(Call, From, State) ->
  Task =
    wpool_utils:task_init(
      {call, Call},
      proplists:get_value(time_checker, State#state.options, undefined),
      proplists:get_value(overrun_warning, State#state.options, infinity)),
  ok = wpool_utils:notify_queue_manager(worker_busy
                                        , State#state.name
                                        , State#state.options),
  Reply =
    case wpool_utils:do_try(
        fun() -> (State#state.mod):handle_call(Call, From, State#state.state)
        end) of
      {noreply, NewState} ->
        {noreply, State#state{state = NewState}};
      {noreply, NewState, Timeout} ->
        {noreply, State#state{state = NewState}, Timeout};
      {reply, Response, NewState} ->
        {reply, Response, State#state{state = NewState}};
      {reply, Response, NewState, Timeout} ->
        {reply, Response, State#state{state = NewState}, Timeout};
      {stop, Reason, NewState} ->
        {stop, Reason, State#state{state = NewState}};
      {stop, Reason, Response, NewState} ->
        {stop, Reason, Response, State#state{state = NewState}}
    end,
  wpool_utils:task_end(Task),
  ok =
    wpool_utils:notify_queue_manager(worker_ready
                                    , State#state.name
                                    , State#state.options),
  Reply.
