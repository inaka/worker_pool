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
%%% @hidden
-module(wpool_process_sup).
-author('elbrujohalcon@inaka.net').

-behaviour(supervisor).

%% API
-export([start_link/3]).

%% Supervisor callbacks
-export([init/1]).

%% @private
-spec start_link(wpool:name(), atom(), [wpool:option()]) -> {ok, pid()}.
start_link(Parent, Name, Options) ->
  supervisor:start_link({local, Name}, ?MODULE, {Parent, Options}).

%% @private
-spec init({wpool:name(), [wpool:option()]}) ->
        {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Name, Options}) ->
  Workers = proplists:get_value(workers, Options, 100),
  Strategy = proplists:get_value(strategy, Options, {one_for_one, 5, 60}),
  maybe_add_event_handler(Options),
  {WorkerType, Worker, InitArgs} =
    case proplists:get_value(worker_type, Options, gen_server) of
      gen_server ->
        {W, IA} =
          proplists:get_value(worker, Options, {wpool_worker, undefined}),
        {wpool_process, W, IA}
        %% We'll eventually add more types (like gen_statem),
        %% that's why this case remains
    end,
  WorkerShutdown = proplists:get_value(worker_shutdown, Options, 5000),
  WorkerSpecs =
    [ { wpool_pool:worker_name(Name, I)
      , { WorkerType
        , start_link
        , [wpool_pool:worker_name(Name, I), Worker, InitArgs, Options]
        }
      , permanent
      , WorkerShutdown
      , worker
      , [Worker]
      } || I <- lists:seq(1, Workers)],
  {ok, {Strategy, WorkerSpecs}}.

maybe_add_event_handler(Options) ->
  case proplists:get_value(event_manager, Options, undefined) of
    undefined ->
      ok;
    EventMgr ->
      lists:foreach(fun(M) -> add_initial_callback(EventMgr, M) end,
                    proplists:get_value(callbacks, Options, []))
  end.

add_initial_callback(EventManager, Module) ->
  case wpool_process_callbacks:add_callback_module(EventManager, Module) of
    ok ->
      ok;
    Other ->
      error_logger:warning_msg("The callback module:~p could not be loaded, reason:~p",
                               [Module, Other])
  end.
