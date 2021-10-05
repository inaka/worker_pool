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
-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2,
         handle_continue/2, format_status/2]).

-dialyzer([no_behaviours]).

%%%===================================================================
%%% callbacks
%%%===================================================================
-spec init(Something) -> Something.
init(Something) ->
    Something.

-spec terminate(Any, term()) -> Any.
terminate(Reason, _State) ->
    Reason.

-spec code_change(string(), State, any()) -> any() | {ok, State}.
code_change(_OldVsn, _State, Extra) ->
    Extra.

-spec handle_info(timeout | Info, term()) -> {noreply, timeout} | Info.
handle_info(timeout, _State) ->
    {noreply, timeout};
handle_info(Info, _State) ->
    Info.

-spec handle_cast(Cast, term()) -> Cast.
handle_cast(Cast, _State) ->
    Cast.

-type from() :: {pid(), reference()}.

-spec handle_call(Call, from(), term()) -> Call.
handle_call(Call, _From, _State) ->
    Call.

-spec handle_continue(Continue, term()) -> Continue.
handle_continue(Continue, _State) ->
    Continue.

-spec format_status(normal | terminate, [[{_, _}] | State, ...]) ->
                       {formatted_state, State}.
format_status(_, [_PDict, State]) ->
    {formatted_state, State}.
