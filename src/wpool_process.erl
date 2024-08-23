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
%%% @doc Decorator over `gen_server' that lets `wpool_pool'
%%%      control certain aspects of the execution
-module(wpool_process).

-behaviour(gen_server).

%% Taken from gen_server OTP
-record(callback_cache,
        {module :: module(),
         handle_call ::
             fun((Request :: term(), From :: from(), State :: term()) ->
                     {reply, Reply :: term(), NewState :: term()} |
                     {reply,
                      Reply :: term(),
                      NewState :: term(),
                      timeout() | hibernate | {continue, term()}} |
                     {noreply, NewState :: term()} |
                     {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
                     {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
                     {stop, Reason :: term(), NewState :: term()}),
         handle_cast ::
             fun((Request :: term(), State :: term()) ->
                     {noreply, NewState :: term()} |
                     {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
                     {stop, Reason :: term(), NewState :: term()}),
         handle_info ::
             fun((Info :: timeout | term(), State :: term()) ->
                     {noreply, NewState :: term()} |
                     {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
                     {stop, Reason :: term(), NewState :: term()})}).
-record(state,
        {name :: atom(),
         mod :: #callback_cache{},
         state :: term(),
         options ::
             #{time_checker := atom(),
               queue_manager := atom(),
               overrun_warning := timeout(),
               _ => _}}).

-opaque state() :: #state{}.

-export_type([state/0]).

-type from() :: {pid(), reference()}.

-export_type([from/0]).

-type next_step() :: timeout() | hibernate | {continue, term()}.

-export_type([next_step/0]).

-type options() :: [{time_checker | queue_manager, atom()} | wpool:option()].

-export_type([options/0]).

%% api
-export([start_link/4, call/3, cast/2, send_request/2]).

-ifdef(TEST).

-export([get_state/1]).

-endif.

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2,
         handle_continue/2, format_status/1]).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Starts a named process
-spec start_link(wpool:name(), module(), term(), options()) ->
                    {ok, pid()} | ignore | {error, {already_started, pid()} | term()}.
start_link(Name, Module, InitArgs, Options) ->
    FullOpts = wpool_utils:add_defaults(Options),
    WorkerOpt = proplists:get_value(worker_opt, FullOpts, []),
    gen_server:start_link({local, Name},
                          ?MODULE,
                          {Name, Module, InitArgs, FullOpts},
                          WorkerOpt).

%% @equiv gen_server:call(Process, Call, Timeout)
-spec call(wpool:name() | pid(), term(), timeout()) -> term().
call(Process, Call, Timeout) ->
    gen_server:call(Process, Call, Timeout).

%% @equiv gen_server:cast(Process, {cast, Cast})
-spec cast(wpool:name() | pid(), term()) -> ok.
cast(Process, Cast) ->
    gen_server:cast(Process, Cast).

%% @equiv gen_server:send_request(Process, Request)
-spec send_request(wpool:name() | pid(), term()) -> gen_server:request_id().
send_request(Name, Request) ->
    gen_server:send_request(Name, Request).

-ifdef(TEST).

-spec get_state(state()) -> term().
get_state(#state{state = State}) ->
    State.

-endif.

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================
%% @private
-spec init({atom(), atom(), term(), options()}) ->
              {ok, state()} | {ok, state(), next_step()} | {stop, can_not_ignore} | {stop, term()}.
init({Name, Mod, InitArgs, LOptions}) ->
    Options = maps:from_list(LOptions),
    wpool_process_callbacks:notify(handle_init_start, Options, [Name]),
    CbCache = create_callback_cache(Mod),
    case Mod:init(InitArgs) of
        {ok, ModState} ->
            ok = notify_queue_manager(new_worker, Name, Options),
            wpool_process_callbacks:notify(handle_worker_creation, Options, [Name]),
            {ok,
             #state{name = Name,
                    mod = CbCache,
                    state = ModState,
                    options = Options}};
        {ok, ModState, NextStep} ->
            ok = notify_queue_manager(new_worker, Name, Options),
            wpool_process_callbacks:notify(handle_worker_creation, Options, [Name]),
            {ok,
             #state{name = Name,
                    mod = CbCache,
                    state = ModState,
                    options = Options},
             NextStep};
        ignore ->
            {stop, can_not_ignore};
        Error ->
            Error
    end.

%% @private
-spec terminate(atom(), state()) -> term().
terminate(Reason, State) ->
    #state{mod = #callback_cache{module = Mod},
           state = ModState,
           name = Name,
           options = Options} =
        State,
    ok = notify_queue_manager(worker_dead, Name, Options),
    wpool_process_callbacks:notify(handle_worker_death, Options, [Name, Reason]),
    case erlang:function_exported(Mod, terminate, 2) of
        true ->
            Mod:terminate(Reason, ModState);
        _ ->
            ok
    end.

%% @private
-spec code_change(string() | {down, string()}, state(), any()) ->
                     {ok, state()} | {error, term()}.
code_change(OldVsn, #state{mod = #callback_cache{module = Mod}} = State, Extra) ->
    case erlang:function_exported(Mod, code_change, 3) of
        true ->
            case Mod:code_change(OldVsn, State#state.state, Extra) of
                {ok, NewState} ->
                    {ok, State#state{state = NewState}};
                {error, Error} ->
                    {error, Error}
            end;
        _ ->
            {ok, State}
    end.

%% @private
-spec handle_info(any(), state()) ->
                     {noreply, state()} | {noreply, state(), next_step()} | {stop, term(), state()}.
handle_info(Info, #state{mod = CbCache} = State) ->
    #callback_cache{module = Mod, handle_info = HandleInfo} = CbCache,
    try HandleInfo(Info, State#state.state) of
        {noreply, NewState} ->
            {noreply, State#state{state = NewState}};
        {noreply, NewState, NextStep} ->
            {noreply, State#state{state = NewState}, NextStep};
        {stop, Reason, NewState} ->
            {stop, Reason, State#state{state = NewState}}
    catch
        error:undef:Stacktrace ->
            case erlang:function_exported(Mod, handle_info, 2) of
                false ->
                    {noreply, State};
                true ->
                    erlang:raise(error, undef, Stacktrace)
            end;
        _:{noreply, NewState} ->
            {noreply, State#state{state = NewState}};
        _:{noreply, NewState, NextStep} ->
            {noreply, State#state{state = NewState}, NextStep};
        _:{stop, Reason, NewState} ->
            {stop, Reason, State#state{state = NewState}}
    end.

%% @private
-spec handle_continue(any(), state()) ->
                         {noreply, state()} |
                         {noreply, state(), next_step()} |
                         {stop, term(), state()}.
handle_continue(Continue, #state{mod = #callback_cache{module = Mod}} = State) ->
    try Mod:handle_continue(Continue, State#state.state) of
        {noreply, NewState} ->
            {noreply, State#state{state = NewState}};
        {noreply, NewState, NextStep} ->
            {noreply, State#state{state = NewState}, NextStep};
        {stop, Reason, NewState} ->
            {stop, Reason, State#state{state = NewState}}
    catch
        _:{noreply, NewState} ->
            {noreply, State#state{state = NewState}};
        _:{noreply, NewState, NextStep} ->
            {noreply, State#state{state = NewState}, NextStep};
        _:{stop, Reason, NewState} ->
            {stop, Reason, State#state{state = NewState}}
    end.

%% @private
-spec format_status(gen_server:format_status()) -> gen_server:format_status().
format_status(#{state := #state{mod = #callback_cache{module = Mod}}} = Status) ->
    case erlang:function_exported(Mod, format_status, 1) of
        false ->
            Status;
        true ->
            Mod:format_status(Status)
    end.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
%% @private
-spec handle_cast(term(), state()) ->
                     {noreply, state()} | {noreply, state(), next_step()} | {stop, term(), state()}.
handle_cast(Cast, #state{mod = CbCache, options = Options} = State) ->
    #callback_cache{handle_cast = HandleCast} = CbCache,
    Task = wpool_utils:task_init({cast, Cast}, Options),
    ok = notify_queue_manager(worker_busy, State#state.name, Options),
    Reply =
        try HandleCast(Cast, State#state.state) of
            {noreply, NewState} ->
                {noreply, State#state{state = NewState}};
            {noreply, NewState, NextStep} ->
                {noreply, State#state{state = NewState}, NextStep};
            {stop, Reason, NewState} ->
                {stop, Reason, State#state{state = NewState}}
        catch
            _:{noreply, NewState} ->
                {noreply, State#state{state = NewState}};
            _:{noreply, NewState, NextStep} ->
                {noreply, State#state{state = NewState}, NextStep};
            _:{stop, Reason, NewState} ->
                {stop, Reason, State#state{state = NewState}}
        end,
    wpool_utils:task_end(Task),
    ok = notify_queue_manager(worker_ready, State#state.name, Options),
    Reply.

%% @private
-spec handle_call(term(), from(), state()) ->
                     {reply, term(), state()} |
                     {reply, term(), state(), next_step()} |
                     {noreply, state()} |
                     {noreply, state(), next_step()} |
                     {stop, term(), term(), state()} |
                     {stop, term(), state()}.
handle_call(Call, From, #state{mod = CbCache, options = Options} = State) ->
    #callback_cache{handle_call = HandleCall} = CbCache,
    Task = wpool_utils:task_init({call, Call}, Options),
    ok = notify_queue_manager(worker_busy, State#state.name, Options),
    Reply =
        try HandleCall(Call, From, State#state.state) of
            {noreply, NewState} ->
                {noreply, State#state{state = NewState}};
            {noreply, NewState, NextStep} ->
                {noreply, State#state{state = NewState}, NextStep};
            {reply, Response, NewState} ->
                {reply, Response, State#state{state = NewState}};
            {reply, Response, NewState, NextStep} ->
                {reply, Response, State#state{state = NewState}, NextStep};
            {stop, Reason, NewState} ->
                {stop, Reason, State#state{state = NewState}};
            {stop, Reason, Response, NewState} ->
                {stop, Reason, Response, State#state{state = NewState}}
        catch
            _:{noreply, NewState} ->
                {noreply, State#state{state = NewState}};
            _:{noreply, NewState, NextStep} ->
                {noreply, State#state{state = NewState}, NextStep};
            _:{reply, Response, NewState} ->
                {reply, Response, State#state{state = NewState}};
            _:{reply, Response, NewState, NextStep} ->
                {reply, Response, State#state{state = NewState}, NextStep};
            _:{stop, Reason, NewState} ->
                {stop, Reason, State#state{state = NewState}};
            _:{stop, Reason, Response, NewState} ->
                {stop, Reason, Response, State#state{state = NewState}}
        end,
    wpool_utils:task_end(Task),
    ok = notify_queue_manager(worker_ready, State#state.name, Options),
    Reply.

notify_queue_manager(Function, Name, #{queue_manager := QueueManager}) ->
    wpool_queue_manager:Function(QueueManager, Name);
notify_queue_manager(_, _, _) ->
    ok.

create_callback_cache(Mod) ->
    #callback_cache{module = Mod,
                    handle_call = fun Mod:handle_call/3,
                    handle_cast = fun Mod:handle_cast/2,
                    handle_info = fun Mod:handle_info/2}.
