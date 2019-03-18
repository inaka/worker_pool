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
%% @doc a gen_server built to test wpool_process
-module(sleepy_server).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

%% gen_server callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        ]).

-dialyzer([no_behaviours]).

%%%===================================================================
%%% callbacks
%%%===================================================================
-spec init(pos_integer()) -> {ok, state}.
init(TimeToSleep) ->
    _ = timer:sleep(TimeToSleep),
    {ok, state}.

-spec handle_cast(pos_integer(), State) -> {noreply, State}.
handle_cast(TimeToSleep, State) ->
    _ = timer:sleep(TimeToSleep),
    {noreply, State}.

-type from() :: {pid(), reference()}.
-spec handle_call(pos_integer(), from(), State) -> {reply, ok, State}.
handle_call(TimeToSleep, _From, State) ->
    _ = timer:sleep(TimeToSleep),
    {reply, ok, State}.
