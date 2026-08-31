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
-module(wpool_worker).
-moduledoc """
Default instance for `wpool_process`.

It is a module that implements a very simple RPC-like interface.
""".
-include_lib("kernel/include/logger.hrl").

-behaviour(gen_server).

-export([call/4, cast/4]).
-export([init/1, handle_call/3, handle_cast/2]).

-record(state, {}).

-opaque state() :: #state{}.

-export_type([state/0]).

-doc #{group => "API Functions"}.
-doc """
Returns the result of `M:F(A).` from any of the workers of the pool `S`.
""".
-spec call(wpool:name(), module(), atom(), [term()]) -> term().
call(S, M, F, A) ->
    case wpool:call(S, {M, F, A}) of
        {ok, Result} ->
            Result;
        {error, Error} ->
            exit(Error)
    end.

-doc """
Executes `M:F(A).` in any of the workers of the pool `S`.
""".
-spec cast(wpool:name(), module(), atom(), [term()]) -> ok.
cast(S, M, F, A) ->
    wpool:cast(S, {M, F, A}).

-doc false.
-spec init(undefined) -> {ok, state()}.
init(undefined) ->
    {ok, #state{}}.

-doc false.
-spec handle_cast(term(), state()) -> {noreply, state(), hibernate}.
handle_cast({M, F, A}, State) ->
    try erlang:apply(M, F, A) of
        _ ->
            {noreply, State, hibernate}
    catch
        Class:Reason:Stacktrace ->
            log_error(M, F, A, Class, Reason, Stacktrace),
            {noreply, State, hibernate}
    end;
handle_cast(Cast, State) ->
    logger:error(
        #{
            what => "Invalid cast",
            cast => Cast,
            worker => self()
        },
        ?LOCATION
    ),
    {noreply, State, hibernate}.

-doc false.
-spec handle_call(term(), gen_server:from(), state()) ->
    {reply, {ok, term()} | {error, term()}, state(), hibernate}.
handle_call({M, F, A}, _From, State) ->
    try erlang:apply(M, F, A) of
        R ->
            {reply, {ok, R}, State, hibernate}
    catch
        Class:Reason:Stacktrace ->
            log_error(M, F, A, Class, Reason, Stacktrace),
            {reply, {error, Reason}, State, hibernate}
    end;
handle_call(Call, From, State) ->
    logger:error(
        #{
            what => "Invalid call",
            call => Call,
            from => From,
            worker => self()
        },
        ?LOCATION
    ),
    {reply, {error, invalid_request}, State, hibernate}.

log_error(M, F, A, Class, Reason, Stacktrace) ->
    logger:error(
        #{
            what => "Reason on ~p:~p~p >> ~p Backtrace ~p",
            mfa => {M, F, A},
            class => Class,
            reason => Reason,
            stacktrace => Stacktrace
        },
        ?LOCATION
    ).
