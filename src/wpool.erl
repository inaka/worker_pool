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

%% @doc Worker pool main interface, use functions in this module to manage pools of workers
-module(wpool).
-author('elbrujohalcon@inaka.net').

-define(DEFAULTS, [{timeout_warning, infinity}, {workers, 100}, {worker, {wpool_worker, undefined}}]).

-type name() :: atom().
-type option() :: {timeout_warning, infinity|pos_integer()} | {workers, pos_integer()} | {worker, {Module::atom(), InitArg::term()}}.
-type strategy() :: best_worker | random_worker | next_worker.
-type worker_stats() :: [{messsage_queue_len, non_neg_integer()} | {memory, pos_integer()}].
-type stats() :: [{workers, pos_integer()} | {total_message_queue_len, non_neg_integer()} | {worker_stats, [{pos_integer(), worker_stats()}]}].
-export_type([name/0, option/0, strategy/0, worker_stats/0, stats/0]).

-export([start/0, start/2, stop/0, stop/1]).
-export([start_link/1, start_link/2]).
-export([call/2, cast/2, call/3, cast/3, call/4]).
-export([stats/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ADMIN API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the application
-spec start() -> ok | {error, {already_started, ?MODULE}}.
start() -> application:start(worker_pool).

%% @doc Stops the application
-spec stop() -> ok.
stop() -> application:stop(worker_pool).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BEHAVIOUR CALLBACKS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @private
-spec start(any(), any()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) -> {ok, self()}.

%% @private
-spec stop(any()) -> ok.
stop(_State) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PUBLIC API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @equiv start_link(Name, [])
-spec start_link(name()) -> {ok, pid()}.
start_link(Name) -> start_link(Name, []).

%% @doc Starts (and links) a pool of N wpool_processes
%%		The result pid belongs to a supervisor (in case you want to add it to a supervisor tree)
-spec start_link(name(), [option()]) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(Name, Options) -> wpool_sup:start_link(Name, Options ++ ?DEFAULTS).

%% @equiv call(Sup, Call, random_worker)
-spec call(name(), term()) -> term().
call(Sup, Call) -> call(Sup, Call, random_worker).

%% @equiv call(Sup, Call, Strategy, 5000)
-spec call(name(), term(), strategy()) -> term().
call(Sup, Call, Strategy) -> wpool_process:call(wpool_sup:Strategy(Sup), Call).

%% @doc Picks a server and issues the call to it
-spec call(name(), term(), strategy(), timeout()) -> term().
call(Sup, Call, Strategy, Timeout) -> wpool_process:call(wpool_sup:Strategy(Sup), Call, Timeout).

%% @equiv cast(Sup, Cast, random_worker)
-spec cast(name(), term()) -> ok.
cast(Sup, Cast) -> cast(Sup, Cast, random_worker).

%% @doc Picks a server and issues the cast to it
-spec cast(name(), term(), strategy()) -> ok.
cast(Sup, Cast, Strategy) -> wpool_process:cast(wpool_sup:Strategy(Sup), Cast).

%% @doc Retrieves a snapshot of the pool stats
-spec stats(name()) -> stats().
stats(Sup) -> wpool_sup:stats(Sup).