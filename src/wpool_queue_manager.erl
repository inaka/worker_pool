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
%% @hidden
-module(wpool_queue_manager).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

%% api
-export([start_link/2]).
-export([available_worker/2, cast_to_available_worker/2,
         new_worker/2, worker_dead/2, worker_ready/2, worker_busy/2]).
-export([pools/0, stats/1]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

-include("wpool.hrl").

-record(state, {wpool        :: wpool:name(),
                clients      :: queue(),
                workers      :: gb_set(),
                worker_count :: non_neg_integer()
               }).
-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link(wpool:name(), queue_mgr())
                -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name) -> gen_server:start_link({local, Name}, ?MODULE, WPool, []).

-spec available_worker(queue_mgr(), timeout()) -> noproc | timeout | atom().
available_worker(QueueManager, Timeout) ->
  Expires =
    case Timeout of
      infinity -> infinity;
      Timeout -> now_in_microseconds() + Timeout*1000
    end,
  try gen_server:call(QueueManager, {available_worker, Expires}, Timeout) of
    {ok, Worker} -> Worker;
    {error, Error} -> throw(Error)
  catch
    _:{noproc, {gen_server, call, _}} ->
      noproc;
    _:{timeout,{gen_server, call, _}} ->
      timeout
  end.

%% @doc Casts a message to the first available worker.
%%      Since we can wait forever for a wpool:cast to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the cast when it gets the worker
-spec cast_to_available_worker(queue_mgr(), term()) -> ok.
cast_to_available_worker(QueueManager, Cast) ->
    gen_server:cast(QueueManager, {cast_to_available_worker, Cast}).

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
    ets:foldl(fun(#wpool{name=Pool_Name, qmanager=Queue_Mgr}, Pools) ->
                      This_Pool = [{pool, Pool_Name}, {queue_manager, Queue_Mgr}],
                      [This_Pool | Pools]
              end, [], wpool_pool).

%% @doc Returns statistics for this queue.
-spec stats(queue_mgr()) -> proplists:proplist().
stats(QueueManager) ->
    {Available_Workers, Busy_Workers, Pending_Tasks}
        = gen_server:call(QueueManager, worker_counts),
    [
     {pending_tasks,     Pending_Tasks},
     {available_workers, Available_Workers},
     {busy_workers,      Busy_Workers}
    ].

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
-spec init(wpool:name()) -> {ok, state()}.
init(WPool) ->
  put(pending_tasks, 0),
  {ok, #state{wpool=WPool, clients=queue:new(), workers=gb_sets:new(), worker_count=0}}.

-type worker_event() :: new_worker | worker_dead | worker_busy | worker_ready.
-spec handle_cast({worker_event(), atom()}, state()) -> {noreply, state()}.
handle_cast({new_worker, Worker}, #state{worker_count=WC} = State) ->
    handle_cast({worker_ready, Worker}, State#state{worker_count=WC+1});
handle_cast({worker_dead, Worker}, #state{worker_count=WC, workers=Workers} = State) ->
  New_Workers = gb_sets:delete_any(Worker, Workers),
  {noreply, State#state{worker_count=WC-1, workers=New_Workers}};
handle_cast({worker_busy, Worker}, #state{workers=Workers} = State) ->
  {noreply, State#state{workers = gb_sets:delete_any(Worker, Workers)}};
handle_cast({worker_ready, Worker}, #state{workers=Workers, clients=Clients} = State) ->
  case queue:out(Clients) of
    {empty, _Clients} ->
      {noreply, State#state{workers = gb_sets:add(Worker, Workers)}};
    {{value, {cast, Cast}}, New_Clients} ->
       dec_pending_tasks(),
       ok = wpool_process:cast(Worker, Cast),
       {noreply, State#state{clients = New_Clients}};
    {{value, {Client = {ClientPid, _}, Expires}}, New_Clients} ->
      dec_pending_tasks(),
      New_State = State#state{clients = New_Clients},
      case is_process_alive(ClientPid) andalso Expires > now_in_microseconds() of
        true ->
          _ = gen_server:reply(Client, {ok, Worker}),
          {noreply, New_State};
        false ->
          handle_cast({worker_ready, Worker}, New_State)
      end
  end;
handle_cast({cast_to_available_worker, Cast},
            #state{workers=Workers, clients=Clients} = State) ->
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      {noreply, State#state{clients = queue:in({cast, Cast}, Clients)}};
    false ->
      {Worker, New_Workers} = gb_sets:take_smallest(Workers),
      ok = wpool_process:cast(Worker, Cast),
      {noreply, State#state{workers = New_Workers}}
  end.

-type from() :: {pid(), reference()}.
-type call_request() :: {available_worker, infinity|pos_integer()} | worker_counts.

-spec handle_call(call_request(), from(), state())
                 -> {reply, {ok, atom()}, state()} | {noreply, state()}.

handle_call({available_worker, Expires}, Client = {ClientPid, _Ref}, State) ->
  case gb_sets:is_empty(State#state.workers) of
    true ->
      inc_pending_tasks(),
      {noreply, State#state{clients = queue:in({Client, Expires}, State#state.clients)}};
    false ->
      {Worker, Workers} = gb_sets:take_smallest(State#state.workers),
      %NOTE: It could've been a while since this call was made, so we check
      case erlang:is_process_alive(ClientPid) andalso Expires > now_in_microseconds() of
        true ->
          {reply, {ok, Worker}, State#state{workers = Workers}};
        false ->
          {noreply, State}
      end
  end;
handle_call(worker_counts, _From,
            #state{worker_count=All_Workers, workers=Available_Workers} = State) ->
    Available = gb_sets:size(Available_Workers),
    Busy = All_Workers - Available,
    {reply, {Available, Busy, get(pending_tasks)}, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(_Info, State) -> {noreply, State}.

-spec terminate(atom(), state()) -> ok.
terminate(Reason, State) ->
  return_error(Reason, queue:out(State#state.clients)).

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
  lager:error("Cast lost on terminate ~p: ~p", [Reason, Cast]),
  return_error(Reason, queue:out(Q));
return_error(Reason, {{value, {From, _Expires}}, Q}) ->
  _  = gen_server:reply(From, {error, {queue_shutdown, Reason}}),
  return_error(Reason, queue:out(Q)).

now_in_microseconds() -> timer:now_diff(os:timestamp(), {0,0,0}).
