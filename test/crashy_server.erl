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
-module(crashy_server).

-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2,
         handle_info/2]).

-dialyzer([no_behaviours]).

-type from() :: {pid(), reference()}.

-export_type([from/0]).

%%%===================================================================
%%% callbacks
%%%===================================================================
-spec init(Something) -> Something.
init(Something) ->
    {ok, Something}.

-spec terminate(Any, term()) -> Any.
terminate(Reason, _State) ->
    Reason.

-spec code_change(string(), State, any()) -> {ok, State}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec handle_info(timeout | Info, term()) -> {noreply, timeout} | Info.
handle_info(timeout, _State) ->
    {noreply, timeout};
handle_info(Info, _State) ->
    Info.

-spec handle_cast(Cast, term()) -> Cast.
handle_cast(crash, _State) ->
    error(crash_requested);
handle_cast(Cast, _State) ->
    Cast.

-spec handle_call(state | Call, from(), State) -> {reply, State, State} | Call.
handle_call(state, _From, State) ->
    {reply, State, State};
handle_call(crash, _From, _State) ->
    error(crash_requested);
handle_call(Call, _From, State) ->
    {reply, Call, State}.
