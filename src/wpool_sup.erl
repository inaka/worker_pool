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
%%% @private
-module(wpool_sup).

-include_lib("kernel/include/logger.hrl").

-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_pool/2, stop_pool/1]).

%%-------------------------------------------------------------------
%% PUBLIC API
%%-------------------------------------------------------------------
%% @doc Starts the supervisor
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Starts a new pool
-spec start_pool(wpool:name(), wpool:options()) -> supervisor:startchild_ret().
start_pool(Name, Options) ->
    supervisor:start_child(?MODULE, [Name, Options]).

%% @doc Stops a pool
-spec stop_pool(wpool:name()) -> ok.
stop_pool(Name) ->
    case erlang:whereis(Name) of
        undefined ->
            logger:warning(#{what => "Could not stop pool",
                             reason => "It was not running",
                             pool => Name},
                           ?LOCATION),
            ok;
        Pid ->
            ok = supervisor:terminate_child(?MODULE, Pid)
    end.

%%----------------------------------------------------------------------
%% Supervisor behaviour callbacks
%%----------------------------------------------------------------------
-spec init([]) -> {ok, {{simple_one_for_one, 5, 60}, [supervisor:child_spec()]}}.
init([]) ->
    {ok,
     {{simple_one_for_one, 5, 60},
      [{wpool_pool, {wpool_pool, start_link, []}, permanent, 2000, supervisor, dynamic}]}}.
