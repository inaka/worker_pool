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
-module(wpool_queue_manager).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

%% api
-export([ start_link/2
        ]).
-export([ call_available_worker/3
        , cast_to_available_worker/2
        , send_event_to_available_worker/2
        , sync_send_event_to_available_worker/3
        , send_all_event_to_available_worker/2
        , sync_send_all_event_to_available_worker/3
        , new_worker/2
        , worker_dead/2
        , worker_ready/2
        , worker_busy/2
        ]).
-export([ pools/0
        , stats/1
        , proc_info/1
        , proc_info/2
        , trace/1
        , trace/3
        ]).

%% gen_server callbacks
-export([ init/1
        , terminate/2
        , code_change/3
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        ]).

-include("wpool.hrl").

-record(state, { wpool                 :: wpool:name()
               , clients               :: queue:queue({cast|{pid(), _}, term()})
               , workers               :: gb_sets:set(atom())
               , born = os:timestamp() :: erlang:timestamp()
               }).
-type state() :: #state{}.

-type from() :: {pid(), reference()}.

-type queue_mgr() :: atom().
-export_type([queue_mgr/0]).

%%%===================================================================
%%% API
%%%===================================================================
%% @private
-spec start_link(wpool:name(), queue_mgr()) ->
        {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name) ->
  gen_server:start_link({local, Name}, ?MODULE, WPool, []).

%% @doc returns the first available worker in the pool
-spec call_available_worker(queue_mgr(), any(), timeout()) ->
        noproc | timeout | atom().
call_available_worker(QueueManager, Call, Timeout) ->
  Expires = expires(Timeout),
  try
    gen_server:call(QueueManager, {available_worker, Call, Expires}, Timeout)
  catch
    _:{noproc, {gen_server, call, _}} ->
      noproc;
    _:{timeout, {gen_server, call, _}} ->
      timeout
  end.

%% @doc Casts a message to the first available worker.
%%      Since we can wait forever for a wpool:cast to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the cast when it gets the worker
-spec cast_to_available_worker(queue_mgr(), term()) -> ok.
cast_to_available_worker(QueueManager, Cast) ->
  gen_server:cast(QueueManager, {cast_to_available_worker, Cast}).

%% @doc returns the first available worker in the pool
-spec sync_send_event_to_available_worker(queue_mgr(), any(), timeout()) ->
        noproc | timeout | atom().
sync_send_event_to_available_worker(QueueManager, Event, Timeout) ->
  Expires = expires(Timeout),
  try
    gen_server:call(
      QueueManager, {sync_event_available_worker, Event, Expires}, Timeout)
  catch
    _:{noproc, {gen_server, call, _}} ->
      noproc;
    _:{timeout, {gen_server, call, _}} ->
      timeout
  end.

%% @doc returns the first available worker in the pool
-spec sync_send_all_event_to_available_worker(queue_mgr(), any(), timeout()) ->
        noproc | timeout | atom().
sync_send_all_event_to_available_worker(QueueManager, Event, Timeout) ->
  Expires =
    case Timeout of
      infinity -> infinity;
      Timeout -> now_in_microseconds() + Timeout * 1000
    end,
  try
    gen_server:call(
      QueueManager, {sync_all_event_available_worker, Event, Expires}, Timeout)
  catch
    _:{noproc, {gen_server, call, _}} ->
      noproc;
    _:{timeout, {gen_server, call, _}} ->
      timeout
  end.

%% @doc Send an event to the first available worker.
%%      Since we can wait forever for a wpool:send_event to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the event when it gets the worker
-spec send_event_to_available_worker(queue_mgr(), term()) -> ok.
send_event_to_available_worker(QueueManager, Event) ->
  gen_server:cast(QueueManager, {send_event_to_available_worker, Event}).

%% @doc Send an event to the first available worker.
%%      Since we can wait forever for a wpool:send_event to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the event when it gets the worker
-spec send_all_event_to_available_worker(queue_mgr(), term()) -> ok.
send_all_event_to_available_worker(QueueManager, Event) ->
  gen_server:cast(QueueManager, {send_all_event_to_available_worker, Event}).

%% @doc Mark a brand new worker as available
-spec new_worker(queue_mgr(), atom()) -> ok.
new_worker(QueueManager, Worker) ->
  gen_server:cast(QueueManager, {new_worker, Worker}).

%% @doc Mark a worker as available
-spec worker_ready(queue_mgr(), atom()) -> ok.
worker_ready(QueueManager, Worker) ->
  gen_server:cast(QueueManager, {worker_ready, Worker}).

%% @doc Mark a worker as no longer available
-spec worker_busy(queue_mgr(), atom()) -> ok.
worker_busy(QueueManager, Worker) ->
  gen_server:cast(QueueManager, {worker_busy, Worker}).

%% @doc Decrement the total number of workers
-spec worker_dead(queue_mgr(), atom()) -> ok.
worker_dead(QueueManager, Worker) ->
  gen_server:cast(QueueManager, {worker_dead, Worker}).

%% @doc Return the list of currently existing worker pools.
-type pool_prop()  :: {pool, wpool:name()}.
-type qm_prop()    :: {queue_manager, queue_mgr()}.
-type pool_props() :: [pool_prop() | qm_prop()].      % Not quite strict enough.
-spec pools() -> [pool_props()].
pools() ->
  ets:foldl(
    fun(#wpool{ name = PoolName
              , size = PoolSize
              , qmanager = QueueMgr
              , born = Born
              }, Pools) ->
      ThisPool = [ {pool,          PoolName}
                 , {pool_age,      age_in_seconds(Born)}
                 , {pool_size,     PoolSize}
                 , {queue_manager, QueueMgr}
                 ],
      [ThisPool | Pools]
    end, [], wpool_pool).

%% @doc Returns statistics for this queue.
-spec stats(wpool:name()) ->
        proplists:proplist() | {error, {invalid_pool, wpool:name()}}.
stats(PoolName) ->
  case ets:lookup(wpool_pool, PoolName) of
    [] -> {error, {invalid_pool, PoolName}};
    [#wpool{qmanager = QueueManager, size = PoolSize, born = Born}] ->
        {AvailableWorkers, PendingTasks} =
          gen_server:call(QueueManager, worker_counts),
        BusyWorkers = PoolSize - AvailableWorkers,
        [ {pool_age_in_secs,  age_in_seconds(Born)}
        , {pool_size,         PoolSize}
        , {pending_tasks,     PendingTasks}
        , {available_workers, AvailableWorkers}
        , {busy_workers,      BusyWorkers}
        ]
  end.

%% @doc Return a default set of process_info about workers.
-spec proc_info(wpool:name()) -> proplists:proplist().
proc_info(PoolName) ->
  KeyInfo =
    [ current_location
    , status
    , stack_size
    , total_heap_size
    , memory
    , reductions
    , message_queue_len
    ],
  proc_info(PoolName, KeyInfo).

%% @doc Return the currently executing function in the queue manager.
-spec proc_info(wpool:name(), atom() | [atom()]) -> proplists:proplist().
proc_info(PoolName, InfoType) ->
  case ets:lookup(wpool_pool, PoolName) of
    [] -> {error, {invalid_pool, PoolName}};
    [#wpool{qmanager = QueueManager, born = MgrBorn}] ->
      AgeInSecs = age_in_seconds(MgrBorn),
      QMPid = whereis(QueueManager),
      MgrInfo =
        [ {age_in_seconds, AgeInSecs}
        | erlang:process_info(QMPid, InfoType)
        ],
      Workers = wpool_pool:worker_names(PoolName),
      WorkersInfo =
        [ {Worker, worker_info(WorkerPid, InfoType)}
        || Worker <- Workers
         , begin
             WorkerPid = whereis(Worker),
             is_process_alive(WorkerPid)
           end
        ],
      [{queue_manager, MgrInfo}, {workers, WorkersInfo}]
  end.

worker_info(WorkerPid, InfoType) ->
  SecsOld = wpool_process:age(WorkerPid) div 1000000,
  {WorkerPid,
    [{age_in_seconds, SecsOld} | erlang:process_info(WorkerPid, InfoType)]}.

-define(DEFAULT_TRACE_TIMEOUT, 5000).
-define(TRACE_KEY, wpool_trace).

%% @doc Default tracing for 5 seconds to track worker pool execution times
%%      to error.log.
-spec trace(wpool:name()) -> ok.
trace(PoolName) ->
  trace(PoolName, true, ?DEFAULT_TRACE_TIMEOUT).

%% @doc Turn pool tracing on and off.
-spec trace(wpool:name(), boolean(), pos_integer()) ->
  ok | {error, {invalid_pool, wpool:name()}}.
trace(PoolName, true, Timeout) ->
  case ets:lookup(wpool_pool, PoolName) of
    [] -> {error, {invalid_pool, PoolName}};
    [#wpool{}] ->
      error_logger:info_msg(
        "[~p] Tracing turned on for worker_pool ~p",
        [?TRACE_KEY, PoolName]),
      {TracerPid, _Ref} = trace_timer(PoolName),
      trace(PoolName, true, TracerPid, Timeout)
  end;
trace(PoolName, false, _Timeout) ->
  case ets:lookup(wpool_pool, PoolName) of
    [] -> {error, {invalid_pool, PoolName}};
    [#wpool{}] ->
      trace(PoolName, false, no_pid, 0)
  end.

-spec trace(wpool:name(), boolean(), pid() | no_pid, non_neg_integer()) -> ok.
trace(PoolName, TraceOn, TracerPid, Timeout) ->
  Workers = wpool_pool:worker_names(PoolName),
  TraceOptions = [timestamp, 'receive', send],
  _ =
    [ case TraceOn of
        true  ->
          erlang:trace(WorkerPid, true,  [{tracer, TracerPid} | TraceOptions]);
        false ->
          erlang:trace(WorkerPid, false, TraceOptions)
      end || Worker <- Workers, is_process_alive(WorkerPid = whereis(Worker))],
  trace_off(PoolName, TraceOn, TracerPid, Timeout).

trace_off(PoolName, false, _TracerPid, _Timeout) ->
  error_logger:info_msg(
    "[~p] Tracing turned off for worker_pool ~p", [?TRACE_KEY, PoolName]),
  ok;
trace_off(PoolName, true,   TracerPid,  Timeout) ->
  _ = timer:apply_after(Timeout, ?MODULE, trace, [PoolName, false, Timeout]),
  _ = erlang:send_after(Timeout, TracerPid, quit),
  error_logger:info_msg(
    "[~p] Tracer pid ~p scheduled to end in ~p msec for worker_pool ~p",
    [?TRACE_KEY, TracerPid, Timeout, PoolName]),
  ok.

%% @doc Collect trace timing results to report succinct run times.
-spec trace_timer(wpool:name()) -> from().
trace_timer(PoolName) ->
  {Pid, Reference} =
    spawn_monitor(fun() -> report_trace_times(PoolName) end),
  register(wpool_trace_timer, Pid),
  error_logger:info_msg(
    "[~p] Tracer pid ~p started for worker_pool ~p",
    [?TRACE_KEY, Pid, PoolName]),
  {Pid, Reference}.

-spec report_trace_times(wpool:name()) -> ok.
report_trace_times(PoolName) ->
  receive
    quit -> summarize_pending_times(PoolName);
    {trace_ts, Worker, 'receive', {'$gen_call', From, Request}, TimeStarted} ->
      Props = {start, TimeStarted, request, Request, worker, Worker},
      undefined = put({?TRACE_KEY, From}, Props),
      report_trace_times(PoolName);
    {trace_ts, Worker, send, {Ref, Result}, FromPid, TimeFinished} ->
      case erase({?TRACE_KEY, {FromPid, Ref}}) of
        undefined -> ok;
        {start, TimeStarted, request, Request, worker, Worker} ->
          Elapsed = timer:now_diff(TimeFinished, TimeStarted),
          error_logger:info_msg(
            "[~p] ~p usec: ~p  request: ~p  reply: ~p",
            [?TRACE_KEY, Worker, Elapsed, Request, Result])
      end,
      report_trace_times(PoolName);
    _SysOrOtherMsg ->
      report_trace_times(PoolName)
  end.

summarize_pending_times(PoolName) ->
  Now = os:timestamp(),
  FmtMsg = "[~p] Unfinished task ~p usec: ~p  request: ~p",
  _ =
    [ error_logger:info_msg(FmtMsg, [?TRACE_KEY, Worker, Elapsed, Request])
    || { {?TRACE_KEY, _From}
       , {start, TimeStarted, request, Request, worker, Worker}
       } <- get()
     , (Elapsed = timer:now_diff(Now, TimeStarted)) > -1
    ],
  error_logger:info_msg(
    "[~p] Tracer pid ~p ended for worker_pool ~p",
    [?TRACE_KEY, self(), PoolName]),
  ok.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%% @private
-spec init(wpool:name()) -> {ok, state()}.
init(WPool) ->
  put(pending_tasks, 0),
  {ok, #state{wpool = WPool, clients = queue:new(), workers = gb_sets:new()}}.

-type worker_event() :: new_worker | worker_dead | worker_busy | worker_ready.
%% @private
-spec handle_cast({worker_event(), atom()}, state()) -> {noreply, state()}.
handle_cast({new_worker, Worker}, State) ->
  handle_cast({worker_ready, Worker}, State);
handle_cast({worker_dead, Worker}, #state{workers = Workers} = State) ->
  NewWorkers = gb_sets:delete_any(Worker, Workers),
  {noreply, State#state{workers = NewWorkers}};
handle_cast({worker_busy, Worker}, #state{workers = Workers} = State) ->
  {noreply, State#state{workers = gb_sets:delete_any(Worker, Workers)}};
handle_cast({worker_ready, Worker}, State) ->
  #state{workers = Workers, clients = Clients} = State,
  case queue:out(Clients) of
    {empty, _Clients} ->
      {noreply, State#state{workers = gb_sets:add(Worker, Workers)}};
    {{value, {cast, Cast}}, NewClients} ->
      dec_pending_tasks(),
      ok = wpool_process:cast(Worker, Cast),
      {noreply, State#state{clients = NewClients}};
    {{value, {Client = {ClientPid, _}, Call, Expires}}, NewClients} ->
      dec_pending_tasks(),
      NewState = State#state{clients = NewClients},
      case is_process_alive(ClientPid) andalso
           Expires > now_in_microseconds() of
        true ->
          ok = wpool_process:cast_call(Worker, Client, Call),
          {noreply, NewState};
        false ->
          handle_cast({worker_ready, Worker}, NewState)
      end;
    {{value, {send_event, Event}}, NewClients} ->
      dec_pending_tasks(),
      ok = wpool_fsm_process:send_event(Worker, Event),
      {noreply, State#state{clients = NewClients}};
    { { value
      , {sync_send_event, Client = {ClientPid, _}, Call, Expires}
      }
    , NewClients
    } ->
      dec_pending_tasks(),
      NewState = State#state{clients = NewClients},
      case is_process_alive(ClientPid) andalso
        Expires > now_in_microseconds() of
        true ->
          ok = wpool_fsm_process:cast_call(Worker, Client, Call),
          {noreply, NewState};
        false ->
          handle_cast({worker_ready, Worker}, NewState)
      end
  end;
handle_cast({cast_to_available_worker, Cast}, State) ->
  #state{workers = Workers, clients = Clients} = State,
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      {noreply, State#state{clients = queue:in({cast, Cast}, Clients)}};
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      ok = wpool_process:cast(Worker, Cast),
      {noreply, State#state{workers = NewWorkers}}
  end;
handle_cast({send_event_to_available_worker, Event}, State) ->
  #state{workers = Workers, clients = Clients} = State,
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      {noreply, State#state{clients = queue:in({send_event, Event}, Clients)}};
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      ok = wpool_fsm_process:send_event(Worker, Event),
      {noreply, State#state{workers = NewWorkers}}
  end;
handle_cast({send_all_event_to_available_worker, Event}, State) ->
  #state{workers = Workers, clients = Clients} = State,
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      {noreply, State#state{clients = queue:in({send_event, Event}, Clients)}};
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      ok = wpool_fsm_process:send_all_state_event(Worker, Event),
      {noreply, State#state{workers = NewWorkers}}
  end.

-type call_request() ::
        {available_worker, infinity|pos_integer()} | worker_counts.
%% @private
-spec handle_call(call_request(), from(), state()) ->
        {reply, {ok, atom()}, state()} | {noreply, state()}.
handle_call(
  {available_worker, Call, Expires}, Client = {ClientPid, _Ref}, State) ->
  #state{workers = Workers, clients = Clients} = State,
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      { noreply
      , State#state{clients = queue:in({Client, Call, Expires}, Clients)}
      };
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      %NOTE: It could've been a while since this call was made, so we check
      case erlang:is_process_alive(ClientPid) andalso
           Expires > now_in_microseconds() of
        true  ->
          ok = wpool_process:cast_call(Worker, Client, Call),
          {noreply, State#state{workers = NewWorkers}};
        false ->
          {noreply, State}
      end
  end;
handle_call(
  {sync_event_available_worker, Event, Expires}, Client = {ClientPid, _Ref},
  State) ->
  #state{workers = Workers, clients = Clients} = State,
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      { noreply
        , State#state{clients =
            queue:in({sync_send_event, Client, Event, Expires}, Clients)}
      };
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      %NOTE: It could've been a while since this call was made, so we check
      case erlang:is_process_alive(ClientPid) andalso
        Expires > now_in_microseconds() of
        true  ->
          Reply = wpool_fsm_process:sync_send_event(Worker, Event),
          gen_server:reply(Client, Reply),
          {noreply, State#state{workers = NewWorkers}};
        false ->
          {noreply, State}
      end
  end;
handle_call(
  {sync_all_event_available_worker, Event, Expires}, Client = {ClientPid, _Ref},
  State) ->
  #state{workers = Workers, clients = Clients} = State,
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      { noreply
      , State#state{clients = queue:in({Client, Event, Expires}, Clients)}
      };
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      %NOTE: It could've been a while since this call was made, so we check
      case erlang:is_process_alive(ClientPid) andalso
        Expires > now_in_microseconds() of
        true  ->
          Reply = wpool_fsm_process:sync_send_all_state_event(Worker, Event),
          gen_server:reply(Client, Reply),
          {noreply, State#state{workers = NewWorkers}};
        false ->
          {noreply, State}
      end
  end;
handle_call(worker_counts, _From, State) ->
  #state{workers = AvailableWorkers} = State,
  Available = gb_sets:size(AvailableWorkers),
  {reply, {Available, get(pending_tasks)}, State}.

%% @private
-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(_Info, State) -> {noreply, State}.

%% @private
-spec terminate(atom(), state()) -> ok.
terminate(Reason, #state{clients = Clients} = _State) ->
  return_error(Reason, queue:out(Clients)).

%% @private
-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% private
%%%===================================================================
inc_pending_tasks() -> inc(pending_tasks).
dec_pending_tasks() -> dec(pending_tasks).

inc(Key) -> put(Key, get(Key) + 1).
dec(Key) -> put(Key, get(Key) - 1).

return_error(_Reason, {empty, _Q}) -> ok;
return_error(Reason, {{value, {cast, Cast}}, Q}) ->
  error_logger:error_msg("Cast lost on terminate ~p: ~p", [Reason, Cast]),
  return_error(Reason, queue:out(Q));
return_error(Reason, {{value, {From, _Expires}}, Q}) ->
  _  = gen_server:reply(From, {error, {queue_shutdown, Reason}}),
  return_error(Reason, queue:out(Q)).

now_in_microseconds() -> timer:now_diff(os:timestamp(), {0, 0, 0}).

age_in_seconds(Born) -> timer:now_diff(os:timestamp(), Born) div 1000000.

expires(Timeout) ->
  case Timeout of
    infinity -> infinity;
    Timeout -> now_in_microseconds() + Timeout * 1000
  end.
