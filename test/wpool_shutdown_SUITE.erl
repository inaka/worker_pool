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
-module(wpool_shutdown_SUITE).

-behaviour(ct_suite).

-export([all/0, init_per_suite/1, end_per_suite/1, end_per_testcase/2]).
-export([
    parallel_shutdown/1,
    shutdown_timeout/1,
    restart_workers/1,
    failed_start/1,
    map_strategy/1,
    single_worker/1,
    compatible_shutdown/1,
    legacy_pools_parallel/1,
    async_pools_parallel/1,
    supervisor_failure/1,
    legacy_workers_serial/1,
    pool_restart/1,
    standalone_pool/1,
    child_spec_shutdown/1,
    original_supervision_tree/1
]).
-export([init/1, handle_call/3, terminate/2]).

all() ->
    [
        parallel_shutdown,
        shutdown_timeout,
        restart_workers,
        failed_start,
        map_strategy,
        single_worker,
        compatible_shutdown,
        legacy_pools_parallel,
        async_pools_parallel,
        supervisor_failure,
        legacy_workers_serial,
        pool_restart,
        standalone_pool,
        child_spec_shutdown,
        original_supervision_tree
    ].

init_per_suite(Config) ->
    ok = wpool:start(),
    Config.

end_per_suite(_Config) ->
    wpool:stop().

end_per_testcase(Name, _Config) ->
    case whereis(Name) of
        undefined -> ok;
        _ -> wpool:stop_sup_pool(Name)
    end.

options(Mode) ->
    #{
        workers => 3,
        strategy => {simple_one_for_one, 5, 60},
        pool_sup_shutdown => infinity,
        worker_shutdown => 5000,
        worker => {?MODULE, {self(), Mode}}
    }.

parallel_shutdown(_Config) ->
    {ok, _} = wpool:start_sup_pool(parallel_shutdown, options(block)),
    parallel_stop(parallel_shutdown, fun() -> wpool:stop_sup_pool(parallel_shutdown) end, 0).

child_spec_shutdown(_Config) ->
    Spec = wpool:child_spec(child_spec_shutdown, options(block)),
    #{shutdown := infinity} = Spec,
    {ok, Sup} = supervisor:start_link(?MODULE, {supervisor, Spec}),
    parallel_stop(child_spec_shutdown, fun() -> gen_server:stop(Sup, normal, infinity) end, 2100),
    false = is_process_alive(Sup).

parallel_stop(Name, Stop, Delay) ->
    Workers = worker_pids(Name),
    Monitors = [{P, monitor(process, P)} || P <:- Workers],
    Owner = self(),
    StopRef = make_ref(),
    spawn(fun() -> Owner ! {StopRef, Stop()} end),
    try
        %% No worker can finish until all have entered terminate/2.
        Entered = [
            receive
                {terminating, P} -> P
            after 1000 -> ct:fail(serial_shutdown)
            end
         || _ <:- Workers
        ],
        true = lists:sort(Workers) =:= lists:sort(Entered),
        timer:sleep(Delay),
        true = lists:all(fun is_process_alive/1, Workers)
    after
        [P ! finish || P <:- Workers]
    end,
    [
        receive
            {'DOWN', Ref, process, P, shutdown} -> ok
        after 3000 -> ct:fail(worker_not_stopped)
        end
     || {P, Ref} <:- Monitors
    ],
    receive
        {StopRef, ok} -> ok
    after 3000 -> ct:fail(pool_not_stopped)
    end.

shutdown_timeout(_Config) ->
    Opts = (options(block))#{worker_shutdown => 50},
    {ok, _} = wpool:start_sup_pool(shutdown_timeout, Opts),
    Monitors = [{P, monitor(process, P)} || P <:- worker_pids(shutdown_timeout)],
    ok = wpool:stop_sup_pool(shutdown_timeout),
    [
        receive
            {'DOWN', Ref, process, P, killed} -> ok
        after 3000 -> ct:fail(worker_not_killed)
        end
     || {P, Ref} <:- Monitors
    ],
    %% Drain the termination notifications from this test.
    [
        receive
            {terminating, P} -> ok
        after 0 -> ok
        end
     || {P, _} <:- Monitors
    ],
    ok.

restart_workers(_Config) ->
    {ok, Pool} = wpool:start_sup_pool(restart_workers, options(normal)),
    [First | _] = worker_pids(restart_workers),
    ok = gen_server:stop(First, normal, infinity),
    await(fun() ->
        Ps = worker_pids(restart_workers),
        length(Ps) =:= 3 andalso not lists:member(First, Ps)
    end),
    [{_, Sup, supervisor, _}] = [
        C
     || C <:- supervisor:which_children(Pool), element(3, C) =:= supervisor
    ],
    OldWorkers = worker_pids(restart_workers),
    ok = gen_server:stop(Sup, shutdown, infinity),
    await(fun() -> workers_replaced(restart_workers, OldWorkers) end),
    ok = wpool:stop_sup_pool(restart_workers).

failed_start(_Config) ->
    %% A name collision on the second worker forces a partially completed start.
    Name = wpool_pool:worker_name(failed_start, 2),
    Dummy = spawn(fun() ->
        receive
            finish -> ok
        after 10000 -> ok
        end
    end),
    true = register(Name, Dummy),
    try
        {error, _} = wpool:start_sup_pool(failed_start, options(normal)),
        undefined = whereis(wpool_pool:worker_name(failed_start, 1)),
        undefined = whereis(failed_start),
        true = is_process_alive(Dummy)
    after
        Dummy ! finish
    end.

map_strategy(_Config) ->
    Opts = (options(normal))#{
        strategy => #{
            strategy => simple_one_for_one,
            intensity => 5,
            period => 60
        }
    },
    {ok, _} = wpool:start_sup_pool(map_strategy, Opts),
    [_, _, _] = worker_pids(map_strategy),
    pong = wpool:call(map_strategy, ping),
    ok = wpool:stop_sup_pool(map_strategy).

single_worker(_Config) ->
    {ok, _} = wpool:start_sup_pool(single_worker, (options(normal))#{workers => 1}),
    [_] = worker_pids(single_worker),
    ok = wpool:stop_sup_pool(single_worker).

compatible_shutdown(_Config) ->
    Strategies = [
        undefined,
        {one_for_one, 5, 60},
        {one_for_all, 5, 60},
        {rest_for_one, 5, 60},
        #{strategy => one_for_one},
        #{strategy => one_for_all},
        #{strategy => rest_for_one},
        {simple_one_for_one, 5, 60},
        #{strategy => simple_one_for_one}
    ],
    lists:foreach(fun check_shutdown/1, Strategies).

check_shutdown(Strategy) ->
    Base = #{workers => 1},
    Options =
        case Strategy of
            undefined -> Base;
            _ -> Base#{strategy => Strategy}
        end,
    {ok, Pool} = wpool:start_sup_pool(compatible_shutdown, Options),
    {ok, #{shutdown := 2000}} = supervisor:get_childspec(wpool_sup, Pool),
    ok = wpool:stop_sup_pool(compatible_shutdown),
    false = lists:keymember(Pool, 2, supervisor:which_children(wpool_sup)).

legacy_pools_parallel(_Config) ->
    Opts = maps:remove(strategy, (options(block))#{workers => 1}),
    application_shutdown([legacy_pool_one, legacy_pool_two], Opts, 0).

async_pools_parallel(_Config) ->
    application_shutdown([async_pool_one, async_pool_two], options(block), 0).

application_shutdown(Names, Opts, Delay) ->
    lists:foreach(
        fun(Name) ->
            {ok, _} = wpool:start_sup_pool(Name, Opts),
            ok
        end,
        Names
    ),
    Workers = lists:append([worker_pids(Name) || Name <:- Names]),
    Owner = self(),
    spawn(fun() -> Owner ! {application_stopped, wpool:stop()} end),
    try
        Entered = [
            receive
                {terminating, P} -> P
            after 1000 -> ct:fail(serial_pool_shutdown)
            end
         || _ <:- Workers
        ],
        true = lists:sort(Workers) =:= lists:sort(Entered),
        timer:sleep(Delay),
        true = lists:all(fun is_process_alive/1, Workers)
    after
        [P ! finish || P <:- Workers],
        receive
            {application_stopped, ok} -> ok
        after 10000 -> ct:fail(application_shutdown_timeout)
        end,
        ok = wpool:start()
    end.

supervisor_failure(_Config) ->
    AppSup = whereis(wpool_sup),
    Ref = monitor(process, AppSup),
    ok = gen_server:stop(wpool_sup, shutdown, infinity),
    receive
        {'DOWN', Ref, process, AppSup, shutdown} -> ok
    after 3000 -> ct:fail(supervisor_was_restarted)
    end,
    await(fun() -> not lists:keymember(worker_pool, 1, application:which_applications()) end),
    undefined = whereis(wpool_sup),
    ok = wpool:start().

legacy_workers_serial(_Config) ->
    Opts = maps:remove(strategy, options(block)),
    {ok, _} = wpool:start_sup_pool(legacy_workers_serial, Opts),
    Workers = worker_pids(legacy_workers_serial),
    Owner = self(),
    spawn(fun() -> Owner ! {legacy_stopped, wpool:stop_sup_pool(legacy_workers_serial)} end),
    try
        lists:foreach(
            fun(_) ->
                Pid =
                    receive
                        {terminating, P} -> P
                    after 1000 -> ct:fail(worker_not_stopping)
                    end,
                receive
                    {terminating, _} -> ct:fail(parallel_legacy_workers)
                after 50 -> ok
                end,
                Pid ! finish
            end,
            Workers
        ),
        receive
            {legacy_stopped, ok} -> ok
        after 3000 -> ct:fail(pool_not_stopped)
        end
    after
        [P ! finish || P <:- Workers]
    end.

pool_restart(_Config) ->
    lists:foreach(fun restart_pool/1, [maps:remove(strategy, options(normal)), options(normal)]).

restart_pool(Opts) ->
    {ok, OldPool} = wpool:start_sup_pool(pool_restart, Opts),
    OldWorkers = worker_pids(pool_restart),
    ok = gen_server:stop(OldPool, shutdown, infinity),
    await(fun() ->
        NewPool = whereis(pool_restart),
        is_pid(NewPool) andalso NewPool =/= OldPool andalso
            workers_replaced(pool_restart, OldWorkers)
    end),
    pong = wpool:call(pool_restart, ping),
    ok = wpool:stop_sup_pool(pool_restart).

standalone_pool(_Config) ->
    {ok, Pool} = wpool:start_pool(standalone_pool, options(normal)),
    Ref = monitor(process, Pool),
    Workers = worker_pids(standalone_pool),
    pong = wpool:call(standalone_pool, ping),
    true = wpool:stop_pool(standalone_pool),
    receive
        {'DOWN', Ref, process, Pool, normal} -> ok
    after 3000 -> ct:fail(pool_not_stopped)
    end,
    true = lists:all(fun(P) -> not is_process_alive(P) end, Workers).

original_supervision_tree(_Config) ->
    {ok,
        {{simple_one_for_one, 5, 60}, [
            {wpool_pool, {wpool_pool, start_link, []}, permanent, 2000, supervisor, dynamic}
        ]}} = wpool_sup:init(noargs),
    undefined = whereis(wpool_app_sup),
    undefined = whereis(wpool_async_sup),
    {ok, Pool} = wpool:start_sup_pool(original_supervision_tree, #{workers => 1}),
    [{undefined, Pool, supervisor, dynamic}] = supervisor:which_children(wpool_sup),
    ok = wpool:stop_sup_pool(original_supervision_tree).

workers_replaced(Name, OldWorkers) ->
    Workers = worker_pids(Name),
    length(Workers) =:= length(OldWorkers) andalso
        lists:all(fun(P) -> not lists:member(P, OldWorkers) end, Workers).

worker_pids(Name) ->
    [P || Worker <:- wpool_pool:get_workers(Name), P <:- [whereis(Worker)], is_pid(P)].

await(Fun) ->
    await(Fun, 100).

await(_Fun, 0) ->
    ct:fail(restart_timeout);
await(Fun, Attempts) ->
    Ready =
        try
            Fun()
        catch
            exit:no_workers -> false
        end,
    case Ready of
        true ->
            ok;
        false ->
            timer:sleep(20),
            await(Fun, Attempts - 1)
    end.

init({supervisor, ChildSpec}) ->
    {ok, {{one_for_one, 0, 60}, [ChildSpec]}};
init(State) ->
    process_flag(trap_exit, true),
    {ok, State}.

handle_call(ping, _From, State) ->
    {reply, pong, State}.

terminate(_Reason, {Owner, block}) ->
    Owner ! {terminating, self()},
    receive
        finish -> ok
    after 10000 -> ok
    end;
terminate(_Reason, {_Owner, normal}) ->
    ok.
