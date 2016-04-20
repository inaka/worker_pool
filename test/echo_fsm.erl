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
% specific language gozverning permissions and limitations
% under the License.
%% @doc a gen_fsm built to test wpool_fsm_process
-module(echo_fsm).
-author("ferigis@gmail.com").

-export([init/1, handle_info/3, handle_event/3,
  handle_sync_event/4, terminate/3, code_change/4]).
-export([state_one/2, state_two/2]). %% states
-export([state_one/3, state_two/3]). %% states


%% Gen FSM callbacks
-spec init(Something) -> Something.
init(Something) ->
  Something.

-spec state_one(Event, any()) -> Event.
state_one(Event, _LoopData) ->
  Event.

-spec state_one(Event, any(), any()) -> Event.
state_one(Event, _From, _LoopData) ->
  Event.

-spec state_two(Event, any()) -> Event.
state_two(Event, _LoopData) ->
  Event.

-spec state_two(Event, any(), any()) -> Event.
state_two(Event, _From, _LoopData) ->
  Event.

-spec handle_info(Info, any(), any()) -> Info.
handle_info(Info, _StateName, _StateData) ->
  Info.

-spec handle_event(Event, any(), any()) -> Event.
handle_event(Event, _StateName, _StateData) ->
  Event.

-spec handle_sync_event(any(), any(), any(), any()) -> any().
handle_sync_event(state, _From, StateName, StateData) ->
  {reply, StateData, StateName, StateData};
handle_sync_event(Event, _From, _StateName, _StateData) ->
  Event.

-spec terminate(any(), any(), any()) -> ok.
terminate(_Reason, _StateName, _StateData) ->
  ok.

-spec code_change(any(), any(), any(), any()) -> {ok, state_one, term()}.
code_change(_OldVsn, _StateName, StateData, _Extra) ->
  {ok, state_one, StateData}.
