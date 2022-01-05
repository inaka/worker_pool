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
%%% @author Felipe Ripoll <ferigis@gmail.com>
%%% @doc Common functions for wpool_process and other modules.
-module(wpool_utils).

-author('ferigis@gmail.com').

%% API
-export([task_init/2, task_end/1, add_defaults/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Marks Task as started in this worker
-spec task_init(term(), #{overrun_warning := timeout(), _ => _}) ->
                   undefined | reference().
task_init(Task, #{overrun_warning := infinity}) ->
    Time = erlang:system_time(second),
    erlang:put(wpool_task, {undefined, Time, Task}),
    undefined;
task_init(Task,
          #{overrun_warning := OverrunTime,
            time_checker := TimeChecker,
            max_overrun_warnings := MaxWarnings}) ->
    TaskId = erlang:make_ref(),
    Time = erlang:system_time(second),
    erlang:put(wpool_task, {TaskId, Time, Task}),
    erlang:send_after(OverrunTime,
                      TimeChecker,
                      {check, self(), TaskId, OverrunTime, MaxWarnings}).

%% @doc Removes the current task from the worker
-spec task_end(undefined | reference()) -> ok.
task_end(undefined) ->
    erlang:erase(wpool_task);
task_end(TimerRef) ->
    _ = erlang:cancel_timer(TimerRef),
    erlang:erase(wpool_task).

-spec add_defaults([wpool:option()]) -> [wpool:option()].
add_defaults(Opts) ->
    lists:ukeymerge(1, lists:sort(Opts), defaults()).

-spec defaults() -> [wpool:option()].
defaults() ->
    [{max_overrun_warnings, infinity},
     {overrun_handler, {error_logger, warning_report}},
     {overrun_warning, infinity},
     {queue_type, fifo},
     {worker_opt, []},
     {workers, 100}].
