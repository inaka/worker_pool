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
%%% @doc This is the supervisor that supervises the `gen_server' workers specifically.
-module(wpool_process_sup).

-include_lib("kernel/include/logger.hrl").

-behaviour(supervisor).

%% API
-export([start_link/3]).
%% Supervisor callbacks
-export([init/1]).

%% @private
-spec start_link(wpool:name(), atom(), wpool:options()) -> supervisor:startlink_ret().
start_link(Parent, Name, Options) ->
    supervisor:start_link({local, Name}, ?MODULE, {Parent, Options}).

%% @private
-spec init({wpool:name(), wpool:options()}) ->
              {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Name, Options}) ->
    Workers = maps:get(workers, Options, 100),
    Strategy = maps:get(strategy, Options, {one_for_one, 5, 60}),
    WorkerShutdown = maps:get(worker_shutdown, Options, 5000),
    {Worker, InitArgs} = maps:get(worker, Options, {wpool_worker, undefined}),
    maybe_add_event_handler(Options),
    WorkerSpecs =
        [#{id => wpool_pool:worker_name(Name, I),
           start =>
               {wpool_process,
                start_link,
                [wpool_pool:worker_name(Name, I), Worker, InitArgs, Options]},
           restart => permanent,
           shutdown => WorkerShutdown,
           type => worker,
           modules => [Worker]}
         || I <- lists:seq(1, Workers)],
    {ok, {Strategy, WorkerSpecs}}.

maybe_add_event_handler(Options) ->
    case maps:get(event_manager, Options, undefined) of
        undefined ->
            ok;
        EventMgr ->
            lists:foreach(fun(M) -> add_initial_callback(EventMgr, M) end,
                          maps:get(callbacks, Options, []))
    end.

add_initial_callback(EventManager, Module) ->
    case wpool_process_callbacks:add_callback_module(EventManager, Module) of
        ok ->
            ok;
        Other ->
            logger:warning(#{what => "The callback module could not be loaded",
                             module => Module,
                             reason => Other},
                           ?LOCATION)
    end.
