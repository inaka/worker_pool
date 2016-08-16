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
%%% @author Felipe Ripoll
%%% @doc Default instance for {@link wpool_fsm_process}
-module(wpool_fsm_worker).
-author('ferigis@gmail.com').

-behaviour(gen_fsm).

%% api
-export([ sync_send_event/4
        , send_event/4
        , sync_send_all_state_event/4
        , send_all_state_event/4
        ]).

%% gen_fsm states
-export([ common_state/2
        , common_state/3
        ]).

%% gen_fsm callbacks
-export([ init/1
        , terminate/3
        , code_change/4
        , handle_info/3
        , handle_event/3
        , handle_sync_event/4
        ]).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Returns the result of M:F(A) from any of the workers of the pool S
-spec sync_send_event(wpool:name(), module(), atom(), [term()]) -> term().
sync_send_event(S, M, F, A) ->
  case wpool:sync_send_event(S, {M, F, A}) of
    {ok, Result} -> Result;
    {error, Error} -> throw(Error)
  end.

%% @doc Executes M:F(A) in any of the workers of the pool S
-spec send_event(wpool:name(), module(), atom(), [term()]) -> ok.
send_event(S, M, F, A) -> wpool:send_event(S, {M, F, A}).

%% @doc Returns the result of M:F(A) from any of the workers of the pool S
-spec sync_send_all_state_event(wpool:name(), module(), atom(), [term()]) ->
        term().
sync_send_all_state_event(S, M, F, A) ->
  case wpool:sync_send_all_state_event(S, {M, F, A}) of
    {ok, Result} -> Result;
    {error, Error} -> throw(Error)
  end.

%% @doc Executes M:F(A) in any of the workers of the pool S
-spec send_all_state_event(wpool:name(), module(), atom(), [term()]) -> ok.
send_all_state_event(S, M, F, A) -> wpool:send_all_state_event(S, {M, F, A}).

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================

-record(state, {}).
-type state() :: #state{}.

%% @private
-spec init(undefined) -> {ok, common_state, state()}.
init(undefined) -> {ok, common_state, #state{}}.
%% @private
-spec terminate(atom(), atom(), state()) -> ok.
terminate(_Reason, _CurrentState, _State) -> ok.
%% @private
-spec code_change(string(), atom(), StateData, any()) ->
        {ok, common_state, StateData}.
code_change(_OldVsn, _StateName, State, _Extra) -> {ok, common_state, State}.
%% @private
-spec handle_info(any(), atom(), StateData) ->
        {next_state, common_state, StateData}.
handle_info(_Info, _StateName, StateData) ->
  {next_state, common_state, StateData}.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
%% @private
-spec handle_event(term(), atom(), StateData) ->
        {next_state, common_state, StateData}.
handle_event({M, F, A}, StateName, StateData) ->
  try erlang:apply(M, F, A) of
    _ ->
      {next_state, StateName, StateData}
  catch
    _:Error ->
      log_error(M, F, A, Error),
      {next_state, StateName, StateData}
  end;
handle_event(Event, StateName, StateData) ->
  error_logger:error_msg("Invalid event:~p", [Event]),
  {next_state, StateName, StateData}.

%% @private
-spec handle_sync_event(term(), any(), atom(), StateData) ->
  {reply, term(), atom(), StateData}.
handle_sync_event({M, F, A}, _From, StateName, StateData) ->
  try erlang:apply(M, F, A) of
    R ->
      {reply, {ok, R}, StateName, StateData}
  catch
    _:Error ->
      log_error(M, F, A, Error),
      {reply, {error, Error}, StateName, StateData}
  end;
handle_sync_event(Event, _From, StateName, StateData) ->
  error_logger:error_msg("Invalid event:~p", [Event]),
  {reply, {error, invalid_request}, StateName, StateData}.

%%%===================================================================
%%% FSM States
%%%===================================================================
%% @private
-spec common_state(term(), term()) -> {next_state, common_state, term()}.
common_state(timeout, StateData) -> {next_state, common_state, StateData};
common_state(Msg, StateData) -> handle_event(Msg, common_state, StateData).

%% @private
-spec common_state(term(), term(), term()) ->
        {reply, term(), common_state, term()}.
common_state(stop, _From, StateData) ->
  {stop, normal, ok, StateData};
common_state(stop_without_reply, From, StateData) ->
  gen_fsm:reply(From, ok),
  {stop, normal, StateData};
common_state({timeout, Timeout}, _From, StateData) ->
  {reply, ok,  common_state, StateData, Timeout};
common_state(next_state, From, StateData) ->
  gen_fsm:reply(From, ok),
  {next_state, common_state, StateData};
common_state({next_state, Timeout}, From, StateData) ->
  gen_fsm:reply(From, ok),
  {next_state, common_state, StateData, Timeout};
common_state(Msg, From, StateData) ->
  handle_sync_event(Msg, From, common_state, StateData).

log_error(M, F, A, Error) ->
  error_logger:error_msg(
    "Error on ~p:~p~p >> ~p Backtrace ~p",
    [M, F, A, Error, erlang:get_stacktrace()]).
