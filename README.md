# Worker Pool [![Build Status](https://github.com/inaka/worker_pool/actions/workflows/erlang.yml/badge.svg)](https://github.com/inaka/worker_pool/actions/workflows/erlang.yml)

<img src="https://img3.wikia.nocookie.net/__cb20140705120849/clubpenguin/images/thumb/f/ff/MINIONS.jpg/481px-MINIONS.jpg" align="right" style="float:right" height="400" />

A pool of gen servers.

## Abstract

The goal of **worker pool** is pretty straightforward: to provide a transparent way to manage a pool of workers and _do the best effort_ in balancing the load among them, distributing the tasks requested to the pool.

You can just replace your calls to the `gen_server` module with calls to the `wpool` module, i.e., wherever you had a `gen_server:call/N` now you put a `wpool:call/N`, and that’s it!

## Installation

Worker Pool is available on [Hex.pm](https://hex.pm/packages/worker_pool). To install, just add it to your dependencies in `rebar.config`:
```erlang
{deps, [{worker_pool, "~> 6.1"}]}.
```
or in `mix.ers`
```elixir
defp deps() do
  [{:worker_pool, "~> 6.1"}]
end
```

## Documentation

The documentation can be generated from code using [rebar3_ex_doc](https://github.com/starbelly/rebar3_ex_doc) with `rebar3 ex_doc`. It is also available online in [Hexdocs](https://hexdocs.pm/worker_pool/).

All user functions are exposed through the [wpool module](https://hexdocs.pm/worker_pool/wpool.html).

Detailed usage is also documented in the same [wpool module summary](https://hexdocs.pm/worker_pool/doc/wpool.html#content).

## Examples

Say your application needs a connection to a third-party service that is frequently used. You implement a `gen_server` called `my_server` that knows how to talk the third-party protocol and keeps the connection open, and your business logic uses this `my_server` as the API to interact with. But this server is not only a single-point-of-failure, but also a bottleneck.

Let's pool this server!

#### Starting the pool

First we need to start the pool, instead of starting a single server. If your server was part of your supervision tree, and your supervisor had a child-spec like:
```erlang
    ChildSpec = #{id => my_server_name,
      start => {my_server, start_link, Arguments},
      restart => permanent,
      shutdown => 5000,
      type => worker}.
```

You can now replace it by
```erlang
    WPoolOpts = [{worker, {my_server, Arguments}}],
    ChildSpec = wpool:child_spec(my_server_name, WPoolOpts),
```

#### Using the pool

Now that the pool is in place, wherever you've called the server, now you can simply call the pool: all code like the following
```erlang
    %% ...
    gen_server:call(my_server, Request),
    %% ...
    gen_server:cast(my_server, Notify),
    %% ...
```
can simply be replaced by
```erlang
    %% ...
    wpool:call(my_server, Request),
    %% ...
    wpool:cast(my_server, Notify),
    %% ...
```

If you want all the workers to get notified of an event (for example for consistency reasons), you can use:
```erlang
    wpool:broadcast(my_server, Request)
```

And if events have a partial ordering, that is, there is a subset of them were they should be processed in a strict ordering, for example requests by user `X` should be processed sequentially but how they interleave with other requests is irrelevant, you can use:
```erlang
    wpool:call(my_server, Request, {hash_worker, X})
```
and requests for `X` will always be sent to the same worker.

And just like that, all your requests are now pooled!

By passing a more complex configuration in the `WPoolOpts` parameter, you can tweak many things, for example the number of workers (`t:wpool:workers()`), options to pass to OTP's the `gen_server` engine behind your code `t:wpool:worker_opt()`, the strategy to supervise all the workers (`t:wpool:strategy()`), register callbacks you want to be triggered on worker's events (`t:wpool:callbacks()`), and many more. See `t:wpool:option()` for all options available.

#### Case studies used in production

To see how `wpool` is used you can check the [test](test) folder where you'll find many different scenarios exercised in the different suites.

If you want to see **worker_pool** in a _real life_ project, we recommend you to check [sumo_db](https://github.com/inaka/sumo_db), another open-source library from [Inaka](https://inaka.github.io/) that uses wpool intensively, or [MongooseIM](https://github.com/esl/MongooseIM), an Erlang Solutions' Messaging server that uses wpool in many different ways.

## Benchmarks

**wpool** comes with a very basic [benchmarker](https://github.com/inaka/worker_pool/blob/main/test/wpool_bench.erl) that let's you compare different strategies against the default `wpool_worker`. If you want to do the same in your project, you can use `wpool_bench` as a template and replace the worker and the tasks by your own ones.

## Contact Us

If you find any **bugs** or have a **problem** while using this library, please [open an issue](https://github.com/inaka/worker_pool/issues/new) in this repo (or a pull request :)).

## Requirements

**Required OTP version 25** or higher. We only provide guarantees that the system runs on `OTP25+` since that's what we're testing it in, but the `minimum_otp_vsn` is `"21"` because some systems where **worker_pool** is integrated do require it.
