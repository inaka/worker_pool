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
-module(wpool_process_SUITE).

-type config() :: [{atom(), term()}].

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([init/1, info/1, cast/1, call/1]).

-spec all() -> [atom()].
all() -> [Fun || {Fun, 1} <- module_info(exports),
				 not lists:member(Fun, [init_per_suite, end_per_suite, module_info])].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
	wpool:start(),
	Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
	wpool:stop(),
	Config.

-spec init_per_testcase(atom(), config()) -> config().
init_per_testcase(_TestCase, Config) ->
	process_flag(trap_exit, true),
	Config.

-spec end_per_testcase(atom(), config()) -> config().
end_per_testcase(_TestCase, Config) ->
	process_flag(trap_exit, false),
	receive after 0 -> ok end,
	Config.

-spec init(config()) -> _.
init(_Config) ->
	{error, can_not_ignore} = wpool_process:start_link({local, ?MODULE}, echo_server, ignore, []),
	{error, ?MODULE} = wpool_process:start_link({local, ?MODULE}, echo_server, {stop, ?MODULE}, []),
	{ok, _Pid} = wpool_process:start_link({local, ?MODULE}, echo_server, {ok, state}, []),
	wpool_process:cast(?MODULE, {stop, normal, state}).

-spec info(config()) -> _.
info(_Config) ->
	{ok, Pid} = wpool_process:start_link({local, ?MODULE}, echo_server, {ok, state}, []),
	Pid ! {noreply, newstate},
	newstate = wpool_process:call(?MODULE, state, 5000),
	Pid ! {noreply, newerstate, 1},
	timer:sleep(1),
	timeout = wpool_process:call(?MODULE, state, 5000),
	Pid ! {stop, normal, state},
	timer:sleep(1000),
	false = erlang:is_process_alive(Pid).

-spec cast(config()) -> _.
cast(_Config) ->
	{ok, Pid} = wpool_process:start_link({local, ?MODULE}, echo_server, {ok, state}, []),
	wpool_process:cast(Pid, {noreply, newstate}),
	newstate = wpool_process:call(?MODULE, state, 5000),
	wpool_process:cast(Pid, {noreply, newerstate, 1}),
	timer:sleep(1),
	timeout = wpool_process:call(?MODULE, state, 5000),
	wpool_process:cast(Pid, {stop, normal, state}),
	timer:sleep(1000),
	false = erlang:is_process_alive(Pid).

-spec call(config()) -> _.
call(_Config) ->
	{ok, Pid} = wpool_process:start_link({local, ?MODULE}, echo_server, {ok, state}, []),
	ok1 = wpool_process:call(Pid, {reply, ok1, newstate}, 5000),
	newstate = wpool_process:call(?MODULE, state, 5000),
	ok2 = wpool_process:call(Pid, {reply, ok2, newerstate, 1}, 5000),
	timer:sleep(1),
	timeout = wpool_process:call(?MODULE, state, 5000),
	ok3 = wpool_process:call(Pid, {stop, normal, ok3, state}, 5000),
	timer:sleep(1000),
	false = erlang:is_process_alive(Pid).