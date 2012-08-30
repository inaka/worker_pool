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
-module(wpool_pool_SUITE).

-type config() :: [{atom(), term()}].

-define(WORKERS, 5).

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([best_worker/1, next_worker/1, random_worker/1]).

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
init_per_testcase(TestCase, Config) ->
	wpool:start_pool(TestCase, [{workers, ?WORKERS}]),
	Config.

-spec end_per_testcase(atom(), config()) -> config().
end_per_testcase(TestCase, Config) ->
	wpool:stop_pool(TestCase),
	Config.

-spec best_worker(config()) -> _.
best_worker(_Config) ->
	Pool = best_worker,
	try wpool:cast(not_a_pool, x, best_worker)
	catch
		_:no_workers -> ok
	end,

	%% Fill up their message queues...
	[wpool:cast(Pool, {timer, sleep, [60000]}, best_worker) || _ <- lists:seq(1, ?WORKERS)],
	timer:sleep(500),
	[0] = sets:to_list(
			sets:from_list(
				[proplists:get_value(message_queue_len, WS)
					|| {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),
	[wpool:cast(Pool, {timer, sleep, [60000]}, best_worker) || _ <- lists:seq(1, ?WORKERS)],
	timer:sleep(500),
	[1] = sets:to_list(
			sets:from_list(
				[proplists:get_value(message_queue_len, WS)
					|| {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])),
	%% Now try best worker once per worker
	[wpool:cast(Pool, {timer, sleep, [60000]}, best_worker) || _ <- lists:seq(1, ?WORKERS)],
	%% The load should be evenly distributed...
	[2] = sets:to_list(
			sets:from_list(
				[proplists:get_value(message_queue_len, WS)
					|| {_, WS} <- proplists:get_value(workers, wpool:stats(Pool))])).

-spec next_worker(config()) -> _.
next_worker(_Config) ->
	Pool = next_worker,

	try wpool:cast(not_a_pool, x, next_worker)
	catch
		_:no_workers -> ok
	end,

	Res0 = [begin
				Stats = wpool:stats(Pool),
				I = proplists:get_value(next_worker, Stats),
				wpool:call(Pool, {erlang, self, []}, next_worker, infinity)
			end || I <- lists:seq(1, ?WORKERS)],
	?WORKERS = sets:size(sets:from_list(Res0)),
	Res0 = [begin
				Stats = wpool:stats(Pool),
				I = proplists:get_value(next_worker, Stats),
				wpool:call(Pool, {erlang, self, []}, next_worker)
			end || I <- lists:seq(1, ?WORKERS)].

-spec random_worker(config()) -> _.
random_worker(_Config) ->
	Pool = random_worker,

	try wpool:cast(not_a_pool, x)
	catch
		_:no_workers -> ok
	end,

	Res0 = [begin
				random:seed({0,0,0}),
				wpool:cast(Pool, {timer, sleep, [100]}),
				wpool:call(Pool, {erlang, self, []})
			end || _ <- lists:seq(1, ?WORKERS)],
	1 = sets:size(sets:from_list(Res0)).