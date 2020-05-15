# Worker Pool [![Build Status](https://travis-ci.org/inaka/worker_pool.svg?branch=master)](https://travis-ci.org/inaka/worker_pool)[![codecov](https://codecov.io/gh/inaka/worker_pool/branch/master/graph/badge.svg)](https://codecov.io/gh/inaka/worker_pool)

<img src="http://img3.wikia.nocookie.net/__cb20140705120849/clubpenguin/images/thumb/f/ff/MINIONS.jpg/481px-MINIONS.jpg" align="right" style="float:right" height="400" />

A pool of gen servers.

### Abstract

The goal of **worker pool** is pretty straightforward: To provide a transparent way to manage a pool of workers and _do the best effort_ in balancing the load among them distributing the tasks requested to the pool.

### Documentation

The documentation can be generated from code using [edoc](http://www.erlang.org/doc/apps/edoc/chapter.html) with ``rebar3 edoc`` or using [erldocs](https://github.com/erldocs/erldocs) with ``make erldocs``. It is also available online [here](https://hexdocs.pm/worker_pool/)

### Usage

All user functions are exposed through the [wpool module](https://hexdocs.pm/worker_pool/wpool.html).

#### Starting the Application
**Worker Pool** is an erlang application that can be started using the functions in the [`application`](http://erldocs.com/current/kernel/application.html) module. For convenience, `wpool:start/0` and `wpool:stop/0` are also provided.

#### Starting a Pool
To start a new worker pool, you can either use `wpool:start_pool` (if you want to supervise it yourself) or `wpool:start_sup_pool` (if you want the pool to live under wpool's supervision tree). You can provide several options on any of those calls:

* **overrun_warning**: The number of milliseconds after which a task is considered *overrun* (i.e. delayed) so a warning is emitted using **overrun_handler**. The task is monitored until it is finished, thus more than one warning might be emitted for a single task. The rounds of warnings are not equally timed, an exponential backoff algorithm is used instead: after each warning the overrun time is doubled (i.e. with `overrun_warning = 1000` warnings would be emmited after 1000, 2000, 4000, 8000 ...) The default value for this setting is `infinity` (i.e. no warnings are emitted)
* **max_overrun_warnings**: The maximum number of overrun warnings emitted before killing a delayed task: that is, killing the worker running the task. If this parameter is set to a value other than `infinity` the rounds of warnings becomes equally timed (i.e. with `overrun_warning = 1000` and `max_overrun_warnings = 5` the task would be killed after 5 seconds of execution) The default value for this setting is `infinity` (i.e. delayed tasks are not killed)


   **NOTE:** As the worker is being killed it might cause worker's messages to be missing if you are using a worker stategy other than `available_worker` (see worker strategies below)


* **overrun_handler**: The module and function to call when a task is *overrun*. The default value for this setting is `{error_logger, warning_report}`. Repor values are:


   * *{alert, AlertType}*: Where `AlertType` is `overrun` on regular warnings, or `max_overrun_limit` when the worker is about to be killed.
   * *{pool, Pool}*: The poolname
   * *{worker, Pid}*: Pid of the worker
   * *{task, Task}*: A description of the task
   * *{runtime, Runtime}*: The runtime of the current round


* **workers**: The number of workers in the pool. The default value for this setting is `100`
* **worker_type**: The type of the worker. The available values are `gen_server`. The default value is `gen_server`. Eventually we'll add `gen_statem` as well.
* **worker**: The [`gen_server`](http://erldocs.com/current/stdlib/gen_server.html) module that each worker will run and the `InitArgs` to use on the corresponding `start_link` call used to initiate it. The default value for this setting is `{wpool_worker, undefined}`. That means that if you don't provide a worker implementation, the pool will be generated with this default one. [`wpool_worker`](https://hexdocs.pm/worker_pool/wpool_worker.html) is a module that implements a very simple RPC-like interface.
* **worker_opt**: Options that will be passed to each `gen_server` worker. This are the same as described at `gen_server` documentation.
* **worker_shutdown**: The `shutdown` option to be used in the child specs of the workers. Defaults to `5000`.
* **strategy**: Not the worker selection strategy (discussed below) but the supervisor flags to be used in the supervisor over the individual workers (`wpool_process_sup`). Defaults to `{one_for_one, 5, 60}`
* **pool_sup_intensity** and **pool_sup_period**: The intensity and period for the supervisor that manages the worker pool system (`wpool_pool`). The strategy of this supervisor must be `one_for_all` but the intensity and period may be changed from their defaults of `5` and `60`.
* **pool_sup_shutdown**: The `shutdown` option to be used for the supervisor over the individual workers (`wpool_process_sup`). That is, the value set in the child spec for this supervisor, which is specified in its parent supervisor (`wpool_pool`).
* **queue_type**: Order in which requests will be stored and handled by workers. This option can take values `lifo` or `fifo`. Defaults to `fifo`.
* **enable_callbacks**: A boolean value determining if `event_manager` should be started for callback modules.
  Defaults to `false`.
* **callbacks**: Initial list of callback modules implementing `wpool_process_callbacks` to be called on certain worker events.
  This options will only work if the `enable_callbacks` is set to **true**. Callbacks can be added and removed later by `wpool_pool:add_callback_module/2` and `wpool_pool:remove_callback_module/2`.

#### Using the Workers
Since the workers are `gen_server`s, messages can be `call`ed or `cast`ed to them. To do that you can use `wpool:call` and `wpool:cast` as you would use the equivalent functions on `gen_server`.

##### Choosing a Strategy
Beyond the regular parameters for `gen_server`, wpool also provides an extra optional parameter: **Strategy**.
The strategy used to pick up the worker to perform the task. If not provided, the result of `wpool:default_strategy/0` is used.  The available strategies are defined in the `wpool:strategy/0` type and also described below:

###### best_worker
Picks the worker with the smaller queue of messages. Loosely based on [this article](http://lethain.com/load-balancing-across-erlang-process-groups/). This strategy is usually useful when your workers always perform the same task, or tasks with expectedly similar runtimes.

###### random_worker
Just picks a random worker. This strategy is the fastest one when to select a worker. It's ideal if your workers will perform many short tasks.

###### next_worker
Picks the next worker in a round-robin fashion. That ensures evenly distribution of tasks.

###### available_worker
Instead of just picking one of the workers in the queue and sending the request to it, this strategy queues the request and waits until a worker is available to perform it. That may render the worker selection part of the process much slower (thus generating the need for an aditional parameter: **Worker_Timeout** that controls how many milliseconds is the client willing to spend in that, regardless of the global **Timeout** for the call).
This strategy ensures that, if a worker crashes, no messages are lost in its message queue.
It also ensures that, if a task takes too long, that doesn't block other tasks since, as soon as other worker is free it can pick up the next task in the list.

###### next_available_worker
In a way, this strategy behaves like `available_worker` in the sense that it will pick the first worker that it can find which is not running any task at the moment, but the difference is that it will fail if all workers are busy.

#### Broadcasting a Pool
Wpool provides a way to `broadcast` a message to every worker within the given Pool.

```erlang
1> wpool:start().
ok
2> wpool:start_pool(my_pool, [{workers, 3}]).
{ok,<0.299.0>}
3> wpool:broadcast(my_pool, {io, format, ["I got a message.~n"]}).
I got a message.
I got a message.
I got a message.
ok
```

**NOTE:** This messages don't get queued, they go straight to the worker's message queues, so if you're using available_worker strategy to balance the charge and you have some tasks queued up waiting for the next available worker, the broadcast will reach all the workers **before** the queued up tasks.

#### Watching a Pool
Wpool provides a way to get live statistics about a pool. To do that, you can use `wpool:stats/1`.

#### Stopping a Pool
To stop a pool, just use `wpool:stop/1`.

### Examples

To see how `wpool` is used you can check the [test](test) folder where you'll find many different scenarios excercised in the different suites.

If you want to see **worker_pool** in a _real life_ project, I recommend you to check [sumo_db](https://github.com/inaka/sumo_db), another open-source library from [Inaka](http://inaka.github.io/) that uses wpool intensively.

### Benchmarks

**wpool** comes with a very basic [benchmarker](test/wpool_bench.erl) that let's you compare different strategies against the default `wpool_worker`. If you want to do the same in your project, you can use `wpool_bench` as a template and replace the worker and the tasks by your own ones.

### Contact Us
If you find any **bugs** or have a **problem** while using this library, please [open an issue](https://github.com/inaka/worker_pool/issues/new) in this repo (or a pull request :)).

### On Hex.pm
Worker Pool is available on [Hex.pm](https://hex.pm/packages/worker_pool).
