# Worker Pool

<img src="http://img3.wikia.nocookie.net/__cb20140705120849/clubpenguin/images/thumb/f/ff/MINIONS.jpg/481px-MINIONS.jpg" align="right" style="float:right" height="400" />

A pool of gen servers and gen fsm.

### Abstract

The goal of **worker pool** is pretty straightforward: To provide a transparent way to manage a pool of workers and _do the best effort_ in balancing the load among them distributing the tasks requested to the pool.

### Documentation

The documentation can be generated from code using [edoc](http://www.erlang.org/doc/apps/edoc/chapter.html) with ``make edoc`` or using [erldocs](https://github.com/erldocs/erldocs) with ``make erldocs``. It is also available online [here](http://inaka.github.io/worker_pool/)

### Usage

All user functions are exposed through the [wpool module](http://inaka.github.io/worker_pool/worker_pool/wpool.html).

#### Starting the Application
**Worker Pool** is an erlang application that can be started using the functions in the [`application`](http://erldocs.com/17.1/kernel/application.html) module. For convinience, `wpool:start/0` and `wpool:stop/0` are also provided.

#### Starting a Pool
To start a new worker pool, you can either use `wpool:start_pool` (if you want to supervise it yourself) or `wpool:start_sup_pool` (if you want the pool to live under wpool's supervision tree). You can provide several options on any of those calls:

* **overrun_warning**: The number of milliseconds after which a task is considered *overrun* (i.e. delayed) so a warning is emitted using **overrun_handler**. The default value for this setting is `infinity` (i.e. no warnings are emitted)
* **overrun_handler**: The module and function to call when a task is *overrun*. The default value for this setting is `{error_logger, warning_report}`.
* **workers**: The number of workers in the pool. The default value for this setting is `100`
* **worker_type**: The type of the worker. The available values are `gen_server` and `gen_fsm`. The default value is `gen_server`
* **worker**: The [`gen_server`](http://erldocs.com/current/stdlib/gen_server.html) or [`gen_fsm`](http://erldocs.com/current/stdlib/gen_fsm.html) module that each worker will run and the `InitArgs` to use on the corresponding `start_link` call used to initiate it. The default value for this setting is `{wpool_worker, undefined}` for `gen_server` type and `{wpool_fsm_worker, undefined}` for `gen_fsm`. That means that if you don't provide a worker implementation, the pool will be generated with this default one. [`wpool_worker`](http://inaka.github.io/worker_pool/worker_pool/wpool_worker.html) and [`wpool_fsm_worker`](http://inaka.github.io/worker_pool/worker_pool/wpool_fsm_worker.html) are modules that implement a very simple RPC-like interfaces
* **worker_opt**: Options that will be passed to each `gen_server` worker. This are the same as described at `gen_server` documentation.

#### Using the Workers
For `gen_server` type, since the workers are `gen_server`s, messages can be `call`ed or `cast`ed to them. To do that you can use `wpool:call` and `wpool:cast` as you would use the equivalent functions on `gen_server`.
For `gen_fsm` messages can be sent using `wpool:send_event` or `wpool:sync_send_event` as you would use the equivalent functions on `gen_fsm`.

##### Choosing a Strategy
Beyond the regular parameters for `gen_server` and `gen_fsm`, wpool also provides an extra optional parameter: **Strategy**.
The strategy used to pick up the worker to perform the task. If not provided, the result of `wpool:default_strategy/0` is used.  The available strategies are defined in the `wpool:strategy/0` type and also described below:

###### best_worker
Picks the worker with the smaller queue of messages. Loosely based on [this article](http://lethain.com/load-balancing-across-erlang-process-groups/). This strategy is usually useful when your workers always perform the same task, or tasks with expectedly similar runtimes.

###### random_worker
Just picks a random worker. This strategy is the fastest one when to select a worker. It's ideal if your workers will perform many short tasks.

###### next_worker
Picks the next worker in a round-robin fashion. That ensures evenly distribution of tasks.

###### available_worker
Instead of just picking one of the workers in the queue and sending the request to it, this strategy queues the request and waits until a worker is available to perform it. That may render the worker selection part of the process much slower (thus generating the need for an aditional paramter: **Worker_Timeout** that controls how many milliseconds is the client willing to spend in that, regardless of the global **Timeout** for the call).
This strategy ensures that, if a worker crashes, no messages are lost in its message queue.
It also ensures that, if a task takes too long, that doesn't block other tasks since, as soon as other worker is free it can pick up the next task in the list.

###### next_available_worker
In a way, this strategy behaves like `available_worker` in the sense that it will pick the first worker that it can find which is not running any task at the moment, but the difference is that it will fail if all workers are busy.

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
For **questions** or **general comments** regarding the use of this library, please use our public
[hipchat room](https://www.hipchat.com/gpBpW3SsT).

If you find any **bugs** or have a **problem** while using this library, please [open an issue](https://github.com/inaka/worker_pool/issues/new) in this repo (or a pull request :)).

And you can check all of our open-source projects at [inaka.github.io](http://inaka.github.io)

### On Hex.pm
Worker Pool is available on [Hex.pm](https://hex.pm/packages/worker_pool).

### NOTE on erlang.mk
Don't use erlang.mk to build the app if you're using an OTP version lower than 18.x. Use plain old rebar and just skip the wpool_meta_SUITE from your test runs.
