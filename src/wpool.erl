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

%% @doc Worker pool main interface. Use functions provided by this module to manage your pools of workers
-module(wpool).
-author('elbrujohalcon@inaka.net').

-define(DEFAULTS, [{overrun_warning, infinity}, {overrun_handler, {error_logger, warning_report}}, {workers, 100}, {worker, {wpool_worker, undefined}}]).

-type name() :: atom().
-type option() :: {overrun_warning, infinity|pos_integer()} | {overrun_handler, {Module::atom(), Fun::atom()}} | {workers, pos_integer()} | {worker, {Module::atom(), InitArg::term()}}.
-type strategy() :: best_worker | random_worker | next_worker | available_worker.
-type worker_stats() :: [{messsage_queue_len, non_neg_integer()} | {memory, pos_integer()}].
-type stats() :: [{workers, pos_integer()} | {total_message_queue_len, non_neg_integer()} | {worker_stats, [{pos_integer(), worker_stats()}]}].
-export_type([name/0, option/0, strategy/0, worker_stats/0, stats/0]).

-export([start/0, start/2, stop/0, stop/1]).
-export([start_pool/1, start_pool/2, start_sup_pool/1, start_sup_pool/2, stop_pool/1]).
-export([call/2, cast/2, call/3, cast/3, call/4, call/5]).
-export([stats/1]).
-export([default_strategy/0]).

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
start(_StartType, _StartArgs) ->
    wpool_sup:start_link().

%% @private
-spec stop(any()) -> ok.
stop(_State) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PUBLIC API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @equiv start_pool(Name, [])
-spec start_pool(name()) -> {ok, pid()}.
start_pool(Name) -> start_pool(Name, []).

%% @doc Starts (and links) a pool of N wpool_processes.
%%      The result pid belongs to a supervisor (in case you want to add it to a supervisor tree)
-spec start_pool(name(), [option()]) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_pool(Name, Options) -> wpool_pool:start_link(Name, Options ++ ?DEFAULTS).

%% @equiv start_sup_pool(Name, [])
-spec start_sup_pool(name()) -> {ok, pid()}.
start_sup_pool(Name) -> start_sup_pool(Name, []).

%% @doc Starts a pool of N wpool_processes under the supervision of {@link wpool_sup}
-spec start_sup_pool(name(), [option()]) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_sup_pool(Name, Options) -> wpool_sup:start_pool(Name, Options ++ ?DEFAULTS).

%% @doc Stops the pool
-spec stop_pool(name()) -> ok.
stop_pool(Name) -> wpool_sup:stop_pool(Name).

%% @doc Default strategy
-spec default_strategy() -> available_worker.
default_strategy() -> available_worker.

%% @equiv call(Sup, Call, default_strategy())
-spec call(name(), term()) -> term().
call(Sup, Call) -> call(Sup, Call, default_strategy()).

%% @equiv call(Sup, Call, Strategy, 5000)
-spec call(name(), term(), strategy()) -> term().
call(Sup, Call, Strategy) -> call(Sup, Call, Strategy, 5000).

%% @doc Picks a server and issues the call to it.
%%      For all strategies except available_worker, Timeout applies only to the
%%      time spent on the actual call to the worker, because time spent finding
%%      the woker in other strategies is negligible.
%%      For available_worker the time used choosing a worker is also considered
-spec call(name(), term(), strategy(), timeout()) -> term().
call(Sup, Call, available_worker, infinity) ->
    wpool_process:call(wpool_pool:available_worker(Sup, infinity), Call, infinity);
call(Sup, Call, available_worker, Timeout) ->
    {Elapsed, Worker} = timer:tc(wpool_pool, available_worker, [Sup, Timeout]),
    % Since the Timeout is a general constraint, we have to deduce the time
    % we spent waiting for a worker, and if it took it too much, no_workers
    % exception should have been thrown
    % It may end up lower than 0, but not much lower, so we use abs to send
    % wpool_process a valid timeout value
    NewTimeout = abs(Timeout - round(Elapsed/1000)),
    wpool_process:call(Worker, Call, NewTimeout);
call(Sup, Call, Strategy, Timeout) -> wpool_process:call(wpool_pool:Strategy(Sup), Call, Timeout).

-type available_worker_timeout() :: timeout().
-spec call(name(), term(), strategy(), available_worker_timeout(), timeout()) -> term().
call(Sup, Call, available_worker, Worker_Timeout, Timeout) ->
    Worker = wpool_pool:available_worker(Sup, Worker_Timeout),
    wpool_process:call(Worker, Call, Timeout);
call(Sup, Call, Strategy, _Worker_Timeout, Timeout) -> call(Sup, Call, Strategy, Timeout).

%% @equiv cast(Sup, Cast, default_strategy())
-spec cast(name(), term()) -> ok.
cast(Sup, Cast) -> cast(Sup, Cast, default_strategy()).

%% @doc Picks a server and issues the cast to it
-spec cast(name(), term(), strategy()) -> ok.
cast(Sup, Cast, available_worker) -> wpool_pool:cast_to_available_worker(Sup, Cast);
cast(Sup, Cast, Strategy) -> wpool_process:cast(wpool_pool:Strategy(Sup), Cast).

%% @doc Retrieves a snapshot of the pool stats
-spec stats(name()) -> stats().
stats(Sup) -> wpool_pool:stats(Sup).
