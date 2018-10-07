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

%% @hidden
-module(wpool_worker_SUITE).

-type config() :: [{atom(), term()}].

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([call/1, cast/1, complete_coverage/1]).
-export([ok/0, error/0]).

-spec all() -> [atom()].
all() ->
  [Fun || {Fun, 1} <- module_info(exports),
          not lists:member(Fun, [init_per_suite, end_per_suite, module_info])].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  ok = wpool:start(),
  Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
  wpool:stop(),
  Config.

-spec ok() -> ?MODULE.
ok() -> ?MODULE.

-spec error() -> no_return().
error() -> exit(?MODULE).

-spec call(config()) -> {comment, []}.
call(_Config) ->
  start_pool(),
  ?MODULE = wpool_worker:call(?MODULE, ?MODULE, ok, []),
  try wpool_worker:call(?MODULE, ?MODULE, error, []) of
    R -> no_result = R
  catch
    exit:?MODULE -> ok
  end,
  {error, invalid_request} = wpool:call(?MODULE, error),
  ok = wpool:stop_sup_pool(?MODULE),

  {comment, []}.

-spec cast(config()) -> {comment, []}.
cast(_Config) ->
  start_pool(),
  ok = wpool_worker:cast(?MODULE, ?MODULE, ok, []),
  ok = wpool_worker:cast(?MODULE, ?MODULE, error, []),
  ok = wpool:cast(?MODULE, x),
  ok = wpool_worker:cast(?MODULE, erlang, send, [self(), {a, message}]),
  receive
    {a, message} -> ok
  after 1000 ->
    ct:fail("Timeout while waiting for cast response")
  end,
  ok = wpool:stop_sup_pool(?MODULE),

  {comment, []}.

-spec complete_coverage(config()) -> {comment, []}.
complete_coverage(_Config) ->
  start_pool(),
  {ok, AWorker} = wpool:call(?MODULE, {erlang, self, []}),
  true = is_process_alive(AWorker),
  AWorker ! info,

  true = is_process_alive(AWorker),

  {ok, {state}} = wpool_worker:code_change("oldvsn", {state}, extra),

  ok = wpool_worker:terminate(reason, {state}),

  {comment, []}.

start_pool() ->
  {ok, _Pid} =
    wpool:start_sup_pool(
      ?MODULE, [{workers, 1}, {worker, {wpool_worker, undefined}}]),
  started.
