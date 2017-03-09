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
-export([ stats/1
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

-record(state, { wpool             :: wpool:name()
               , clients           :: queue:queue({cast|{pid(), _}, term()})
               , workers           :: gb_sets:set(atom())
               , monitors          :: gb_trees:tree(atom(), monitored_from())
               }).
-type state() :: #state{}.

-type from() :: {pid(), reference()}.
-type monitored_from() :: {reference(), from()}.

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
  of
    {'EXIT', _, noproc} ->
      noproc;
    {'EXIT', Worker, Exit} ->
      exit({Exit, {gen_server, call, [Worker, Call, Timeout]}});
    Result ->
      Result
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
  of
    {'EXIT', _, noproc} ->
      noproc;
    {'EXIT', Worker, Exit} ->
      exit({Exit, {gen_fsm, sync_send_event, [Worker, Event, Timeout]}});
    Result ->
      Result
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
  Expires = expires(Timeout),
  try
    gen_server:call(
      QueueManager, {sync_all_event_available_worker, Event, Expires}, Timeout)
  of
    {'EXIT', _, noproc} ->
      noproc;
    {'EXIT', Worker, Exit} ->
      exit({Exit,
            {gen_fsm, sync_send_all_state_event, [Worker, Event, Timeout]}});
    Result ->
      Result
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

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%% @private
-spec init(wpool:name()) -> {ok, state()}.
init(WPool) ->
  put(pending_tasks, 0),
  {ok, #state{wpool = WPool, clients = queue:new(),
              workers = gb_sets:new(), monitors = gb_trees:empty()}}.

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
handle_cast({worker_ready, Worker}, State0) ->
  #state{workers = Workers, clients = Clients, monitors = Mons} = State0,
  State = case gb_trees:is_defined(Worker, Mons) of
    true ->
      {Ref, _Client} = gb_trees:get(Worker, Mons),
      demonitor(Ref, [flush]),
      State0#state{monitors = gb_trees:delete(Worker, Mons)};
    false ->
      State0
  end,
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
          MonitorState = monitor_worker(Worker, Client, NewState),
          ok = wpool_process:cast_call(Worker, Client, Call),
          {noreply, MonitorState};
        false ->
          handle_cast({worker_ready, Worker}, NewState)
      end;
    {{value, {send_event, Event}}, NewClients} ->
      dec_pending_tasks(),
      ok = wpool_fsm_process:send_event(Worker, Event),
      {noreply, State#state{clients = NewClients}};
    {{value, {send_all_event, Event}}, NewClients} ->
      dec_pending_tasks(),
      ok = wpool_fsm_process:send_all_state_event(Worker, Event),
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
          MonitorState = monitor_worker(Worker, Client, NewState),
          ok = wpool_fsm_process:cast_call(Worker, Client, Call),
          {noreply, MonitorState};
        false ->
          handle_cast({worker_ready, Worker}, NewState)
      end;
    { { value
      , {sync_send_all_event, Client = {ClientPid, _}, Call, Expires}
      }
    , NewClients
    } ->
      dec_pending_tasks(),
      NewState = State#state{clients = NewClients},
      case is_process_alive(ClientPid) andalso
        Expires > now_in_microseconds() of
        true ->
          MonitorState = monitor_worker(Worker, Client, NewState),
          ok = wpool_fsm_process:cast_call_all(Worker, Client, Call),
          {noreply, MonitorState};
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
      {noreply, State#state{clients =
                            queue:in({send_event, Event}, Clients)}};
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
      {noreply, State#state{clients =
                            queue:in({send_all_event, Event}, Clients)}};
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
          NewState = monitor_worker(Worker, Client,
                                    State#state{workers = NewWorkers}),
          ok = wpool_process:cast_call(Worker, Client, Call),
          {noreply, NewState};
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
          NewState = monitor_worker(Worker, Client,
                                    State#state{workers = NewWorkers}),
          ok = wpool_fsm_process:cast_call(Worker, Client, Event),
          {noreply, NewState};
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
      , State#state{clients =
          queue:in({sync_send_all_event, Client, Event, Expires}, Clients)}
      };
    false ->
      {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
      %NOTE: It could've been a while since this call was made, so we check
      case erlang:is_process_alive(ClientPid) andalso
        Expires > now_in_microseconds() of
        true  ->
          NewState = monitor_worker(Worker, Client,
                                    State#state{workers = NewWorkers}),
          ok = wpool_fsm_process:cast_call_all(Worker, Client, Event),
          {noreply, NewState};
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
handle_info({'DOWN', _, _, Worker, Exit}, State = #state{monitors = Mons}) ->
  case gb_trees:is_defined(Worker, Mons) of
    true ->
      {_Ref, Client} = gb_trees:get(Worker, Mons),
      gen_server:reply(Client, {'EXIT', Worker, Exit}),
      {noreply, State#state{monitors = gb_trees:delete(Worker, Mons)}};
    false ->
      {noreply, State}
  end;
handle_info(_Info, State) -> {noreply, State}.

%% @private
-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) -> ok.

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

now_in_microseconds() -> timer:now_diff(os:timestamp(), {0, 0, 0}).

age_in_seconds(Born) -> timer:now_diff(os:timestamp(), Born) div 1000000.

expires(Timeout) ->
  case Timeout of
    infinity -> infinity;
    Timeout -> now_in_microseconds() + Timeout * 1000
  end.

monitor_worker(Worker, Client, State = #state{monitors = Mons}) ->
  Ref = monitor(process, Worker),
  State#state{monitors = gb_trees:enter(Worker, {Ref, Client}, Mons)}.
