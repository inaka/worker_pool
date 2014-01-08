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
-export([pools/0, stats/1, proc_info/1, proc_info/2]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

-include("wpool.hrl").

-record(state, {wpool        :: wpool:name(),
                clients      :: queue(),
                workers      :: gb_set()
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
    ets:foldl(fun(#wpool{name=Pool_Name, size=Pool_Size, qmanager=Queue_Mgr}, Pools) ->
                      This_Pool = [
                                   {pool,          Pool_Name},
                                   {pool_size,     Pool_Size},
                                   {queue_manager, Queue_Mgr}
                                  ],
                      [This_Pool | Pools]
              end, [], wpool_pool).

%% @doc Returns statistics for this queue.
-spec stats(wpool:name()) -> proplists:proplist().
stats(Pool_Name) ->
    [#wpool{qmanager=Queue_Manager, size=Pool_Size}]
        = ets:lookup(wpool_pool, Pool_Name),
    {Available_Workers, Pending_Tasks}
        = gen_server:call(Queue_Manager, worker_counts),
    Busy_Workers = Pool_Size - Available_Workers,
    [
     {pool_size,         Pool_Size},
     {pending_tasks,     Pending_Tasks},
     {available_workers, Available_Workers},
     {busy_workers,      Busy_Workers}
    ].

%% @doc Return a default set of process_info about workers.
-spec proc_info(wpool:name()) -> proplists:proplist().
proc_info(Pool_Name) ->
    Key_Info = [current_location, status,
                stack_size, total_heap_size, memory,
                reductions, message_queue_len],
    proc_info(Pool_Name, Key_Info).

%% @doc Return the currently executing function in the queue manager.
-spec proc_info(wpool:name(), atom() | [atom()]) -> proplists:proplist().
proc_info(Pool_Name, Info_Type) ->
    [#wpool{qmanager=Queue_Manager}] = ets:lookup(wpool_pool, Pool_Name),
    Mgr_Info = erlang:process_info(whereis(Queue_Manager), Info_Type),
    Workers = wpool_pool:worker_names(Pool_Name),
    Workers_Info = [{Worker, {Worker_Pid, erlang:process_info(Worker_Pid, Info_Type)}}
                    || Worker <- Workers,
                       begin
                           Worker_Pid = whereis(Worker),
                           is_process_alive(Worker_Pid)
                       end],
    [{queue_manager, Mgr_Info}, {workers, Workers_Info}].

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
-spec init(wpool:name()) -> {ok, state()}.
init(WPool) ->
  put(pending_tasks, 0),
  {ok, #state{wpool=WPool, clients=queue:new(), workers=gb_sets:new()}}.

-type worker_event() :: new_worker | worker_dead | worker_busy | worker_ready.
-spec handle_cast({worker_event(), atom()}, state()) -> {noreply, state()}.
handle_cast({new_worker, Worker}, State) ->
    handle_cast({worker_ready, Worker}, State);
handle_cast({worker_dead, Worker}, #state{workers=Workers} = State) ->
  New_Workers = gb_sets:delete_any(Worker, Workers),
  {noreply, State#state{workers=New_Workers}};
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

handle_call({available_worker, Expires}, Client = {ClientPid, _Ref},
            #state{workers=Workers, clients=Clients} = State) ->
  case gb_sets:is_empty(Workers) of
    true ->
      inc_pending_tasks(),
      {noreply, State#state{clients = queue:in({Client, Expires}, Clients)}};
    false ->
      {Worker, New_Workers} = gb_sets:take_smallest(Workers),
      %NOTE: It could've been a while since this call was made, so we check
      case erlang:is_process_alive(ClientPid) andalso Expires > now_in_microseconds() of
        true  -> {reply, {ok, Worker}, State#state{workers = New_Workers}};
        false -> {noreply, State}
      end
  end;
handle_call(worker_counts, _From,
            #state{workers=Available_Workers} = State) ->
    Available = gb_sets:size(Available_Workers),
    {reply, {Available, get(pending_tasks)}, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(_Info, State) -> {noreply, State}.

-spec terminate(atom(), state()) -> ok.
terminate(Reason, #state{clients=Clients} = _State) ->
  return_error(Reason, queue:out(Clients)).

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
