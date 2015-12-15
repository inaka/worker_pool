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
-module(wpool_fsm_process_SUITE).

-type config() :: [{atom(), term()}].

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([init/1, init_timeout/1, info/1,
         async_states/1, sync_states/1]).

-spec all() -> [atom()].
all() -> [Fun || {Fun, 1} <- module_info(exports),
         not lists:member(Fun, [init_per_suite, end_per_suite, module_info])].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  ok = wpool:start(),
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
  {error, can_not_ignore} =
    wpool_fsm_process:start_link(?MODULE, echo_fsm, ignore, []),
  {error, ?MODULE} =
    wpool_fsm_process:start_link(?MODULE, echo_fsm, {stop, ?MODULE}, []),
  {ok, _Pid} = wpool_fsm_process:start_link(?MODULE,
                                            echo_fsm,
                                            {ok, state_one, []},
                                            []).

-spec init_timeout(config()) -> _.
init_timeout(_Config) ->
  {ok, Pid} =
        wpool_fsm_process:start_link(?MODULE,
                                    echo_fsm,
                                    {ok, state_one, [], 0},
                                    []),
  timer:sleep(1),
  false = erlang:is_process_alive(Pid).

-spec info(config()) -> _.
info(_Config) ->
  {ok, Pid} = wpool_fsm_process:start_link(?MODULE,
                                          echo_fsm,
                                          {ok, state_one, []},
                                          []),
  Pid ! {next_state, state_two, newstate},
  newstate = wpool_fsm_process:sync_send_all_state_event(?MODULE, state, 5000),
  Pid ! {next_state, state_three, newstate, 0},
  timer:sleep(1),
  false = erlang:is_process_alive(Pid).

-spec async_states(config()) -> _.
async_states(_Config) ->
  {ok, Pid} = wpool_fsm_process:start_link(?MODULE,
                                          echo_fsm,
                                          {ok, state_one, []},
                                          []),
  wpool_fsm_process:send_event(Pid, {next_state, state_two, newstate}),
  newstate = wpool_fsm_process:sync_send_all_state_event(?MODULE, state, 5000),
  wpool_fsm_process:send_event(Pid, {next_state, state_one, newerstate, 0}),
  timer:sleep(1),
  false = erlang:is_process_alive(Pid).

-spec sync_states(config()) -> _.
sync_states(_Config) ->
  {ok, Pid} = wpool_fsm_process:start_link(?MODULE,
                                          echo_fsm,
                                          {ok, state_one, []},
                                          []),
  ok1 = wpool_fsm_process:sync_send_event(Pid,
                                          {reply, ok1, state_two, newstate},
                                          5000),
  newstate = wpool_fsm_process:sync_send_all_state_event(?MODULE, state, 5000),
  ok2 = wpool_fsm_process:sync_send_event(Pid,
                                        {reply, ok2, state_one, newerstate, 0},
                                        5000),
  timer:sleep(1),
  false = erlang:is_process_alive(Pid).
