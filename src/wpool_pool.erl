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
%% @doc A pool of workers. If you want to put it in your supervisor tree, remember it's a supervisor.
-module(wpool_pool).
-author('elbrujohalcon@inaka.net').

-behaviour(supervisor).

-record(wpool, {name :: wpool:name(),
                size :: pos_integer(),
                next :: pos_integer(),
                opts :: [wpool:option()]}).

%% API
-export([start_link/2, create_table/0]).
-export([best_worker/1, random_worker/1, next_worker/1]).
-export([stats/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================
%% @doc Creates the ets table that will hold the information about currently active pools
-spec create_table() -> ok.
create_table() ->
    ?MODULE = ets:new(?MODULE, [public, named_table, set, {read_concurrency, true}, {keypos, #wpool.name}]),
    ok.

%% @doc Starts a supervisor with several {@link wpool_process}es as its children
-spec start_link(wpool:name(), [wpool:option()]) -> {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(Name, Options) -> supervisor:start_link({local, Name}, ?MODULE, {Name, Options}).

%% @doc Picks the worker with the smaller queue of messages.
%%      Based on [http://lethain.com/load-balancing-across-erlang-process-groups/]
%% @throws no_workers
-spec best_worker(wpool:name()) -> pid().
best_worker(Sup) ->
    case find_wpool(Sup) of
        undefined -> throw(no_workers);
        Wpool -> min_message_queue(Wpool)
    end.

%% @doc Picks a random worker
%% @throws no_workers
-spec random_worker(wpool:name()) -> pid().
random_worker(Sup) ->
    case wpool_size(Sup) of
        undefined -> throw(no_workers);
        Wpool_Size -> worker_name(Sup, random:uniform(Wpool_Size))
    end.

%% @doc Picks the next worker in a round robin fashion
%% @throws no_workers
-spec next_worker(wpool:name()) -> pid().
next_worker(Sup) ->
    case move_wpool(Sup) of
        undefined -> throw(no_workers);
        Next -> worker_name(Sup, Next)
    end.

%% @doc Retrieves a snapshot of the pool stats
%% @throws no_workers
-spec stats(wpool:name()) -> wpool:stats().
stats(Sup) ->
    case find_wpool(Sup) of
        undefined -> throw(no_workers);
        Wpool ->
            {Total, WorkerStats} =
                lists:foldl(
                    fun(N, {T, L}) ->
                        Worker = erlang:whereis(worker_name(Sup, N)),
                        [{message_queue_len, MQL} = MQLT, Memory, Function, Location, {dictionary, Dictionary}] =
                            erlang:process_info(Worker, [message_queue_len, memory, current_function, current_location, dictionary]),
                        WS =
                            case {Function, proplists:get_value(wpool_task, Dictionary)} of
                                {{current_function, {gen_server, loop, 6}}, undefined} -> [MQLT, Memory];
                                {{current_function, {erlang, hibernate, _}}, undefined} -> [MQLT, Memory];
                                {_, undefined} -> [MQLT, Memory, Function, Location];
                                {_, {_TaskId, Started, Task}} ->
                                    [MQLT, Memory, Function, Location,
                                     {task, Task},
                                     {runtime, calendar:datetime_to_gregorian_seconds(calendar:universal_time()) - Started}]
                            end,
                        {T + MQL, [{N, WS} | L]}
                    end, {0, []}, lists:seq(1, Wpool#wpool.size)),
            [{pool,                     Sup},
             {supervisor,               erlang:whereis(Sup)},
             {options,                  Wpool#wpool.opts},
             {size,                     Wpool#wpool.size},
             {next_worker,              Wpool#wpool.next},
             {total_message_queue_len,  Total},
             {workers,                  WorkerStats}]
    end.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
%% @private
-spec init({wpool:name(), [wpool:option()]}) -> {ok, {{supervisor:strategy(), non_neg_integer(), non_neg_integer()}, [supervisor:child_spec()]}}.
init({Name, Options}) ->
    _ = random:seed(erlang:now()),
    {Worker, InitArgs}  = proplists:get_value(worker, Options, {wpool_worker, start_link, []}),
    Workers             = proplists:get_value(workers, Options, 100),
    Strategy            = proplists:get_value(strategy, Options, {one_for_one, 5, 60}),
    OverrunHandler      = proplists:get_value(overrun_handler, Options, {error_logger, warning_report}),
    TimeChecker         = time_checker_name(Name),
    _Wpool = store_wpool(#wpool{name = Name, size = Workers, next = 1, opts = Options}),
    {ok, {Strategy,
          [{TimeChecker, {wpool_time_checker, start_link, [Name, TimeChecker, OverrunHandler]}, permanent, brutal_kill, worker, [wpool_time_checker]} |
            [{worker_name(Name, I), {wpool_process, start_link, [{local, worker_name(Name, I)}, Worker, InitArgs, [{time_checker, TimeChecker}|Options]]},
              permanent, 5000, worker, [Worker]}
                || I <- lists:seq(1, Workers)]
           ]}}.

%% ===================================================================
%% Private functions
%% ===================================================================
worker_name(Sup, I) -> list_to_atom(?MODULE_STRING ++ [$-|atom_to_list(Sup)] ++ [$-| integer_to_list(I)]).
time_checker_name(Sup) -> list_to_atom(?MODULE_STRING ++ [$-|atom_to_list(Sup)] ++ "-time-checker").

min_message_queue(Wpool) ->
    %% Moving the beginning of the list to some random point to ensure that clients
    %% do not always start asking for process_info to the processes that are most
    %% likely to have bigger message queues
    First = random:uniform(Wpool#wpool.size),
    min_message_queue(0, Wpool#wpool{next = First}, []).
min_message_queue(Size, #wpool{size = Size}, Found) ->
    {_, Worker} = lists:min(Found),
    Worker;
min_message_queue(Checked, Wpool, Found) ->
    Worker = worker_name(Wpool#wpool.name, Wpool#wpool.next),
    case erlang:process_info(erlang:whereis(Worker), message_queue_len) of
        {message_queue_len, 0} -> Worker;
        {message_queue_len, L} ->
            NextWpool = Wpool#wpool{next = (Wpool#wpool.next rem Wpool#wpool.size) + 1},
            min_message_queue(Checked + 1, NextWpool, [{L, Worker} | Found]);
        Error -> throw(Error)
    end.

%% ===================================================================
%% ETS functions
%% ===================================================================
store_wpool(Wpool) ->
    true = ets:insert(?MODULE, Wpool),
    Wpool.

move_wpool(Name) ->
    try
        Wpool_Size = ets:update_counter(?MODULE, Name, {#wpool.size, 0}),
        ets:update_counter(?MODULE, Name, {#wpool.next, 1, Wpool_Size, 1})
    catch
        _:badarg ->
            case build_wpool(Name) of
                undefined -> undefined;
                Wpool -> Wpool#wpool.next
            end
    end.

wpool_size(Name) ->
    try ets:update_counter(?MODULE, Name, {#wpool.size, 0}) of
        Wpool_Size ->
            case erlang:whereis(Name) of
                undefined ->
                    ets:delete(?MODULE, Name),
                    undefined;
                _ ->
                    Wpool_Size
            end
    catch
        _:badarg ->
            case build_wpool(Name) of
                undefined -> undefined;
                Wpool -> Wpool#wpool.size
            end
    end.

find_wpool(Name) ->
    try ets:lookup(?MODULE, Name) of
        [Wpool | _] ->
            case erlang:whereis(Name) of
                undefined ->
                    ets:delete(?MODULE, Name),
                    undefined;
                _ ->
                    Wpool
            end;
        _ -> build_wpool(Name)
    catch
        _:badarg ->
            build_wpool(Name)
    end.

%% @doc We use this function not to report an error if for some reason we've lost the record
%%      on the ets table. This SHOULDN'T be called too many times
build_wpool(Name) ->
    lager:warning("Building a #wpool record for ~p. Something must have failed.", [Name]),
    try supervisor:count_children(Name) of
        Children ->
            case proplists:get_value(active, Children, 0) of
                0 -> undefined;
                Size ->
                    Wpool = #wpool{name = Name, size = Size, next = 1, opts = []},
                    store_wpool(Wpool)
            end
    catch
        _:Error ->
            lager:warning("Wpool ~p not found: ~p", [Name, Error]),
            undefined
    end.