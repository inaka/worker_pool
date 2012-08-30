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
%% @doc Default instance for {@link wpool_process}
-module(wpool_worker).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

%% api
-export([call/4, cast/4]).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Returns the result of M:F(A) from any of the workers of the pool S
-spec call(wpool:name(), module(), atom(), [term()]) -> term().
call(S, M, F, A) ->
  case wpool:call(S, {M,F,A}) of
    {ok, Result} -> Result;
    {error, Error} -> throw(Error)
  end.

%% @doc Executes M:F(A) in any of the workers of the pool S
-spec cast(wpool:name(), module(), atom(), [term()]) -> ok.
cast(S, M, F, A) ->
  wpool:cast(S, {M,F,A}).

%%%===================================================================
%%% init, terminate, code_change, info callbacks
%%%===================================================================

-record(state, {}).

%% @private
-spec init(undefined) -> {ok, #state{}}.
init(undefined) -> {ok, #state{}}.
%% @private
-spec terminate(atom(), #state{}) -> ok.
terminate(_Reason, _State) -> ok.
%% @private
-spec code_change(string(), #state{}, any()) -> {ok, {}}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
%% @private
-spec handle_info(any(), #state{}) -> {noreply, #state{}}.
handle_info(_Info, State) -> {noreply, State}.

%%%===================================================================
%%% real (i.e. interesting) callbacks
%%%===================================================================
%% @private
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({M,F,A}, State) ->
  try erlang:apply(M, F, A) of
    _ ->
      {noreply, State, hibernate}
  catch
    _:Error ->
      lager:error("Error on ~p:~p~p >> ~p Backtrace ~p", [M, F, A, Error, erlang:get_stacktrace()]),
      {noreply, State, hibernate}
  end;
handle_cast(Cast, State) ->
  lager:error("Invalid cast:~p", [Cast]),
  {noreply, State, hibernate}.

-type from() :: {pid(), reference()}.
%% @private
-spec handle_call(term(), from(), #state{}) -> {reply, {ok, term()} | {error, term()}, #state{}}.
handle_call({M,F,A}, _From, State) ->
  try erlang:apply(M, F, A) of
    R ->
      {reply, {ok, R}, State, hibernate}
  catch
    _:Error ->
      lager:error("Error on ~p:~p~p >> ~p Backtrace ~p", [M, F, A, Error, erlang:get_stacktrace()]),
      {reply, {error, Error}, State, hibernate}
  end;
handle_call(Call, _From, State) ->
  lager:error("Invalid call:~p", [Call]),
  {reply, {error, invalid_request}, State, hibernate}.