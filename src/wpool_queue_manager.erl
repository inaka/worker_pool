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

-record(state, {wpool   :: wpool:name(),
                clients :: queue(),
                workers :: gb_set()}).
-type state() :: #state{}.

%% api
-export([start_link/2]).
-export([available_worker/2, cast_to_available_worker/2, worker_ready/2, worker_busy/2]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link(wpool:name(), atom()) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name) -> gen_server:start_link({local, Name}, ?MODULE, WPool, []).

-spec available_worker(atom(), timeout()) -> noproc | timeout | atom().
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
-spec cast_to_available_worker(atom(), term()) -> ok.
cast_to_available_worker(QueueManager, Cast) -> gen_server:cast(QueueManager, {cast_to_available_worker, Cast}).

-spec worker_ready(atom(), atom()) -> ok.
worker_ready(QueueManager, Worker) -> gen_server:cast(QueueManager, {worker_ready, Worker}).

%% @doc This function is needed just to handle
%%      the use of other strategies combined with
%%      available_worker
-spec worker_busy(atom(), atom()) -> ok.
worker_busy(QueueManager, Worker) -> gen_server:cast(QueueManager, {worker_busy, Worker}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
-spec init(wpool:name()) -> {ok, state()}.
init(WPool) -> {ok, #state{wpool = WPool, clients = queue:new(), workers = gb_sets:new()}}.

-spec handle_cast({worker_busy|worker_ready, atom()}, state()) -> {noreply, state()}.
handle_cast({worker_busy, Worker}, State) ->
  {noreply, State#state{workers = gb_sets:delete_any(Worker, State#state.workers)}};
handle_cast({worker_ready, Worker}, State) ->
  case queue:out(State#state.clients) of
    {empty, _Clients} ->
      {noreply, State#state{workers = gb_sets:add(Worker, State#state.workers)}};
    {{value, {cast, Cast}}, Clients} ->
       ok = wpool_process:cast(Worker, Cast),
       {noreply, State#state{clients = Clients}};
    {{value, {Client = {ClientPid, _}, Expires}}, Clients} ->
      case erlang:is_process_alive(ClientPid) andalso Expires > now_in_microseconds() of
        true ->
          _ = gen_server:reply(Client, {ok, Worker}),
          {noreply, State#state{clients = Clients}};
        false ->
          handle_cast({worker_ready, Worker}, State#state{clients = Clients})
      end
  end;
handle_cast({cast_to_available_worker, Cast}, State) ->
  case gb_sets:is_empty(State#state.workers) of
    true ->
      {noreply, State#state{clients = queue:in({cast, Cast}, State#state.clients)}};
    false ->
      {Worker, Workers} = gb_sets:take_smallest(State#state.workers),
      ok = wpool_process:cast(Worker, Cast),
      {noreply, State#state{workers = Workers}}
  end.

-type from() :: {pid(), reference()}.
-spec handle_call({available_worker, infinity|pos_integer()}, from(), state()) -> {reply, {ok, atom()}, state()} | {noreply, state()}.
handle_call({available_worker, Expires}, Client = {ClientPid, _Ref}, State) ->
  case gb_sets:is_empty(State#state.workers) of
    true ->
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
  end.

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
return_error(_Reason, {empty, _Q}) -> ok;
return_error(Reason, {{value, {cast, Cast}}, Q}) ->
  lager:error("Cast lost on terminate ~p: ~p", [Reason, Cast]),
  return_error(Reason, Q);
return_error(Reason, {{value, {From, _Expires}}, Q}) ->
  _  = gen_server:reply(From, {error, {queue_shutdown, Reason}}),
  return_error(Reason, Q).

now_in_microseconds() -> timer:now_diff(os:timestamp(), {0,0,0}).