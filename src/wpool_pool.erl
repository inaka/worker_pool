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
%%% @author Fernando Benavides <elbrujohalcon@inaka.net>
%%% @doc A pool of workers. If you want to put it in your supervisor tree,
%%%      remember it's a supervisor.
-module(wpool_pool).
-author('elbrujohalcon@inaka.net').

-behaviour(supervisor).

%% API
-export([ start_link/2
        , create_table/0
        ]).
-export([ best_worker/1
        , random_worker/1
        , next_worker/1
        , hash_worker/2
        , next_available_worker/1
        , call_available_worker/3
        , sync_send_event_to_available_worker/3
        , sync_send_all_event_to_available_worker/3
        , time_checker_name/1
        ]).
-export([ cast_to_available_worker/2
        , send_event_to_available_worker/2
        , send_all_event_to_available_worker/2
        ]).
-export([ stats/0
        , stats/1
        ]).
-export([ worker_name/2
        , find_wpool/1
        , all/0
        ]).
-export([ next/2
        , wpool_get/2
        ]).

%% Supervisor callbacks
-export([ init/1
        ]).

-include("wpool.hrl").

-type wpool() :: #wpool{}.
-export_type([wpool/0]).

%% ===================================================================
%% API functions
%% ===================================================================
%% @doc Creates the ets table that will hold the information about active pools
-spec create_table() -> ok.
create_table() ->
  _ = ets:new(
        ?MODULE,
        [public, named_table, set,
         {read_concurrency, true}, {keypos, #wpool.name}]),
  ok.

%% @doc Starts a supervisor with several {@link wpool_process}es as its children
-spec start_link(wpool:name(), [wpool:option()]) ->
        {ok, pid()} | {error, {already_started, pid()} | term()}.
start_link(Name, Options) ->
  supervisor:start_link({local, Name}, ?MODULE, {Name, Options}).

%% @doc Picks the worker with the smaller queue of messages.
%% @throws no_workers
-spec best_worker(wpool:name()) -> atom().
best_worker(Sup) ->
  case find_wpool(Sup) of
    undefined -> throw(no_workers);
    Wpool -> min_message_queue(Wpool)
  end.

%% @doc Picks a random worker
%% @throws no_workers
-spec random_worker(wpool:name()) -> atom().
random_worker(Sup) ->
  case wpool_size(Sup) of
    undefined  -> throw(no_workers);
    WpoolSize ->
      WorkerNumber = rnd(WpoolSize),
      worker_name(Sup, WorkerNumber)
  end.

%% @doc Picks the next worker in a round robin fashion
%% @throws no_workers
-spec next_worker(wpool:name()) -> atom().
next_worker(Sup) ->
  case move_wpool(Sup) of
    undefined -> throw(no_workers);
    Next -> worker_name(Sup, Next)
  end.

%% @doc Picks the first available worker, if any
%% @throws no_workers | no_available_workers
-spec next_available_worker(wpool:name()) -> atom().
next_available_worker(Sup) ->
  case find_wpool(Sup) of
    undefined -> throw(no_workers);
    Wpool ->
      case worker_with_no_task(Wpool) of
        undefined -> throw(no_available_workers);
        Worker -> Worker
      end
  end.

%% @doc Picks the first available worker and sends the call to it.
%%      The timeout provided includes the time it takes to get a worker
%%      and for it to process the call.
%% @throws no_workers | timeout
-spec call_available_worker(wpool:name(), any(), timeout()) -> any().
call_available_worker(Sup, Call, Timeout) ->
  case wpool_queue_manager:call_available_worker(
        queue_manager_name(Sup), Call, Timeout) of
    noproc  -> throw(no_workers);
    timeout -> throw(timeout);
    Result  -> Result
  end.

%% @doc Picks the first available worker and sends the event to it.
%%      The timeout provided includes the time it takes to get a worker
%%      and for it to process the call.
%% @throws no_workers | timeout
-spec sync_send_event_to_available_worker(
        wpool:name(), any(), timeout()) -> any().
sync_send_event_to_available_worker(Sup, Event, Timeout) ->
  case wpool_queue_manager:sync_send_event_to_available_worker(
        queue_manager_name(Sup), Event, Timeout) of
    noproc  -> throw(no_workers);
    timeout -> throw(timeout);
    Result  -> Result
  end.

%% @doc Picks the first available worker and sends the event to it.
%%      The timeout provided includes the time it takes to get a worker
%%      and for it to process the call.
%% @throws no_workers | timeout
-spec sync_send_all_event_to_available_worker(
        wpool:name(), any(), timeout()) -> any().
sync_send_all_event_to_available_worker(Sup, Event, Timeout) ->
  case wpool_queue_manager:sync_send_all_event_to_available_worker(
        queue_manager_name(Sup), Event, Timeout) of
    noproc  -> throw(no_workers);
    timeout -> throw(timeout);
    Result  -> Result
  end.

%% @doc Picks a worker base on a hash result.
%%      <pre>phash2(Term, Range)</pre> returns hash = integer,
%%      0 &lt;= hash &lt; Range so <pre>1</pre> must be added
%% @throws no_workers
-spec hash_worker(wpool:name(), term()) -> atom().
hash_worker(Sup, HashKey) ->
  case wpool_size(Sup) of
    undefined -> throw(no_workers);
    WpoolSize ->
      Index = 1 + erlang:phash2(HashKey, WpoolSize),
      worker_name(Sup, Index)
  end.

%% @doc Casts a message to the first available worker.
%%      Since we can wait forever for a wpool:cast to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the cast when it gets the worker
-spec cast_to_available_worker(wpool:name(), term()) -> ok.
cast_to_available_worker(Sup, Cast) ->
  wpool_queue_manager:cast_to_available_worker(queue_manager_name(Sup), Cast).

%% @doc Sends an event to the first available worker.
%%      Since we can wait forever for a wpool:send_event to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the event when it gets the worker
-spec send_event_to_available_worker(wpool:name(), term()) -> ok.
send_event_to_available_worker(Sup, Event) ->
  wpool_queue_manager:send_event_to_available_worker(
    queue_manager_name(Sup), Event).

%% @doc Sends an event to the first available worker.
%%      Since we can wait forever for a wpool:send_event to be delivered
%%      but we don't want the caller to be blocked, this function
%%      just forwards the event when it gets the worker
-spec send_all_event_to_available_worker(wpool:name(), term()) -> ok.
send_all_event_to_available_worker(Sup, Event) ->
  wpool_queue_manager:send_all_event_to_available_worker(
    queue_manager_name(Sup), Event).

-spec all() -> [wpool:name()].
all() ->
  [Name || #wpool{name = Name} <- ets:tab2list(?MODULE)
         , find_wpool(Name) /= undefined].

%% @doc Retrieves the pool stats for all pools
-spec stats() -> [wpool:stats()].
stats() -> [stats(Sup) || Sup <- all()].

%% @doc Retrieves a snapshot of the pool stats
%% @throws no_workers
-spec stats(wpool:name()) -> wpool:stats().
stats(Sup) ->
  case find_wpool(Sup) of
    undefined -> throw(no_workers);
    Wpool ->
      stats(Wpool, Sup)
  end.

stats(Wpool, Sup) ->
  {Total, WorkerStats} =
    lists:foldl(
      fun(N, {T, L}) ->
        case erlang:whereis(worker_name(Sup, N)) of
          undefined ->
            {T, L};
          Worker ->
            [{message_queue_len, MQL} = MQLT,
             Memory, Function, Location, {dictionary, Dictionary}] =
              erlang:process_info(
                Worker,
                [ message_queue_len
                , memory
                , current_function
                , current_location
                , dictionary
                ]),
            WS = [MQLT, Memory] ++
              function_location(Function, Location) ++
              task(proplists:get_value(wpool_task, Dictionary)),
            {T + MQL, [{N, WS} | L]}
        end
      end, {0, []}, lists:seq(1, Wpool#wpool.size)),
  ManagerStats = wpool_queue_manager:stats(Wpool#wpool.name),
  PendingTasks = proplists:get_value(pending_tasks, ManagerStats),
  [ {pool,                     Sup}
  , {supervisor,               erlang:whereis(Sup)}
  , {options,                  Wpool#wpool.opts}
  , {size,                     Wpool#wpool.size}
  , {next_worker,              Wpool#wpool.next}
  , {total_message_queue_len,  Total + PendingTasks}
  , {workers,                  WorkerStats}
  ].

function_location({current_function, {gen_server, loop, 6}}, _) ->
                  [];
function_location({current_function, {erlang, hibernate, _}}, _) ->
                  [];
function_location(Function, Location) ->
                 [Function, Location].
task(undefined) ->
  [];
task({_TaskId, Started, Task}) ->
  Time =
    calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
  [{task, Task}, {runtime, Time - Started}].

%% @doc the number of workers in the pool
-spec wpool_size(atom()) -> non_neg_integer() | undefined.
wpool_size(Name) ->
  try ets:update_counter(?MODULE, Name, {#wpool.size, 0}) of
    WpoolSize ->
      case erlang:whereis(Name) of
        undefined ->
          ets:delete(?MODULE, Name),
          undefined;
        _ ->
          WpoolSize
      end
  catch
    _:badarg ->
      case build_wpool(Name) of
        undefined -> undefined;
        Wpool -> Wpool#wpool.size
      end
  end.


%% @doc Set next within the worker pool record. Useful when using
%% a custom strategy function.
-spec next(pos_integer(), wpool()) -> wpool().
next(Next, WPool) -> WPool#wpool{next = Next}.

%% @doc Get values from the worker pool record. Useful when using a custom
%% strategy function.
-spec wpool_get(atom(), wpool()) -> any(); ([atom()], wpool()) -> any().
wpool_get(List, WPool) when is_list(List)->
  [g(Atom, WPool) || Atom <- List];
wpool_get(Atom, WPool) when is_atom(Atom) ->
  g(Atom, WPool).

g(name, #wpool{name=Ret}) -> Ret;
g(size, #wpool{size=Ret}) -> Ret;
g(next, #wpool{next=Ret}) -> Ret;
g(opts, #wpool{opts=Ret}) -> Ret;
g(qmanager, #wpool{qmanager=Ret}) -> Ret;
g(born, #wpool{born=Ret}) -> Ret.

-spec time_checker_name(wpool:name()) -> atom().
time_checker_name(Sup) ->
  list_to_atom(
    ?MODULE_STRING ++ [$-|atom_to_list(Sup)] ++ "-time-checker").

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
%% @private
-spec init({wpool:name(), [wpool:option()]}) ->
        {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init({Name, Options}) ->
  Workers = proplists:get_value(workers, Options, 100),
  OverrunHandler =
    proplists:get_value(
      overrun_handler, Options, {error_logger, warning_report}),
  TimeChecker = time_checker_name(Name),
  QueueManager = queue_manager_name(Name),
  ProcessSup = process_sup_name(Name),
  _Wpool =
    store_wpool(
      #wpool{ name = Name
            , size = Workers
            , next = 1
            , opts = Options
            , qmanager = QueueManager
            }),
  TimeCheckerSpec =
    { TimeChecker
    , {wpool_time_checker, start_link, [Name, TimeChecker, OverrunHandler]}
    , permanent
    , brutal_kill
    , worker
    , [wpool_time_checker]
    },
  QueueManagerSpec =
    { QueueManager
    , {wpool_queue_manager, start_link, [Name, QueueManager]}
    , permanent
    , brutal_kill
    , worker
    , [wpool_queue_manager]
    },

  SupShutdown = proplists:get_value(pool_sup_shutdown, Options, brutal_kill),
  WorkerOpts =
    [{queue_manager, QueueManager}, {time_checker, TimeChecker} | Options],
  ProcessSupSpec =
    { ProcessSup
    , {wpool_process_sup, start_link, [Name, ProcessSup, WorkerOpts]}
    , permanent
    , SupShutdown
    , supervisor
    , [wpool_process_sup]
    },

  SupIntensity = proplists:get_value(pool_sup_intensity, Options, 5),
  SupPeriod = proplists:get_value(pool_sup_period, Options, 60),
  SupStrategy = {one_for_all, SupIntensity, SupPeriod},
  {ok, {SupStrategy, [TimeCheckerSpec, QueueManagerSpec, ProcessSupSpec]}}.

%% @private
-spec worker_name(wpool:name(), pos_integer()) -> atom().
worker_name(Sup, I) ->
  list_to_atom(
    ?MODULE_STRING ++ [$-|atom_to_list(Sup)] ++ [$-| integer_to_list(I)]).

%% ===================================================================
%% Private functions
%% ===================================================================
process_sup_name(Sup) ->
  list_to_atom(?MODULE_STRING ++ [$-|atom_to_list(Sup)] ++ "-process-sup").
queue_manager_name(Sup) ->
  list_to_atom(?MODULE_STRING ++ [$-|atom_to_list(Sup)] ++ "-queue-manager").

worker_with_no_task(Wpool) ->
  %% Moving the beginning of the list to a random point to ensure that clients
  %% do not always start asking for process_info to the processes that are most
  %% likely to have bigger message queues
  First = rnd(Wpool#wpool.size),
  worker_with_no_task(0, Wpool#wpool{next = First}).
worker_with_no_task(Size, #wpool{size = Size}) ->
  undefined;
worker_with_no_task(Checked, Wpool) ->
  Worker = worker_name(Wpool#wpool.name, Wpool#wpool.next),
  case try_process_info(whereis(Worker), [message_queue_len, dictionary]) of
    [{message_queue_len, 0}, {dictionary, Dictionary}] ->
      case proplists:get_value(wpool_task, Dictionary) of
        undefined -> Worker;
        _ -> worker_with_no_task(Checked + 1, next_wpool(Wpool))
      end;
    _ ->
      worker_with_no_task(Checked + 1, next_wpool(Wpool))
  end.

try_process_info(undefined, _) ->
  [];
try_process_info(Pid, Keys) ->
  erlang:process_info(Pid, Keys).

min_message_queue(Wpool) ->
  %% Moving the beginning of the list to a random point to ensure that clients
  %% do not always start asking for process_info to the processes that are most
  %% likely to have bigger message queues
  First = rnd(Wpool#wpool.size),
  min_message_queue(0, Wpool#wpool{next = First}, []).
min_message_queue(Size, #wpool{size = Size}, Found) ->
  {_, Worker} = lists:min(Found),
  Worker;
min_message_queue(Checked, Wpool, Found) ->
  Worker = worker_name(Wpool#wpool.name, Wpool#wpool.next),
  QLength = queue_length(whereis(Worker)),
  min_message_queue(Checked + 1, next_wpool(Wpool),
                    [{QLength, Worker} | Found]).

queue_length(undefined) ->
  infinity;
queue_length(Pid) when is_pid(Pid) ->
  case erlang:process_info(Pid, message_queue_len) of
    {message_queue_len, L} -> L;
    undefined -> infinity
  end.

%% ===================================================================
%% ETS functions
%% ===================================================================
store_wpool(Wpool) ->
  true = ets:insert(?MODULE, Wpool),
  Wpool.

move_wpool(Name) ->
  try
    WpoolSize = ets:update_counter(?MODULE, Name, {#wpool.size, 0}),
    ets:update_counter(?MODULE, Name, {#wpool.next, 1, WpoolSize, 1})
  catch
    _:badarg ->
      case build_wpool(Name) of
        undefined -> undefined;
        Wpool -> Wpool#wpool.next
      end
  end.

%% @doc Use this function to get the Worker pool record in a custom worker.
-spec find_wpool(atom()) -> undefined | wpool().
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

%% @doc We use this function not to report an error if for some reason we've
%%      lost the record on the ets table. This SHOULDN'T be called too much
build_wpool(Name) ->
  error_logger:warning_msg(
    "Building a #wpool record for ~p. Something must have failed.", [Name]),
  try supervisor:count_children(process_sup_name(Name)) of
    Children ->
      Size = proplists:get_value(active, Children, 0),
      Wpool =
        #wpool{ name = Name
              , size = Size
              , next = 1
              , opts = []
              , qmanager = queue_manager_name(Name)
              },
      store_wpool(Wpool)
  catch
    _:Error ->
      error_logger:warning_msg("Wpool ~p not found: ~p", [Name, Error]),
      undefined
  end.

next_wpool(Wpool) ->
  Wpool#wpool{next = (Wpool#wpool.next rem Wpool#wpool.size) + 1}.

rnd(WpoolSize) ->
  case application:get_env(worker_pool, random_fun) of
    undefined ->
      set_random_fun(),
      rnd(WpoolSize);
    {ok, RndFun} ->
      RndFun(WpoolSize)
  end.

set_random_fun() ->
  RndFun =
    case code:ensure_loaded(rand) of
      {module, rand} -> fun rand:uniform/1;
      {error, _} ->
        fun(Size) ->
          _ = erlang:apply(random, seed, [os:timestamp()]),
          erlang:apply(random, uniform, [Size])
        end
    end,
  application:set_env(worker_pool, random_fun, RndFun).
