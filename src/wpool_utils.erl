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
%%% @doc Common functions for wpool_process and wpool_fsm_process
%%%      modules.
-module(wpool_utils).
-author('ferigis@gmail.com').

%% API
-export([ task_init/3
        , task_end/1
        , notify_queue_manager/3
        , do_try/1]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Api
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Marks Task as started in this worker
-spec task_init(term(), atom(), infinity | pos_integer()) ->
  undefined | reference().
task_init(Task, _TimeChecker, infinity) ->
  Time = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
  erlang:put(wpool_task, {undefined, Time, Task}),
  undefined;
task_init(Task, TimeChecker, OverrunTime) ->
  TaskId = erlang:make_ref(),
  Time = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
  erlang:put(wpool_task, {TaskId, Time, Task}),
  erlang:send_after(
    OverrunTime, TimeChecker, {check, self(), TaskId, OverrunTime}).

%% @doc Removes the current task from the worker
-spec task_end(undefined | reference()) -> ok.
task_end(undefined) -> erlang:erase(wpool_task);
task_end(TimerRef) ->
  _ = erlang:cancel_timer(TimerRef),
  erlang:erase(wpool_task).

-spec notify_queue_manager(atom(), atom(), list()) -> ok | any().
notify_queue_manager(Function, Name, Options) ->
  case proplists:get_value(queue_manager, Options) of
    undefined -> ok;
    QueueManager -> wpool_queue_manager:Function(QueueManager, Name)
  end.

-spec do_try(fun()) -> any().
do_try(Fun) -> try Fun() catch _:Error -> Error end.
