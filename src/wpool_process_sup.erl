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
-module(wpool_process_sup).
-moduledoc """
This is the supervisor that supervises the `gen_server` workers specifically.

It should not be used outside this project.
""".

-include_lib("kernel/include/logger.hrl").

-behaviour(supervisor).

-export([start_link/3]).
-export([init/1]).

-doc false.
-spec start_link(wpool:name(), atom(), wpool:options()) -> supervisor:startlink_ret().
start_link(Parent, Name, Options) ->
    case supervisor:start_link({local, Name}, ?MODULE, {Parent, Options}) of
        {ok, Sup} = Started ->
            case simple_one_for_one(Options) of
                true -> start_workers(Sup, Parent, Options);
                false -> Started
            end;
        Error ->
            Error
    end.

simple_one_for_one(Options) ->
    case maps:get(strategy, Options, {one_for_one, 5, 60}) of
        {simple_one_for_one, _, _} -> true;
        #{strategy := simple_one_for_one} -> true;
        _ -> false
    end.

start_workers(Sup, Parent, Options) ->
    Workers = maps:get(workers, Options, 100),
    case start_workers(Sup, Parent, Options, lists:seq(1, Workers)) of
        ok ->
            {ok, Sup};
        {error, _} = Error ->
            unlink(Sup),
            ok = gen_server:stop(Sup, shutdown, infinity),
            Error
    end.

start_workers(_Sup, _Parent, _Options, []) ->
    ok;
start_workers(Sup, Parent, Options, [I | Rest]) ->
    {Worker, InitArgs} = maps:get(worker, Options, {wpool_worker, undefined}),
    Args = [wpool_pool:worker_name(Parent, I), Worker, InitArgs, Options],
    case supervisor:start_child(Sup, Args) of
        {ok, Pid} when is_pid(Pid) ->
            start_workers(Sup, Parent, Options, Rest);
        Other ->
            {error, {failed_to_start_child, wpool_pool:worker_name(Parent, I), Other}}
    end.

-doc false.
-spec init({wpool:name(), wpool:options()}) ->
    {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Name, Options}) ->
    Workers = maps:get(workers, Options, 100),
    Strategy = maps:get(strategy, Options, {one_for_one, 5, 60}),
    WorkerShutdown = maps:get(worker_shutdown, Options, 5000),
    {Worker, InitArgs} = maps:get(worker, Options, {wpool_worker, undefined}),
    maybe_add_event_handler(Options),
    WorkerSpec = #{
        id => wpool_process,
        start => {wpool_process, start_link, []},
        restart => permanent,
        shutdown => WorkerShutdown,
        type => worker,
        modules => [Worker]
    },
    Specs =
        case simple_one_for_one(Options) of
            true ->
                [WorkerSpec];
            false ->
                [
                    WorkerSpec#{
                        id => wpool_pool:worker_name(Name, I),
                        start =>
                            {wpool_process, start_link, [
                                wpool_pool:worker_name(Name, I), Worker, InitArgs, Options
                            ]}
                    }
                 || I <:- lists:seq(1, Workers)
                ]
        end,
    {ok, {Strategy, Specs}}.

maybe_add_event_handler(Options) ->
    case maps:get(event_manager, Options, undefined) of
        undefined ->
            ok;
        EventMgr ->
            lists:foreach(
                fun(M) -> add_initial_callback(EventMgr, M) end,
                maps:get(callbacks, Options, [])
            )
    end.

add_initial_callback(EventManager, Module) ->
    case wpool_process_callbacks:add_callback_module(EventManager, Module) of
        ok ->
            ok;
        Other ->
            logger:warning(
                #{
                    what => "The callback module could not be loaded",
                    module => Module,
                    reason => Other
                },
                ?LOCATION
            )
    end.
