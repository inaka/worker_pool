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
-module(echo_server).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%%%===================================================================
%%% callbacks
%%%===================================================================

-spec init(term()) -> term().
init(Something) -> Something.

-spec terminate(atom(), term()) -> atom().
terminate(Reason, _State) -> Reason.

-spec code_change(string(), term(), any()) -> {ok, term()}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

-spec handle_info(term(), term()) -> term().
handle_info(timeout, _State) -> {noreply, timeout};
handle_info(Info, _State) -> Info.

-spec handle_cast(term(), term()) -> term().
handle_cast(Cast, _State) -> Cast.

-type from() :: {pid(), reference()}.
-spec handle_call(term(), from(), term()) -> term().
handle_call(state, _From, State) -> {reply, State, State};
handle_call(Call, _From, _State) -> Call.