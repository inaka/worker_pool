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
%%% @hidden
-module(wpool_shutdown).
-author('jay@tigertext.com').

-export([final_task/2]).

%% @doc Final task to execute before shutting down the node.
-spec final_task(wpool:name(), pos_integer()) -> ok.
final_task(Pool_Name, Time_Allowed) ->
  case wpool_queue_manager:trace(Pool_Name, true, Time_Allowed) of
    {error, Error} ->
      error_logger:error_msg("~p failed with ~p", [?MODULE, Error]);
    ok ->
       timer:sleep(Time_Allowed)
  end,
  ok.
