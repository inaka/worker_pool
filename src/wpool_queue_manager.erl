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
                workers :: queue()}).
-type state() :: #state{}.

%% api
-export([start_link/2]).
-export([available_worker/2]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link(wpool:name(), atom()) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(WPool, Name) -> gen_server:start_link({local, Name}, ?MODULE, WPool, []).

-spec available_worker(atom(), timeout()) -> noproc | timeout | atom().
available_worker(QueueManager, Timeout) ->
  try gen_server:call(QueueManager, available_worker, Timeout) of
    {ok, Worker} -> Worker;
    {error, Error} -> throw(Error)
  catch
    _:{noproc, {gen_server, call, _}} ->
      noproc;
    _:{timeout,{gen_server, call, _}} ->
      timeout
  end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
-spec init(wpool:name()) -> {ok, state()}.
init(WPool) -> {ok, #state{wpool = WPool, clients = queue:new(), workers = queue:new()}}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Cast, State) -> {noreply, State}.

-type from() :: {pid(), reference()}.
-spec handle_call(available_worker, from(), state()) -> {reply, {ok, atom()}, state()} | {noreply, state()}.
handle_call(available_worker, From, State) ->
  case queue:out(State#state.workers) of
    {empty, _Workers} ->
      {noreply, State#state{clients = queue:in(From, State#state.clients)}};
    {{value, Worker}, Workers} ->
      {reply, {ok, Worker}, State#state{workers = Workers}}
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
return_error(Reason, {{value, From}, Q}) ->
  _  = gen_server:reply(From, {error, {queue_shutdown, Reason}}),
  return_error(Reason, Q).