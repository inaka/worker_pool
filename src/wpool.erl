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
-module(wpool).
-moduledoc """
Worker pool main interface.

Use functions provided by this module to manage your pools of workers.

## Starting the application

**Worker Pool** is an Erlang application that can be started using the functions in the
`application` module. For convenience, `wpool:start/0` and `wpool:stop/0` are also provided.

## Starting a Pool

To start a new worker pool, you can either

* Use `wpool:child_spec/2` if you want to add the pool under a supervision tree initialisation;
* Use `wpool:start_pool/1` or `wpool:start_pool/2` if you want to supervise it yourself;
* Use `wpool:start_sup_pool/1` or `wpool:start_sup_pool/2` if you want the pool to live under
  `wpool`'s supervision tree.

## Stopping a Pool

To stop a pool, just use `wpool:stop_pool/1` or `wpool:stop_sup_pool/1` according to how you
started the pool.

## Using the Workers

Since the workers are `gen_server`s, messages can be _called_ or _casted_ to them. To do that
you can use `wpool:call` and `wpool:cast` as you would use the equivalent functions on
`gen_server`.

### Choosing a Strategy

Beyond the regular parameters for `gen_server`, `wpool` also provides an extra optional parameter,
`Strategy`: The strategy used to pick up the worker to perform the task. If not provided,
the result of `wpool:default_strategy/0` is used.

The available strategies are defined in the `t:wpool:strategy/0` type.

## Watching a Pool

`wpool` provides a way to get live statistics about a pool. To do that, you can use
`wpool:stats/1`.
""".

-elvis([{elvis_style, private_data_types, disable}]).

-behaviour(application).

-doc """
The number of milliseconds after which a task is considered _overrun_ i.e., delayed.

A warning is emitted using `overrun_handler()`.

The task is monitored until it is finished,
thus more than one warning might be emitted for a single task.

The rounds of warnings are not equally timed, an exponential backoff algorithm is used instead:
after each warning the overrun time is doubled (i.e. with `overrun_warning = 1000` warnings would
be emitted after 1000, 2000, 4000, 8000 ...).

> The default value for this setting is `infinity`, i.e., no warnings are emitted.
""".
-nominal overrun_warning() :: infinity | pos_integer().

-doc """
The maximum number of overrun warnings emitted before killing the worker with a delayed task.

If this parameter is set to a value other than `infinity` the rounds of warnings become equally
timed (i.e. with `overrun_warning = 1000` and `max_overrun_warnings = 5` the task would be killed
after 5 seconds of execution).

> The default value for this setting is `infinity`, i.e., delayed tasks are not killed.
>
> As the worker is being killed it might cause worker's messages to be missing if you
> are using a worker stategy other than `available_worker`.
""".
-nominal max_overrun_warnings() :: infinity | pos_integer().

-doc """
The module and function to call when a task is _overrun_.

The default value for this setting is `{logger, warning}`. The function must be of
arity 1, and it will be called as`Module:Fun(Args)` where `Args` is a proplist with the following
reported values:

* `{alert, AlertType}`: Where `AlertType` is `overrun` on regular warnings, or
`max_overrun_limit` when the worker is about to be killed.
* `{pool, Pool}`: The pool name.
* `{worker, Pid}`: Pid of the worker.
* `{task, Task}`: A description of the task.
* `{runtime, Runtime}`: The runtime of the current round.
""".
-nominal overrun_handler() :: {Module :: module(), Fun :: atom()}.

-doc """
The number of workers in the pool.

> The default value for this setting is `100`.
""".
-nominal workers() :: pos_integer().

-doc """
The `gen_server` module and the arguments to pass to the `init` callback.

This is the module that each worker will run and the `InitArgs` to use on the corresponding
`start_link` call used to initiate it.

The default value for this setting is `{wpool_worker, undefined}`. That means that if you don't
provide a worker implementation, the pool will be generated with this default one.

> See `wpool_worker` for details.
""".
-nominal worker() :: {Module :: module(), InitArg :: term()}.

-doc """
The `shutdown` option to be used over the individual workers.

> Defaults to `5000`.
>
> See `wpool_process_sup` for more details.
""".
-nominal worker_shutdown() :: brutal_kill | timeout().

-doc """
The `shutdown` option to be used over the supervisor that supervises the workers.

> Defaults to `brutal_kill`.
>
> See `wpool_process_sup` for more details.
""".
-nominal pool_sup_shutdown() :: brutal_kill | timeout().

-doc """
The supervision period to use over the supervisor that supervises the workers.

> Defaults to `60`.
>
> See `wpool_pool` for more details.
""".
-nominal pool_sup_period() :: non_neg_integer().

-doc """
The supervision intensity to use over the supervisor that supervises the workers.

> Defaults to `5`.
>
> See `wpool_pool` for more details.
""".
-nominal pool_sup_intensity() :: non_neg_integer().

-doc """
Order in which requests will be stored and handled by workers.

> Defaults to `fifo`.
""".
-nominal queue_type() :: fifo | lifo.

-doc """
A boolean value determining if `queue_manager` should be started for queueing requests.

> Defaults to `true`.
>
> Disabling this will disable `available_worker` and `next_available_worker` strategies.
""".
-nominal enable_queues() :: boolean().

-doc """
A boolean value determining if `event_manager` should be started for callback modules.

> Defaults to `false`.
""".
-nominal enable_callbacks() :: boolean().

-doc """
Initial list of callback modules implementing `wpool_process_callbacks` to be
called on certain worker events.

> This options will only work if the `enable_callbacks` is set to `true`.
>
> Callbacks can be added and removed later by `wpool_pool:add_callback_module/2` and
> `wpool_pool:remove_callback_module/2`.
""".
-nominal callbacks() :: [module()].

-doc """
A function to run with a given worker.

It can be used to enable APIs that hide the `gen_server` behind a complex logic
that might for example curate parameters or run side-effects, for example, `supervisor`.

For example:
```erlang
    Opts = #{
        workers => 3,
        worker_shutdown => infinity,
        worker => {supervisor, {Name, ModuleCallback, Args}}
    },
    %% Note that the supervisor's `init/1` callback takes such 3-tuple.
    {ok, Pid} = wpool:start_sup_pool(pool_of_supervisors, Opts),
...

    Run = fun(Sup, _) -> supervisor:start_child(Sup, Params) end,
    {ok, Pid} = wpool:run(pool_of_supervisors, Run, next_worker),
```
""".
-nominal run(Result) :: fun((name() | pid(), timeout()) -> Result).

-doc """
Name of the pool.
""".
-nominal name() :: atom().

-doc """
Options that can be provided to a new pool.

> `child_spec/2`, `start_pool/2`, `start_sup_pool/2` are the callbacks
> that take a list of these options as a parameter.
""".
-nominal option() ::
    {workers, workers()}
    | {worker, worker()}
    | {worker_opt, [gen_server:start_opt()]}
    | {strategy, supervisor:sup_flags()}
    | {worker_shutdown, worker_shutdown()}
    | {overrun_handler, overrun_handler() | [overrun_handler()]}
    | {overrun_warning, overrun_warning()}
    | {max_overrun_warnings, max_overrun_warnings()}
    | {pool_sup_intensity, pool_sup_intensity()}
    | {pool_sup_shutdown, pool_sup_shutdown()}
    | {pool_sup_period, pool_sup_period()}
    | {queue_type, queue_type()}
    | {enable_callbacks, enable_callbacks()}
    | {enable_queues, enable_queues()}
    | {callbacks, callbacks()}.

-doc """
Options that can be provided to a new pool.

> `child_spec/2`, `start_pool/2`, `start_sup_pool/2` are the callbacks
> that take a list of these options as a parameter.
""".
-nominal options() :: #{
    workers => workers(),
    worker => worker(),
    worker_opt => [gen_server:start_opt()],
    strategy => supervisor:sup_flags(),
    worker_shutdown => worker_shutdown(),
    overrun_handler => overrun_handler() | [overrun_handler()],
    overrun_warning => overrun_warning(),
    max_overrun_warnings => max_overrun_warnings(),
    pool_sup_intensity => pool_sup_intensity(),
    pool_sup_shutdown => pool_sup_shutdown(),
    pool_sup_period => pool_sup_period(),
    queue_type => queue_type(),
    enable_callbacks => enable_callbacks(),
    enable_queues => enable_queues(),
    callbacks => callbacks(),
    _ => _
}.

-doc """
A callback that gets the pool name and returns a worker's name.
""".
-nominal custom_strategy() :: fun((atom()) -> Atom :: atom()).

-doc """
Strategy to use when choosing a worker.

## `best_worker`
Picks the worker with the shortest queue of messages. Loosely based on [this
article](https://lethain.com/load-balancing-across-erlang-process-groups/).

This strategy is usually useful when your workers always perform the same task,
or tasks with expectedly similar runtimes.

## `random_worker`
Just picks a random worker. This strategy is the fastest one to select a worker.
It's ideal if your workers will perform many short tasks.

## `next_worker`
Picks the next worker in a round-robin fashion. This ensures an evenly distribution of tasks.

## `available_worker`
Instead of just picking one of the workers in the queue and sending the request to it, this
strategy queues the request and waits until a worker is available to perform it. That may render
the worker selection part of the process much slower (thus generating the need for an additional
parameter: `Worker_Timeout' that controls how many milliseconds the client is willing to spend
in that, regardless of the global `Timeout' for the call).

This strategy ensures that, if a worker crashes, no messages are lost in its message queue.
It also ensures that, if a task takes too long, that doesn't block other tasks since, as soon as
other worker is free it can pick up the next task in the list.

## `next_available_worker`
In a way, this strategy behaves like `available_worker` in the sense that it will pick the first
worker that it can find which is not running any task at the moment, but the difference is that
it will fail if all workers are busy.

## `{hash_worker, Key}`
This strategy takes a `Key` and selects a worker using `erlang:phash2/2`. This ensures that tasks
classified under the same key will be delivered to the same worker, which is useful to classify
events by key and work on them sequentially on the worker, distributing different keys across
different workers.

## `custom_strategy()`
A callback that gets the pool name and returns a worker's name.
""".
-nominal strategy() ::
    best_worker
    | random_worker
    | next_worker
    | available_worker
    | next_available_worker
    | {hash_worker, term()}
    | custom_strategy().

-doc """
Statistics about a worker in a pool.
""".
-nominal worker_stats() :: [{messsage_queue_len, non_neg_integer()} | {memory, pos_integer()}].

-doc """
Statistics about a given live pool.
""".
-nominal stats() ::
    [
        {pool, name()}
        | {supervisor, pid()}
        | {options, [option()] | options()}
        | {size, non_neg_integer()}
        | {next_worker, pos_integer()}
        | {total_message_queue_len, non_neg_integer()}
        | {workers, [{pos_integer(), worker_stats()}]}
    ].

-export_type([
    name/0,
    callbacks/0,
    worker/0,
    workers/0,
    worker_shutdown/0,
    overrun_handler/0,
    overrun_warning/0,
    max_overrun_warnings/0,
    pool_sup_intensity/0,
    pool_sup_shutdown/0,
    pool_sup_period/0,
    enable_callbacks/0,
    enable_queues/0,
    option/0,
    options/0,
    custom_strategy/0,
    strategy/0,
    queue_type/0,
    run/1,
    worker_stats/0,
    stats/0
]).

-export([start/0, start/2, stop/0, stop/1]).
-export([child_spec/2, start_pool/1, start_pool/2, start_sup_pool/1, start_sup_pool/2]).
-export([stop_pool/1, stop_sup_pool/1]).
-export([
    call/2, call/3, call/4,
    cast/2, cast/3,
    run/2, run/3, run/4,
    broadcall/3,
    broadcast/2,
    send_request/2, send_request/3, send_request/4
]).
-export([stats/0, stats/1, get_workers/1]).
-export([default_strategy/0]).

-doc #{group => "Admin API"}.
-doc """
Starts the application.
""".
-spec start() -> ok | {error, {already_started, ?MODULE}}.
start() ->
    application:start(worker_pool).

-doc #{group => "Admin API"}.
-doc """
Stops the application.
""".
-spec stop() -> ok.
stop() ->
    application:stop(worker_pool).

-doc #{group => "Behaviour callbacks"}.
-doc false.
-spec start(term(), term()) -> supervisor:startlink_ret().
start(_StartType, _StartArgs) ->
    wpool_sup:start_link().

-doc #{group => "Behaviour callbacks"}.
-doc false.
-spec stop(term()) -> ok.
stop(_State) ->
    ok.

-doc #{group => "Public API"}.
-doc #{equiv => start_pool(Name, [])}.
-spec start_pool(name()) -> supervisor:startlink_ret().
start_pool(Name) ->
    start_pool(Name, []).

-doc #{group => "Public API"}.
-doc """
Starts (and links) a pool of `N` `wpool_process`es.
The result pid belongs to a supervisor (in case you want to add it to a
supervisor tree).
""".
-spec start_pool(name(), [option()] | options()) -> supervisor:startlink_ret().
start_pool(Name, Options) ->
    wpool_pool:start_link(Name, wpool_utils:add_defaults(Options)).

-doc #{group => "Public API"}.
-doc """
Builds a child specification to pass to a supervisor.
""".
-spec child_spec(name(), [option()] | options()) -> supervisor:child_spec().
child_spec(Name, Options) ->
    FullOptions = wpool_utils:add_defaults(Options),
    #{
        id => Name,
        start => {wpool, start_pool, [Name, FullOptions]},
        restart => permanent,
        shutdown => infinity,
        type => supervisor
    }.

-doc #{group => "Public API"}.
-doc """
Stops a pool that doesn't belong to `wpool_sup`.
""".
-spec stop_pool(name()) -> true.
stop_pool(Name) ->
    case whereis(Name) of
        undefined ->
            true;
        Pid ->
            exit(Pid, normal)
    end.

-doc #{group => "Public API"}.
-doc #{equiv => start_sup_pool(Name, [])}.
-spec start_sup_pool(name()) -> supervisor:startchild_ret().
start_sup_pool(Name) ->
    start_sup_pool(Name, []).

-doc #{group => "Public API"}.
-doc """
Starts a pool of `N` wpool_processes supervised by `wpool_sup`.
""".
-spec start_sup_pool(name(), [option()] | options()) -> supervisor:startchild_ret().
start_sup_pool(Name, Options) ->
    wpool_sup:start_pool(Name, wpool_utils:add_defaults(Options)).

-doc #{group => "Public API"}.
-doc """
Stops a pool supervised by `wpool_sup` supervision tree.
""".
-spec stop_sup_pool(name()) -> ok.
stop_sup_pool(Name) ->
    wpool_sup:stop_pool(Name).

-doc #{group => "Public API"}.
-doc """
Default strategy.
""".
-spec default_strategy() -> strategy().
default_strategy() ->
    case application:get_env(worker_pool, default_strategy) of
        undefined ->
            available_worker;
        {ok, Strategy} ->
            Strategy
    end.

-doc #{group => "Public API"}.
-doc #{equiv => run(Sup, Run, default_strategy())}.
-spec run(name(), run(Result)) -> Result.
run(Sup, Run) ->
    run(Sup, Run, default_strategy()).

-doc #{group => "Public API"}.
-doc #{equiv => run(Sup, Run, Strategy, 5000)}.
-spec run(name(), run(Result), strategy()) -> Result.
run(Sup, Run, Strategy) ->
    run(Sup, Run, Strategy, 5000).

-doc #{group => "Public API"}.
-doc """
Picks a server and issues the run to it.

For all strategies except `available_worker`, `Timeout` applies only to the
time spent on the actual run to the worker, because time spent finding
the worker in other strategies is negligible.
For `available_worker`, the time used choosing a worker is also considered.
""".
-spec run(name(), run(Result), strategy(), timeout()) -> Result.
run(Sup, Run, available_worker, Timeout) ->
    wpool_pool:run_with_available_worker(Sup, Run, Timeout);
run(Sup, Run, next_available_worker, Timeout) ->
    wpool_process:run(wpool_pool:next_available_worker(Sup), Run, Timeout);
run(Sup, Run, next_worker, Timeout) ->
    wpool_process:run(wpool_pool:next_worker(Sup), Run, Timeout);
run(Sup, Run, random_worker, Timeout) ->
    wpool_process:run(wpool_pool:random_worker(Sup), Run, Timeout);
run(Sup, Run, best_worker, Timeout) ->
    wpool_process:run(wpool_pool:best_worker(Sup), Run, Timeout);
run(Sup, Run, {hash_worker, HashKey}, Timeout) ->
    wpool_process:run(wpool_pool:hash_worker(Sup, HashKey), Run, Timeout);
run(Sup, Run, Fun, Timeout) when is_function(Fun, 1) ->
    wpool_process:run(Fun(Sup), Run, Timeout).

-doc #{group => "Public API"}.
-doc #{equiv => call(Sup, Call, default_strategy())}.
-spec call(name(), term()) -> term().
call(Sup, Call) ->
    call(Sup, Call, default_strategy()).

-doc #{group => "Public API"}.
-doc #{equiv => call(Sup, Call, Strategy, 5000)}.
-spec call(name(), term(), strategy()) -> term().
call(Sup, Call, Strategy) ->
    call(Sup, Call, Strategy, 5000).

-doc #{group => "Public API"}.
-doc """
Picks a server and issues the call to it.

For all strategies except `available_worker`, `Timeout` applies only to the
time spent on the actual run to the worker, because time spent finding
the worker in other strategies is negligible.
For `available_worker`, the time used choosing a worker is also considered.
""".
-spec call(name(), term(), strategy(), timeout()) -> term().
call(Sup, Call, available_worker, Timeout) ->
    wpool_pool:call_available_worker(Sup, Call, Timeout);
call(Sup, Call, next_available_worker, Timeout) ->
    wpool_process:call(wpool_pool:next_available_worker(Sup), Call, Timeout);
call(Sup, Call, next_worker, Timeout) ->
    wpool_process:call(wpool_pool:next_worker(Sup), Call, Timeout);
call(Sup, Call, random_worker, Timeout) ->
    wpool_process:call(wpool_pool:random_worker(Sup), Call, Timeout);
call(Sup, Call, best_worker, Timeout) ->
    wpool_process:call(wpool_pool:best_worker(Sup), Call, Timeout);
call(Sup, Call, {hash_worker, HashKey}, Timeout) ->
    wpool_process:call(wpool_pool:hash_worker(Sup, HashKey), Call, Timeout);
call(Sup, Call, Fun, Timeout) when is_function(Fun, 1) ->
    wpool_process:call(Fun(Sup), Call, Timeout).

-doc #{group => "Public API"}.
-doc #{equiv => cast(Sup, Cast, default_strategy())}.
-spec cast(name(), term()) -> ok.
cast(Sup, Cast) ->
    cast(Sup, Cast, default_strategy()).

-doc #{group => "Public API"}.
-doc """
Picks a server and issues the cast to it.
""".
-spec cast(name(), term(), strategy()) -> ok.
cast(Sup, Cast, available_worker) ->
    wpool_pool:cast_to_available_worker(Sup, Cast);
cast(Sup, Cast, next_available_worker) ->
    wpool_process:cast(wpool_pool:next_available_worker(Sup), Cast);
cast(Sup, Cast, next_worker) ->
    wpool_process:cast(wpool_pool:next_worker(Sup), Cast);
cast(Sup, Cast, random_worker) ->
    wpool_process:cast(wpool_pool:random_worker(Sup), Cast);
cast(Sup, Cast, best_worker) ->
    wpool_process:cast(wpool_pool:best_worker(Sup), Cast);
cast(Sup, Cast, {hash_worker, HashKey}) ->
    wpool_process:cast(wpool_pool:hash_worker(Sup, HashKey), Cast);
cast(Sup, Cast, Fun) when is_function(Fun, 1) ->
    wpool_process:cast(Fun(Sup), Cast).

-doc #{group => "Public API"}.
-doc #{equiv => send_request(Sup, Call, default_strategy(), 5000)}.
-spec send_request(name(), term()) -> noproc | timeout | gen_server:request_id().
send_request(Sup, Call) ->
    send_request(Sup, Call, default_strategy()).

-doc #{group => "Public API"}.
-doc #{equiv => send_request(Sup, Call, Strategy, 5000)}.
-spec send_request(name(), term(), strategy()) ->
    noproc | timeout | gen_server:request_id().
send_request(Sup, Call, Strategy) ->
    send_request(Sup, Call, Strategy, 5000).

-doc #{group => "Public API"}.
-doc """
Picks a server and issues the call to it.

> `Timeout` applies only for the time used choosing a worker in the `available_worker` strategy.
""".
-spec send_request(name(), term(), strategy(), timeout()) ->
    noproc | timeout | gen_server:request_id().
send_request(Sup, Call, available_worker, Timeout) ->
    wpool_pool:send_request_available_worker(Sup, Call, Timeout);
send_request(Sup, Call, next_available_worker, _Timeout) ->
    wpool_process:send_request(wpool_pool:next_available_worker(Sup), Call);
send_request(Sup, Call, next_worker, _Timeout) ->
    wpool_process:send_request(wpool_pool:next_worker(Sup), Call);
send_request(Sup, Call, random_worker, _Timeout) ->
    wpool_process:send_request(wpool_pool:random_worker(Sup), Call);
send_request(Sup, Call, best_worker, _Timeout) ->
    wpool_process:send_request(wpool_pool:best_worker(Sup), Call);
send_request(Sup, Call, {hash_worker, HashKey}, _Timeout) ->
    wpool_process:send_request(wpool_pool:hash_worker(Sup, HashKey), Call);
send_request(Sup, Call, Fun, _Timeout) when is_function(Fun, 1) ->
    wpool_process:send_request(Fun(Sup), Call).

-doc #{group => "Public API"}.
-doc """
Casts a message to all the workers within the given pool.

> These messages don't get queued, they go straight to the worker's message queues, so
> if you're using `available_worker` strategy to balance the charge and you have some
> tasks queued up waiting for the next available worker, the broadcast will reach all
> the workers **before** the queued up tasks.
""".
-spec broadcast(wpool:name(), term()) -> ok.
broadcast(Sup, Cast) ->
    wpool_pool:broadcast(Sup, Cast).

-doc #{group => "Public API"}.
-doc """
Calls all the workers within the given pool async and waits for the responses synchronously.

> If one worker times out, the entire call is considered timed-out.
""".
-spec broadcall(wpool:name(), term(), timeout()) ->
    {[Replies :: term()], [Errors :: term()]}.
broadcall(Sup, Call, Timeout) ->
    wpool_pool:broadcall(Sup, Call, Timeout).

-doc #{group => "Public API"}.
-doc """
Retrieves a snapshot of statistics for all pools.

> See `t:stats/0` for details on the return type.
""".
-spec stats() -> [stats()].
stats() ->
    wpool_pool:stats().

-doc #{group => "Public API"}.
-doc """
Retrieves a snapshot of statistics for a a given pool.

> See `t:stats/0` for details on the return type.
""".
-spec stats(name()) -> stats().
stats(Sup) ->
    wpool_pool:stats(Sup).

-doc #{group => "Public API"}.
-doc """
Retrieves the list of worker registered names.

This can be useful to manually inspect the workers or do custom work on them.
""".
-spec get_workers(name()) -> [atom()].
get_workers(Sup) ->
    wpool_pool:get_workers(Sup).
