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
%%% @private
-module(wpool_utils).

-export([add_defaults/1]).

%% @doc Adds default parameters to a pool configuration
-spec add_defaults([wpool:option()] | wpool:options()) -> wpool:options().
add_defaults(Opts) when is_map(Opts) ->
    maps:merge(defaults(), Opts);
add_defaults(Opts) when is_list(Opts) ->
    maps:merge(defaults(), maps:from_list(Opts)).

defaults() ->
    #{
        max_overrun_warnings => infinity,
        overrun_handler => {logger, warning},
        overrun_warning => infinity,
        queue_type => fifo,
        worker_opt => [],
        workers => 100
    }.
