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
%%% @author Felipe Ripoll <ferigis@gmail.com>
%%% @doc Decorator over {@link gen_fsm} that lets {@link wpool_pool}
%%%      control certain aspects of the execution
-module(wpool_fsm_process).
-author('ferigis@gmail.com').

-behaviour(gen_fsm).

-record(state, { name    :: atom()
               , mod     :: atom()
               , state   :: term()
               , options :: [ {time_checker|queue_manager, atom()}
                            | wpool:option()
                            ]
               , fsm_state :: fsm_state()
               }).
-type state() :: #state{}.
-type fsm_state() :: atom().
-type from() :: {pid(), reference()}.

-export([ start_link/4
        , send_event/2
        , sync_send_event/2
        , sync_send_event/3
        , send_all_state_event/2
        , sync_send_all_state_event/2
        , sync_send_all_state_event/3
        , cast_call/3
        , cast_call_all/3
        ]).
-export([ dispatch_state/2
        , dispatch_state/3
        ]).
-export([ init/1
        , terminate/3
        , code_change/4
        , handle_info/3
        , handle_event/3
        , handle_sync_event/4
        , format_status/2
        ]).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Starts a named process
-spec start_link(wpool:name(), module(), term(), [wpool:option()]) ->
        {ok, pid()} | ignore | {error, {already_started, pid()} | term()}.
start_link(Name, Module, InitArgs, Options) ->
  WorkerOpt = proplists:get_value(worker_opt, Options, []),
  gen_fsm:start_link(
    {local, Name}, ?MODULE, {Name, Module, InitArgs, Options}, WorkerOpt).

-spec send_event(wpool:name() | pid(), term()) -> term().
send_event(Process, Event) ->
  gen_fsm:send_event(Process, Event).

-spec sync_send_event(wpool:name() | pid(), term()) -> term().
sync_send_event(Process, Event) ->
  gen_fsm:sync_send_event(Process, Event).

-spec sync_send_event(wpool:name() | pid(), term(), timeout()) -> term().
sync_send_event(Process, Event, Timeout) ->
  gen_fsm:sync_send_event(Process, Event, Timeout).

-spec send_all_state_event(wpool:name() | pid(), term()) -> term().
send_all_state_event(Process, Event) ->
  gen_fsm:send_all_state_event(Process, Event).

-spec sync_send_all_state_event(wpool:name() | pid(), term()) -> term().
sync_send_all_state_event(Process, Event) ->
  gen_fsm:sync_send_all_state_event(Process, Event).

-spec sync_send_all_state_event(wpool:name() | pid(), term(), timeout()) ->
        term().
sync_send_all_state_event(Process, Event, Timeout) ->
  gen_fsm:sync_send_all_state_event(Process, Event, Timeout).

%% @equiv gen_fsm:send_event(Process, {sync_send_event, From, Event})
-spec cast_call(wpool:name() | pid(), from(), term()) -> ok.
cast_call(Process, From, Event) ->
  gen_fsm:send_event(Process, {sync_send_event, From, Event}).

%% @equiv gen_fsm:send_all_state_event(Process, {sync_send_event, From, Event})
-spec cast_call_all(wpool:name() | pid(), from(), term()) -> ok.
cast_call_all(Process, From, Event) ->
  gen_fsm:send_all_state_event(Process, {sync_send_event, From, Event}).

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================
%% @private
-spec init({atom(), atom(), term(), [wpool:option()]}) ->
  {ok, dispatch_state, state()}.
init({Name, Mod, InitArgs, Options}) ->
  case Mod:init(InitArgs) of
    {ok, FirstState, StateData} ->
      ok = wpool_utils:notify_queue_manager(new_worker, Name, Options),
      {ok, dispatch_state, #state{ name = Name
                              , mod = Mod
                              , state = StateData
                              , options = Options
                              , fsm_state = FirstState}};
    {ok, FirstState, StateData, Timeout} ->
      ok = wpool_utils:notify_queue_manager(new_worker, Name, Options),
      {ok, dispatch_state, #state{ name = Name
                              , mod = Mod
                              , state = StateData
                              , options = Options
                              , fsm_state = FirstState}, Timeout};
    ignore -> {stop, can_not_ignore};
    Error -> Error
  end.

%% @private
-spec terminate(atom(), fsm_state(), state()) -> term().
terminate(Reason, CurrentState, State) ->
  #state{ mod     = Mod
        , state   = ModState
        , name    = Name
        , options = Options
        } = State,
  ok = wpool_utils:notify_queue_manager(worker_dead, Name, Options),
  Mod:terminate(Reason, CurrentState, ModState).

%% @private
-spec code_change(string(), fsm_state(), state(), any()) ->
        {ok, dispatch_state, state()}.
code_change(OldVsn, StateName, State, Extra) ->
  case (State#state.mod):code_change(
        OldVsn, StateName, State#state.state, Extra) of
    {ok, NextStateName, NewState} ->
      {ok, dispatch_state, State#state{ state = NewState
                                      , fsm_state = NextStateName
                                      }};
    _Error -> {ok, dispatch_state, State}
  end.

%% @private
-spec handle_info(any(), fsm_state(), state()) ->
        {next_state, dispatch_state, state()} | {stop, term(), state()}.
handle_info(Info, StateName, StateData) ->
  case wpool_utils:do_try(
        fun() ->
          (StateData#state.mod):handle_info(
            Info, StateName, StateData#state.state)
        end) of
    {next_state, NextStateName, NewStateData} ->
      {next_state, dispatch_state, StateData#state{ state = NewStateData
                                                  , fsm_state = NextStateName
                                                  }};
    {next_state, NextStateName, NewStateData, Timeout} ->
      { next_state
      , dispatch_state
      , StateData#state{ state = NewStateData
                       , fsm_state = NextStateName
                       }
      , Timeout
      };
    {stop, Reason, NewStateData} ->
      {stop, Reason, StateData#state{state = NewStateData}}
  end.

-spec format_status(normal | terminate, list()) -> term().
format_status(Opt, [PDict, StateData]) ->
  (StateData#state.mod):format_status(Opt, [PDict, StateData#state.state]).

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
-spec handle_event(term(), fsm_state(), state()) ->
    {next_state, dispatch_state, state()}
  | {next_state, dispatch_state, state(), timeout()}
  | {stop, term(), state()}.
handle_event({sync_send_event, From, Event}, StateName, StateData) ->
  case ?MODULE:handle_sync_event(Event, From, StateName, StateData) of
    {reply, Reply, NextState, NextData} ->
      gen_fsm:reply(From, Reply),
      {next_state, NextState, NextData};
    {reply, Reply, NextState, NextData, Timeout} ->
      gen_fsm:reply(From, Reply),
      {next_state, NextState, NextData, Timeout};
    {stop, Reason, Reply, NextData} ->
      gen_fsm:reply(From, Reply),
      {stop, Reason, NextData};
    Other ->
      Other
  end;
handle_event(Event, _StateName, StateData) ->
  Task =
    wpool_utils:task_init(
      {handle_event, Event},
      proplists:get_value(time_checker, StateData#state.options, undefined),
      proplists:get_value(overrun_warning, StateData#state.options, infinity)),
  ok =
    wpool_utils:notify_queue_manager(
      worker_busy, StateData#state.name, StateData#state.options),
  Reply =
    case wpool_utils:do_try(
        fun() ->
          (StateData#state.mod):handle_event(Event,
              StateData#state.fsm_state, StateData#state.state)
        end) of
      {next_state, NextStateName, NewStateData} ->
        {next_state, dispatch_state, StateData#state{ state = NewStateData
                                                    , fsm_state = NextStateName
                                                    }};
      {next_state, NextStateName, NewStateData, Timeout} ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        , Timeout
        };
      {stop, Reason, NewState} ->
        {stop, Reason, StateData#state{state = NewState}}
    end,
  wpool_utils:task_end(Task),
  ok =
    wpool_utils:notify_queue_manager(
      worker_ready, StateData#state.name, StateData#state.options),
  Reply.

-spec handle_sync_event(term(), from(), fsm_state(), state()) ->
          {reply, term(), dispatch_state, state()}
        | {reply, term(), dispatch_state, state(), timeout()}
        | {next_state, dispatch_state, state()}
        | {next_state, dispatch_state, state(), timeout()}
        | {stop, term(), term(), state()}
        | {stop, term(), state()}.
handle_sync_event(Event, From, _StateName, StateData) ->
  Task =
    wpool_utils:task_init(
      {handle_sync_event, Event},
      proplists:get_value(time_checker, StateData#state.options, undefined),
      proplists:get_value(overrun_warning, StateData#state.options, infinity)),
  ok =
    wpool_utils:notify_queue_manager(
      worker_busy, StateData#state.name, StateData#state.options),
  Result =
    case wpool_utils:do_try(
        fun() ->
          (StateData#state.mod):handle_sync_event(
            Event, From, StateData#state.fsm_state, StateData#state.state)
        end) of
      {reply, Reply, NextStateName, NewStateData} ->
        { reply
        , Reply
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        };
      {reply, Reply, NextStateName, NewStateData, Timeout} ->
        { reply
        , Reply
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        , Timeout
        };
      {next_state, NextStateName, NewStateData} ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        };
      {next_state, NextStateName, NewStateData, Timeout} ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        , Timeout
        };
      {stop, Reason, NewState} ->
        {stop, Reason, StateData#state{state = NewState}};
      {stop, Reason, Response, NewState} ->
        {stop, Reason, Response, StateData#state{state = NewState}}
    end,
  wpool_utils:task_end(Task),
  ok =
    wpool_utils:notify_queue_manager(worker_ready,
                        StateData#state.name,
                        StateData#state.options),
  Result.

%%%===================================================================
%%% FSM States
%%%===================================================================
-spec dispatch_state(term(), state()) ->
        {next_state, dispatch_state, state()} | {stop, term(), state()}.
dispatch_state({sync_send_event, From, Event}, StateData) ->
  case dispatch_state(Event, From, StateData) of
    {reply, Reply, dispatch_state, StateData} ->
      gen_fsm:reply(From, Reply),
      {next_state, dispatch_state, StateData};
    {reply, Reply, dispatch_state, StateData, Timeout} ->
      gen_fsm:reply(From, Reply),
      {next_state, dispatch_state, StateData, Timeout};
    {stop, Reason, Reply, StateData} ->
      gen_fsm:reply(From, Reply),
      {stop, Reason, StateData};
    Reply -> Reply
  end;
dispatch_state(Event, StateData) ->
  Task = get_task(Event, StateData),
  ok =
    wpool_utils:notify_queue_manager(
      worker_busy, StateData#state.name, StateData#state.options),
  Reply =
    case wpool_utils:do_try(
        fun() ->
          (StateData#state.mod):(StateData#state.fsm_state)(
            Event, StateData#state.state)
        end) of
      {next_state, NextStateName, NewStateData}  ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        };
      {next_state, NextStateName, NewStateData, Timeout} ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        , Timeout
        };
      {stop, Reason, NewStateData} ->
        {stop, Reason, StateData#state{state = NewStateData}}
    end,
  wpool_utils:task_end(Task),
  ok =
    wpool_utils:notify_queue_manager(
      worker_ready, StateData#state.name, StateData#state.options),
  Reply.

-spec dispatch_state(term(), from(), state()) ->
          {next_state, dispatch_state, state()}
        | {next_state, dispatch_state, state(), timeout()}
        | {reply, term(), dispatch_state, state()}
        | {reply, term(), dispatch_state, state(), timeout()}
        | {stop, term(), term(), state()}
        | {stop, term(), state()}.
dispatch_state(Event, From, StateData) ->
  Task = get_task(Event, StateData),
  ok =
    wpool_utils:notify_queue_manager(
      worker_busy, StateData#state.name, StateData#state.options),
  Result =
    case wpool_utils:do_try(
        fun() ->
          (StateData#state.mod):(StateData#state.fsm_state)(
            Event, From, StateData#state.state)
        end) of
      {reply, Reply, NextStateName, NewStateData} ->
        { reply
        , Reply
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        };
      {reply, Reply, NextStateName, NewStateData, Timeout} ->
        { reply
        , Reply
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        , Timeout
        };
      {next_state, NextStateName, NewStateData}  ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        };
      {next_state, NextStateName, NewStateData, Timeout} ->
        { next_state
        , dispatch_state
        , StateData#state{ state = NewStateData
                         , fsm_state = NextStateName
                         }
        , Timeout
        };
      {stop, Reason, NewStateData} ->
        {stop, Reason, StateData#state{state = NewStateData}};
      {stop, Reason, Reply, NewStateData} ->
        {stop, Reason, Reply, StateData#state{state = NewStateData}}
    end,
  wpool_utils:task_end(Task),
  ok =
    wpool_utils:notify_queue_manager(
      worker_ready, StateData#state.name, StateData#state.options),
  Result.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PRIVATE FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_task(Event, StateData) ->
  wpool_utils:task_init(
    {dispatch_state, Event},
    proplists:get_value(time_checker, StateData#state.options, undefined),
    proplists:get_value(overrun_warning, StateData#state.options, infinity)).
