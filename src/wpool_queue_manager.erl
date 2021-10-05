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
-export([start_link/2, start_link/3]).
-export([call_available_worker/3, cast_to_available_worker/2, new_worker/2, worker_dead/2,
         worker_ready/2, worker_busy/2, pending_task_count/1]).
%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-record(state,
        {wpool :: wpool:name(),
         clients :: queue:queue({cast | {pid(), _}, term()}),
         workers :: gb_sets:set(atom()),
         monitors :: gb_trees:tree(atom(), monitored_from()),
         queue_type :: queue_type()}).

-type state() :: #state{}.
-type from() :: {pid(), reference()}.
-type monitored_from() :: {reference(), from()}.
-type options() :: [{option(), term()}].
-type option() :: queue_type.
-type args() :: [{arg(), term()}].
-type arg() :: option() | pool.
-type queue_mgr() :: atom().
-type queue_type() :: fifo | lifo.

-export_type([queue_mgr/0, queue_type/0]).

%%%===================================================================
%%% API
%%%===================================================================
%% @equiv start_link(WPool, Name, [])
-spec start_link(wpool:name(), queue_mgr()) ->
                    {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name) ->
    start_link(WPool, Name, []).

%% @private
-spec start_link(wpool:name(), queue_mgr(), options()) ->
                    {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name, Options) ->
    gen_server:start_link({local, Name}, ?MODULE, [{pool, WPool} | Options], []).

%% @doc returns the first available worker in the pool
-spec call_available_worker(queue_mgr(), any(), timeout()) -> noproc | timeout | atom().
call_available_worker(QueueManager, Call, Timeout) ->
    Expires = expires(Timeout),
    try gen_server:call(QueueManager, {available_worker, Call, Expires}, Timeout) of
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

%% @doc Retrieves the number of pending tasks (used for stats)
%% @see wpool_pool:stats/1
-spec pending_task_count(queue_mgr()) -> non_neg_integer().
pending_task_count(QueueManager) ->
    gen_server:call(QueueManager, pending_task_count).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%% @private
-spec init(args()) -> {ok, state()}.
init(Args) ->
    WPool = proplists:get_value(pool, Args),
    QueueType = proplists:get_value(queue_type, Args),
    put(pending_tasks, 0),
    {ok,
     #state{wpool = WPool,
            clients = queue:new(),
            workers = gb_sets:new(),
            monitors = gb_trees:empty(),
            queue_type = QueueType}}.

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
    #state{workers = Workers,
           clients = Clients,
           monitors = Mons,
           queue_type = QueueType} =
        State0,
    State =
        case gb_trees:is_defined(Worker, Mons) of
            true ->
                {Ref, _Client} = gb_trees:get(Worker, Mons),
                demonitor(Ref, [flush]),
                State0#state{monitors = gb_trees:delete(Worker, Mons)};
            false ->
                State0
        end,
    case queue_out(Clients, QueueType) of
        {empty, _Clients} ->
            {noreply, State#state{workers = gb_sets:add(Worker, Workers)}};
        {{value, {cast, Cast}}, NewClients} ->
            dec_pending_tasks(),
            ok = wpool_process:cast(Worker, Cast),
            {noreply, State#state{clients = NewClients}};
        {{value, {Client = {ClientPid, _}, Call, Expires}}, NewClients} ->
            dec_pending_tasks(),
            NewState = State#state{clients = NewClients},
            case is_process_alive(ClientPid) andalso Expires > now_in_microseconds() of
                true ->
                    MonitorState = monitor_worker(Worker, Client, NewState),
                    ok = wpool_process:cast_call(Worker, Client, Call),
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
    end.

-type call_request() :: {available_worker, infinity | pos_integer()} | pending_task_count.

%% @private
-spec handle_call(call_request(), from(), state()) ->
                     {reply, {ok, atom()}, state()} | {noreply, state()}.
handle_call({available_worker, Call, Expires}, Client = {ClientPid, _Ref}, State) ->
    #state{workers = Workers, clients = Clients} = State,
    case gb_sets:is_empty(Workers) of
        true ->
            inc_pending_tasks(),
            {noreply, State#state{clients = queue:in({Client, Call, Expires}, Clients)}};
        false ->
            {Worker, NewWorkers} = gb_sets:take_smallest(Workers),
            %NOTE: It could've been a while since this call was made, so we check
            case erlang:is_process_alive(ClientPid) andalso Expires > now_in_microseconds() of
                true ->
                    NewState = monitor_worker(Worker, Client, State#state{workers = NewWorkers}),
                    ok = wpool_process:cast_call(Worker, Client, Call),
                    {noreply, NewState};
                false ->
                    {noreply, State}
            end
    end;
handle_call(pending_task_count, _From, State) ->
    {reply, get(pending_tasks), State}.

%% @private
-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info({'DOWN', Ref, Type, {Worker, _Node}, Exit}, State) ->
    handle_info({'DOWN', Ref, Type, Worker, Exit}, State);
handle_info({'DOWN', _, _, Worker, Exit}, State = #state{monitors = Mons}) ->
    case gb_trees:is_defined(Worker, Mons) of
        true ->
            {_Ref, Client} = gb_trees:get(Worker, Mons),
            gen_server:reply(Client, {'EXIT', Worker, Exit}),
            {noreply, State#state{monitors = gb_trees:delete(Worker, Mons)}};
        false ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) ->
    ok.

%% @private
-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% private
%%%===================================================================
inc_pending_tasks() ->
    inc(pending_tasks).

dec_pending_tasks() ->
    dec(pending_tasks).

inc(Key) ->
    put(Key, get(Key) + 1).

dec(Key) ->
    put(Key, get(Key) - 1).

now_in_microseconds() ->
    timer:now_diff(
        os:timestamp(), {0, 0, 0}).

expires(Timeout) ->
    case Timeout of
        infinity ->
            infinity;
        Timeout ->
            now_in_microseconds() + Timeout * 1000
    end.

monitor_worker(Worker, Client, State = #state{monitors = Mons}) ->
    Ref = monitor(process, Worker),
    State#state{monitors = gb_trees:enter(Worker, {Ref, Client}, Mons)}.

queue_out(Clients, fifo) ->
    queue:out(Clients);
queue_out(Clients, lifo) ->
    queue:out_r(Clients).
