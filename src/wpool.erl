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
%%% @doc Worker pool main interface.
%%%
%%% Use functions provided by this module to manage your pools of workers.
%%%
%%% <h2>Starting the application</h2>
%%% <b>Worker Pool</b> is an Erlang application that can be started using the functions in the
%%% `application' module. For convenience, `wpool:start/0' and `wpool:stop/0' are also provided.
%%%
%%% <h2>Starting a Pool</h2>
%%%
%%% To start a new worker pool, you can either
%%% <ul>
%%%   <li>Use `wpool:child_spec/2' if you want to add the pool under a supervision tree
%%%   initialisation;</li>
%%%   <li>Use `wpool:start_pool/1' or `wpool:start_pool/2' if you want to supervise it
%%%   yourself;</li>
%%%   <li>Use `wpool:start_sup_pool/1' or `wpool:start_sup_pool/2' if you want the pool to live
%%%   under
%%%   wpool's supervision tree.</li>
%%% </ul>
%%%
%%% <h2>Stopping a Pool</h2>
%%% To stop a pool, just use `wpool:stop_pool/1' or `wpool:stop_sup_pool/1' according to how you
%%% started the pool.
%%%
%%% <h2>Using the Workers</h2>
%%%
%%% Since the workers are `gen_server's, messages can be `call'ed or `cast'ed to them. To do that
%%% you can use `wpool:call' and `wpool:cast' as you would use the equivalent functions on
%%% `gen_server'.
%%%
%%% <h3>Choosing a Strategy</h3>
%%%
%%% Beyond the regular parameters for `gen_server', wpool also provides an extra optional parameter
%%% <b>Strategy</b> The strategy used to pick up the worker to perform the task. If not provided,
%%% the result of `wpool:default_strategy/0' is used.
%%%
%%% The available strategies are defined in the `t:wpool:strategy/0' type.
%%%
%%% <h2>Watching a Pool</h2>
%%% Wpool provides a way to get live statistics about a pool. To do that, you can use
%%% `wpool:stats/1'.
-module(wpool).

-behaviour(application).

-type overrun_warning() :: infinity | pos_integer().
%% The number of milliseconds after which a task is considered <i>overrun</i> i.e., delayed.
%%
%% A warning is emitted using {@link overrun_handler()}.
%%
%% The task is monitored until it is finished,
%% thus more than one warning might be emitted for a single task.
%%
%% The rounds of warnings are not equally timed, an exponential backoff algorithm is used instead:
%% after each warning the overrun time is doubled (i.e. with `overrun_warning = 1000' warnings would
%% be emitted after 1000, 2000, 4000, 8000 ...).
%%
%% The default value for this setting is `infinity', i.e., no warnings are emitted.

-type max_overrun_warnings() :: infinity | pos_integer().
%% The maximum number of overrun warnings emitted before killing the worker with a delayed task.
%%
%% If this parameter is set to a value other than `infinity' the rounds of warnings becomes equally
%% timed (i.e. with `overrun_warning = 1000' and `max_overrun_warnings = 5' the task would be killed
%% after 5 seconds of execution).
%%
%% The default value for this setting is `infinity', i.e., delayed tasks are not killed.
%%
%% <b>NOTE</b>: As the worker is being killed it might cause worker's messages to be missing if you
%% are using a worker stategy other than `available_worker' (see worker {@link strategy()} below).

-type overrun_handler() :: {Module :: module(), Fun :: atom()}.
%% The module and function to call when a task is <i>overrun</i>
%%
%% The default value for this setting is `{error_logger, warning_report}'. The function must be of
%% arity 1, and it will be called as`Module:Fun(Args)' where `Args' is a proplist with the following
%% reported values:
%% <ul>
%%  <li>`{alert, AlertType}': Where `AlertType' is `overrun' on regular warnings, or
%%  `max_overrun_limit' when the worker is about to be killed.</li>
%%  <li>`{pool, Pool}': The pool name.</li>
%%  <li>`{worker, Pid}': Pid of the worker.</li>
%%  <li>`{task, Task}': A description of the task.</li>
%%  <li>`{runtime, Runtime}': The runtime of the current round.</li>
%% </ul>

-type workers() :: pos_integer().
%% The number of workers in the pool.
%%
%% The default value for this setting is `100'

-type worker() :: {Module :: module(), InitArg :: term()}.
%% The `gen_server' module and ther arguments to pass to the `init' callback.
%%
%% This is the module that each worker will run and the `InitArgs' to use on the corresponding
%% `start_link' call used to initiate it.
%%
%% The default value for this setting is `{wpool_worker, undefined}'. That means that if you don't
%% provide a worker implementation, the pool will be generated with this default one.
%% See {@link wpool_worker} for details.

-type worker_opt() :: gen_server:start_opt().
%% Server options that will be passed to each `gen_server' worker.
%%
%% This are the same as described at the `gen_server' documentation.

-type worker_shutdown() :: worker_shutdown().
%% The `shutdown' option to be used over the individual workers.
%%
%% Defaults to `5000'. See {@link wpool_process_sup} for more details.

-type supervisor_strategy() :: supervisor:sup_flags().
%% Supervision strategy to use over the individual workers.
%%
%% Defaults to `{one_for_one, 5, 60}'. See {@link wpool_process_sup} for more details.

-type pool_sup_shutdown() :: brutal_kill | timeout().
%% The `shutdown' option to be used over the supervisor that supervises the workers.
%%
%% Defaults to `brutal_kill'. See {@link wpool_process_sup} for more details.

-type pool_sup_period() :: non_neg_integer().
%% The supervision period to use over the supervisor that supervises the workers.
%%
%% Defaults to `60'. See {@link wpool_pool} for more details.

-type pool_sup_intensity() :: non_neg_integer().
%% The supervision intensity to use over the supervisor that supervises the workers.
%%
%% Defaults to `5'. See {@link wpool_pool} for more details.

-type queue_type() :: wpool_queue_manager:queue_type().
%% Order in which requests will be stored and handled by workers.
%%
%% This option can take values `lifo' or `fifo'. Defaults to `fifo'.

-type enable_callbacks() :: boolean().
%% A boolean value determining if `event_manager' should be started for callback modules.
%%
%% Defaults to `false'.

-type callbacks() :: [module()].
%% Initial list of callback modules implementing `wpool_process_callbacks' to be
%% called on certain worker events.
%%
%% This options will only work if the {@link enable_callbacks()} is set to <b>true</b>.
%% Callbacks can be added and removed later by `wpool_pool:add_callback_module/2' and
%% `wpool_pool:remove_callback_module/2'.

-type name() :: atom().
%% Name of the pool

-type option() ::
    {workers, workers()} |
    {worker, worker()} |
    {worker_opt, [worker_opt()]} |
    {strategy, supervisor_strategy()} |
    {worker_shutdown, worker_shutdown()} |
    {overrun_handler, overrun_handler()} |
    {overrun_warning, overrun_warning()} |
    {max_overrun_warnings, max_overrun_warnings()} |
    {pool_sup_intensity, pool_sup_intensity()} |
    {pool_sup_shutdown, pool_sup_shutdown()} |
    {pool_sup_period, pool_sup_period()} |
    {queue_type, queue_type()} |
    {enable_callbacks, enable_callbacks()} |
    {callbacks, callbacks()}.
%% Options that can be provided to a new pool.
%%
%% `child_spec/2', `start_pool/2', `start_sup_pool/2' are the callbacks
%% that take a list of these options as a parameter.

-type custom_strategy() :: fun(([atom()]) -> Atom :: atom()).
%% A callback that gets the pool name and returns a worker's name.

-type strategy() ::
    best_worker |
    random_worker |
    next_worker |
    available_worker |
    next_available_worker |
    {hash_worker, term()} |
    custom_strategy().
%% Strategy to use when choosing a worker.
%%
%% <h2>`best_worker'</h2>
%% Picks the worker with the smaller queue of messages. Loosely based on this
%% article: [https://lethain.com/load-balancing-across-erlang-process-groups/].
%%
%% This strategy is usually useful when your workers always perform the same task,
%% or tasks with expectedly similar runtimes.
%%
%% <h2>`random_worker'</h2>
%% Just picks a random worker. This strategy is the fastest one when to select a worker. It's ideal
%% if your workers will perform many short tasks.
%%
%% <h2>`next_worker'</h2>
%% Picks the next worker in a round-robin fashion. This ensures an evenly distribution of tasks.
%%
%% <h2>`available_worker'</h2>
%% Instead of just picking one of the workers in the queue and sending the request to it, this
%% strategy queues the request and waits until a worker is available to perform it. That may render
%% the worker selection part of the process much slower (thus generating the need for an additional
%% parameter: `Worker_Timeout' that controls how many milliseconds is the client willing to spend
%% in that, regardless of the global `Timeout' for the call).
%%
%% This strategy ensures that, if a worker crashes, no messages are lost in its message queue.
%% It also ensures that, if a task takes too long, that doesn't block other tasks since, as soon as
%% other worker is free it can pick up the next task in the list.
%%
%% <h2>`next_available_worker'</h2>
%% In a way, this strategy behaves like `available_worker' in the sense that it will pick the first
%% worker that it can find which is not running any task at the moment, but the difference is that
%% it will fail if all workers are busy.
%%
%% <h2>`{hash_worker, Key}'</h2>
%% This strategy takes a `Key' and selects a worker using `erlang:phash2/2'. This ensures that tasks
%% classified under the same key will be delivered to the same worker, which is useful to classify
%% events by key and work on them sequentially on the worker, distributing different keys across
%% different workers.
%%
%% <h2>{@link custom_strategy()}</h2>
%% A callback that gets the pool name and returns a worker's name.

-type worker_stats() ::
    [{messsage_queue_len, non_neg_integer()} | {memory, pos_integer()}].
%% Statistics about a worker in a pool.

-type stats() ::
    [{pool, name()} |
     {supervisor, pid()} |
     {options, [option()]} |
     {size, non_neg_integer()} |
     {next_worker, pos_integer()} |
     {total_message_queue_len, non_neg_integer()} |
     {workers, [{pos_integer(), worker_stats()}]}].
%% Statistics about a given live pool.

-export_type([name/0, option/0, custom_strategy/0, strategy/0, worker_stats/0, stats/0]).

-export([start/0, start/2, stop/0, stop/1]).
-export([child_spec/2, start_pool/1, start_pool/2, start_sup_pool/1, start_sup_pool/2]).
-export([stop_pool/1, stop_sup_pool/1]).
-export([call/2, cast/2, call/3, cast/3, call/4, broadcall/3, broadcast/2]).
-export([send_request/2, send_request/3, send_request/4]).
-export([stats/0, stats/1, get_workers/1]).
-export([default_strategy/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ADMIN API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the application
-spec start() -> ok | {error, {already_started, ?MODULE}}.
start() ->
    application:start(worker_pool).

%% @doc Stops the application
-spec stop() -> ok.
stop() ->
    application:stop(worker_pool).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BEHAVIOUR CALLBACKS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @private
-spec start(any(), any()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    wpool_sup:start_link().

%% @private
-spec stop(any()) -> ok.
stop(_State) ->
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PUBLIC API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @equiv start_pool(Name, [])
-spec start_pool(name()) -> {ok, pid()}.
start_pool(Name) ->
    start_pool(Name, []).

%% @doc Starts (and links) a pool of N wpool_processes.
%%      The result pid belongs to a supervisor (in case you want to add it to a
%%      supervisor tree)
-spec start_pool(name(), [option()]) ->
                    {ok, pid()} | {error, {already_started, pid()} | term()}.
start_pool(Name, Options) ->
    wpool_pool:start_link(Name, wpool_utils:add_defaults(Options)).

%% @doc Builds a child specification to pass to a supervisor.
-spec child_spec(name(), [option()]) -> supervisor:child_spec().
child_spec(Name, Options) ->
    FullOptions = wpool_utils:add_defaults(Options),
    #{id => Name,
      start => {wpool, start_pool, [Name, FullOptions]},
      restart => permanent,
      shutdown => infinity,
      type => supervisor}.

%% @doc Stops a pool that doesn't belong to `wpool_sup'.
-spec stop_pool(name()) -> true.
stop_pool(Name) ->
    case whereis(Name) of
        undefined ->
            true;
        Pid ->
            exit(Pid, normal)
    end.

%% @equiv start_sup_pool(Name, [])
-spec start_sup_pool(name()) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_sup_pool(Name) ->
    start_sup_pool(Name, []).

%% @doc Starts a pool of N wpool_processes supervised by `wpool_sup'
-spec start_sup_pool(name(), [option()]) ->
                        {ok, pid()} | {error, {already_started, pid()} | term()}.
start_sup_pool(Name, Options) ->
    wpool_sup:start_pool(Name, wpool_utils:add_defaults(Options)).

%% @doc Stops a pool supervised by `wpool_sup' supervision tree.
-spec stop_sup_pool(name()) -> ok.
stop_sup_pool(Name) ->
    wpool_sup:stop_pool(Name).

%% @doc Default strategy
-spec default_strategy() -> strategy().
default_strategy() ->
    case application:get_env(worker_pool, default_strategy) of
        undefined ->
            available_worker;
        {ok, Strategy} ->
            Strategy
    end.

%% @equiv call(Sup, Call, default_strategy())
-spec call(name(), term()) -> term().
call(Sup, Call) ->
    call(Sup, Call, default_strategy()).

%% @equiv call(Sup, Call, Strategy, 5000)
-spec call(name(), term(), strategy()) -> term().
call(Sup, Call, Strategy) ->
    call(Sup, Call, Strategy, 5000).

%% @doc Picks a server and issues the call to it.
%%      For all strategies except available_worker, Timeout applies only to the
%%      time spent on the actual call to the worker, because time spent finding
%%      the worker in other strategies is negligible.
%%      For available_worker the time used choosing a worker is also considered
-spec call(name(), term(), strategy(), timeout()) -> term().
call(Sup, Call, available_worker, Timeout) ->
    wpool_pool:call_available_worker(Sup, Call, Timeout);
call(Sup, Call, {hash_worker, HashKey}, Timeout) ->
    wpool_process:call(
        wpool_pool:hash_worker(Sup, HashKey), Call, Timeout);
call(Sup, Call, Fun, Timeout) when is_function(Fun) ->
    wpool_process:call(Fun(Sup), Call, Timeout);
call(Sup, Call, Strategy, Timeout) ->
    wpool_process:call(
        wpool_pool:Strategy(Sup), Call, Timeout).

%% @equiv cast(Sup, Cast, default_strategy())
-spec cast(name(), term()) -> ok.
cast(Sup, Cast) ->
    cast(Sup, Cast, default_strategy()).

%% @doc Picks a server and issues the cast to it
-spec cast(name(), term(), strategy()) -> ok.
cast(Sup, Cast, available_worker) ->
    wpool_pool:cast_to_available_worker(Sup, Cast);
cast(Sup, Cast, {hash_worker, HashKey}) ->
    wpool_process:cast(
        wpool_pool:hash_worker(Sup, HashKey), Cast);
cast(Sup, Cast, Fun) when is_function(Fun) ->
    wpool_process:cast(Fun(Sup), Cast);
cast(Sup, Cast, Strategy) ->
    wpool_process:cast(
        wpool_pool:Strategy(Sup), Cast).

%% @equiv send_request(Sup, Call, default_strategy(), 5000)
-spec send_request(name(), term()) -> noproc | timeout | gen_server:request_id().
send_request(Sup, Call) ->
    send_request(Sup, Call, default_strategy()).

%% @equiv send_request(Sup, Call, Strategy, 5000)
-spec send_request(name(), term(), strategy()) ->
                      noproc | timeout | gen_server:request_id().
send_request(Sup, Call, Strategy) ->
    send_request(Sup, Call, Strategy, 5000).

%% @doc Picks a server and issues the call to it.
%%      Timeout applies only for the time used choosing a worker in the available_worker strategy
-spec send_request(name(), term(), strategy(), timeout()) ->
                      noproc | timeout | gen_server:request_id().
send_request(Sup, Call, available_worker, Timeout) ->
    wpool_pool:send_request_available_worker(Sup, Call, Timeout);
send_request(Sup, Call, {hash_worker, HashKey}, _Timeout) ->
    wpool_process:send_request(
        wpool_pool:hash_worker(Sup, HashKey), Call);
send_request(Sup, Call, Fun, _Timeout) when is_function(Fun) ->
    wpool_process:send_request(Fun(Sup), Call);
send_request(Sup, Call, Strategy, _Timeout) ->
    wpool_process:send_request(
        wpool_pool:Strategy(Sup), Call).

%% @doc Retrieves a snapshot of statistics for all pools.
%%
%% See `t:stats/0' for details on the return type.
-spec stats() -> [stats()].
stats() ->
    wpool_pool:stats().

%% @doc Retrieves a snapshot of statistics for a a given pool.
%%
%% See `t:stats/0' for details on the return type.
-spec stats(name()) -> stats().
stats(Sup) ->
    wpool_pool:stats(Sup).

%% @doc Retrieves the list of worker registered names.
%% This can be useful to manually inspect the workers or do custom work on them.
-spec get_workers(name()) -> [atom()].
get_workers(Sup) ->
    wpool_pool:get_workers(Sup).

%% @doc Casts a message to all the workers within the given pool.
%%
%% <b>NOTE:</b> This messages don't get queued, they go straight to the worker's message queues, so
%% if you're using available_worker strategy to balance the charge and you have some tasks queued up
%% waiting for the next available worker, the broadcast will reach all the workers <b>before</b> the
%% queued up tasks.
-spec broadcast(wpool:name(), term()) -> ok.
broadcast(Sup, Cast) ->
    wpool_pool:broadcast(Sup, Cast).

%% @doc Calls all the workers within the given pool async and waits for the responses synchronously.
%%
%% If one worker times out, the entire call is considered timed-out.
-spec broadcall(wpool:name(), term(), timeout()) ->
                   {[Replies :: term()], [Errors :: term()]}.
broadcall(Sup, Call, Timeout) ->
    wpool_pool:broadcall(Sup, Call, Timeout).
