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
%%% @doc Worker pool main interface.
%%%      Use functions provided by this module to manage your pools of workers
-module(wpool).
-author('elbrujohalcon@inaka.net').

-define(DEFAULTS, [ {overrun_warning, infinity}
                  , {overrun_handler, {error_logger, warning_report}}
                  , {workers, 100}, {worker_opt, []}
                  ]).

%% Copied from gen.erl
-type debug_flag() :: 'trace' | 'log' | 'statistics' | 'debug'
                    | {'logfile', string()}.
-type gen_option() :: {'timeout', timeout()}
                    | {'debug', [debug_flag()]}
                    | {'spawn_opt', [proc_lib:spawn_option()]}.
-type gen_options() :: [gen_option()].

-type name() :: atom().
-type supervisor_strategy() :: { supervisor:strategy()
                               , non_neg_integer()
                               , pos_integer()
                               }.
-type option() :: {overrun_warning, infinity|pos_integer()}
                | {overrun_handler, {Module::atom(), Fun::atom()}}
                | {workers, pos_integer()}
                | {worker_opt, gen_options()}
                | {worker, {Module::atom(), InitArg::term()}}
                | {strategy, supervisor_strategy()}
                | {worker_type, gen_fsm | gen_server}
                | {pool_sup_intensity, non_neg_integer()}
                | {pool_sup_period, non_neg_integer()}
                .
-type custom_strategy() :: fun(([atom()])-> Atom::atom()).
-type strategy() :: best_worker
                  | random_worker
                  | next_worker
                  | available_worker
                  | next_available_worker
                  | {hash_worker, term()}
                  | custom_strategy().
-type worker_stats() :: [ {messsage_queue_len, non_neg_integer()}
                        | {memory, pos_integer()}
                        ].
-type stats() :: [ {pool, name()}
                 | {supervisor, pid()}
                 | {options, [option()]}
                 | {size, non_neg_integer()}
                 | {next_worker, pos_integer()}
                 | {total_message_queue_len, non_neg_integer()}
                 | {workers, [{pos_integer(), worker_stats()}]}
                 ].
-export_type([ name/0
             , option/0
             , custom_strategy/0
             , strategy/0
             , worker_stats/0
             , stats/0
             ]).

-export([ start/0
        , start/2
        , stop/0
        , stop/1
        ]).
-export([ start_pool/1
        , start_pool/2
        , start_sup_pool/1
        , start_sup_pool/2
        ]).
-export([ stop_pool/1
        ]).
-export([ call/2
        , cast/2
        , call/3
        , cast/3
        , call/4
        ]).
-export([ send_event/2
        , send_event/3
        , sync_send_event/2
        , sync_send_event/3
        , sync_send_event/4
        , send_all_state_event/2
        , send_all_state_event/3
        , sync_send_all_state_event/2
        , sync_send_all_state_event/3
        , sync_send_all_state_event/4
        ]).
-export([ stats/0
        , stats/1
        ]).
-export([ default_strategy/0
        ]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ADMIN API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the application
-spec start() -> ok | {error, {already_started, ?MODULE}}.
start() -> application:start(worker_pool).

%% @doc Stops the application
-spec stop() -> ok.
stop() -> application:stop(worker_pool).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% BEHAVIOUR CALLBACKS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @private
-spec start(any(), any()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) -> wpool_sup:start_link().

%% @private
-spec stop(any()) -> ok.
stop(_State) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PUBLIC API
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @equiv start_pool(Name, [])
-spec start_pool(name()) -> {ok, pid()}.
start_pool(Name) -> start_pool(Name, []).

%% @doc Starts (and links) a pool of N wpool_processes.
%%      The result pid belongs to a supervisor (in case you want to add it to a
%%      supervisor tree)
-spec start_pool(name(), [option()]) ->
        {ok, pid()} | {error, {already_started, pid()} | term()}.
start_pool(Name, Options) -> wpool_pool:start_link(Name, all_opts(Options)).

%% @equiv start_sup_pool(Name, [])
-spec start_sup_pool(name()) -> {ok, pid()}.
start_sup_pool(Name) -> start_sup_pool(Name, []).

%% @doc Starts a pool of N wpool_processes supervised by {@link wpool_sup}
-spec start_sup_pool(name(), [option()]) ->
        {ok, pid()} | {error, {already_started, pid()} | term()}.
start_sup_pool(Name, Options) ->
  wpool_sup:start_pool(Name, all_opts(Options)).

%% @doc Stops the pool
-spec stop_pool(name()) -> ok.
stop_pool(Name) -> wpool_sup:stop_pool(Name).

%% @doc Default strategy
-spec default_strategy() -> strategy().
default_strategy() ->
  case application:get_env(worker_pool, default_strategy) of
    undefined -> available_worker;
    {ok, Strategy} -> Strategy
  end.

%% @equiv call(Sup, Call, default_strategy())
-spec call(name(), term()) -> term().
call(Sup, Call) -> call(Sup, Call, default_strategy()).

%% @equiv call(Sup, Call, Strategy, 5000)
-spec call(name(), term(), strategy()) -> term().
call(Sup, Call, Strategy) -> call(Sup, Call, Strategy, 5000).

%% @doc Picks a server and issues the call to it.
%%      For all strategies except available_worker, Timeout applies only to the
%%      time spent on the actual call to the worker, because time spent finding
%%      the worker in other strategies is negligible.
%%      For available_worker the time used choosing a worker is also considered
-spec call(name(), term(), strategy(), timeout()) -> term().
call(Sup, Call, available_worker, Timeout) ->
  wpool_pool:call_available_worker(Sup, Call, Timeout);
call(Sup, Call, {hash_worker, HashKey}, Timeout) ->
  wpool_process:call(wpool_pool:hash_worker(Sup, HashKey), Call, Timeout);
call(Sup, Call, Fun, Timeout) when is_function(Fun) ->
  wpool_process:call(Fun(Sup), Call, Timeout);
call(Sup, Call, Strategy, Timeout) ->
  wpool_process:call(wpool_pool:Strategy(Sup), Call, Timeout).

%% @equiv cast(Sup, Cast, default_strategy())
-spec cast(name(), term()) -> ok.
cast(Sup, Cast) -> cast(Sup, Cast, default_strategy()).

%% @doc Picks a server and issues the cast to it
-spec cast(name(), term(), strategy()) -> ok.
cast(Sup, Cast, available_worker) ->
  wpool_pool:cast_to_available_worker(Sup, Cast);
cast(Sup, Cast, {hash_worker, HashKey}) ->
  wpool_process:cast(wpool_pool:hash_worker(Sup, HashKey), Cast);
cast(Sup, Cast, Fun) when is_function(Fun) ->
  wpool_process:cast(Fun(Sup), Cast);
cast(Sup, Cast, Strategy) ->
  wpool_process:cast(wpool_pool:Strategy(Sup), Cast).

%% @equiv sync_send_event(Sup, Event, default_strategy())
-spec sync_send_event(name(), term()) -> term().
sync_send_event(Sup, Event) -> sync_send_event(Sup, Event, default_strategy()).

%% @equiv sync_send_event(Sup, Event, Strategy, 5000)
-spec sync_send_event(name(), term(), strategy()) -> term().
sync_send_event(Sup, Event, Strategy) ->
  sync_send_event(Sup, Event, Strategy, 5000).

%% @doc Picks a fsm and issues the event to it.
%%      For all strategies except available_worker, Timeout applies only to the
%%      time spent on the actual call to the worker, because time spent finding
%%      the worker in other strategies is negligible.
%%      For available_worker the time used choosing a worker is also considered
-spec sync_send_event(name(), term(), strategy(), timeout()) -> term().
sync_send_event(Sup, Event, available_worker, Timeout) ->
  wpool_pool:sync_send_event_to_available_worker(Sup, Event, Timeout);
sync_send_event(Sup, Event, {hash_worker, HashKey}, Timeout) ->
  wpool_fsm_process:sync_send_event(wpool_pool:hash_worker(Sup, HashKey),
    Event, Timeout);
sync_send_event(Sup, Event, Fun, Timeout) when is_function(Fun) ->
  wpool_fsm_process:sync_send_event(Fun(Sup), Event, Timeout);
sync_send_event(Sup, Event, Strategy, Timeout) ->
  wpool_fsm_process:sync_send_event(wpool_pool:Strategy(Sup), Event, Timeout).

%% @equiv send_event(Sup, Event, default_strategy())
-spec send_event(name(), term()) -> ok.
send_event(Sup, Event) -> send_event(Sup, Event, default_strategy()).

%% @doc Picks a server and issues the event to it
-spec send_event(name(), term(), strategy()) -> ok.
send_event(Sup, Event, available_worker) ->
  wpool_pool:send_event_to_available_worker(Sup, Event);
send_event(Sup, Event, {hash_worker, HashKey}) ->
  wpool_fsm_process:send_event(wpool_pool:hash_worker(Sup, HashKey), Event);
send_event(Sup, Event, Fun) when is_function(Fun) ->
  wpool_fsm_process:send_event(Fun(Sup), Event);
send_event(Sup, Event, Strategy) ->
  wpool_fsm_process:send_event(wpool_pool:Strategy(Sup), Event).

%% @equiv send_all_state_event(Sup, Event, default_strategy())
-spec send_all_state_event(name(), term()) -> ok.
send_all_state_event(Sup, Event) ->
  send_all_state_event(Sup, Event, default_strategy()).

%% @doc Picks a server and issues the event to it
-spec send_all_state_event(name(), term(), strategy()) -> ok.
send_all_state_event(Sup, Event, available_worker) ->
  wpool_pool:send_all_event_to_available_worker(Sup, Event);
send_all_state_event(Sup, Event, {hash_worker, HashKey}) ->
  wpool_fsm_process:send_all_state_event(
    wpool_pool:hash_worker(Sup, HashKey), Event);
send_all_state_event(Sup, Event, Fun) when is_function(Fun) ->
  wpool_fsm_process:send_all_state_event(Fun(Sup), Event);
send_all_state_event(Sup, Event, Strategy) ->
  wpool_fsm_process:send_all_state_event(wpool_pool:Strategy(Sup), Event).

%% @equiv sync_send_all_state_event(Sup, Event, default_strategy())
-spec sync_send_all_state_event(name(), term()) -> term().
sync_send_all_state_event(Sup, Event) ->
  sync_send_all_state_event(Sup, Event, default_strategy()).

%% @equiv sync_send_all_state_event(Sup, Event, Strategy, 5000)
-spec sync_send_all_state_event(name(), term(), strategy()) -> term().
sync_send_all_state_event(Sup, Event, Strategy) ->
  sync_send_all_state_event(Sup, Event, Strategy, 5000).

%% @doc Picks a fsm and issues the event to it.
%%      For all strategies except available_worker, Timeout applies only to the
%%      time spent on the actual call to the worker, because time spent finding
%%      the worker in other strategies is negligible.
%%      For available_worker the time used choosing a worker is also considered
-spec sync_send_all_state_event(name(), term(), strategy(), timeout()) ->
        term().
sync_send_all_state_event(Sup, Event, available_worker, Timeout) ->
  wpool_pool:sync_send_all_event_to_available_worker(Sup, Event, Timeout);
sync_send_all_state_event(Sup, Event, {hash_worker, HashKey}, Timeout) ->
  wpool_fsm_process:sync_send_all_state_event(
    wpool_pool:hash_worker(Sup, HashKey), Event, Timeout);
sync_send_all_state_event(Sup, Event, Fun, Timeout) when is_function(Fun) ->
  wpool_fsm_process:sync_send_all_state_event(Fun(Sup),
    Event, Timeout);
sync_send_all_state_event(Sup, Event, Strategy, Timeout) ->
  wpool_fsm_process:sync_send_all_state_event(wpool_pool:Strategy(Sup),
    Event, Timeout).

%% @doc Retrieves a snapshot of the pool stats
-spec stats() -> [stats()].
stats() -> wpool_pool:stats().

%% @doc Retrieves a snapshot of a given pool stats
-spec stats(name()) -> stats().
stats(Sup) -> wpool_pool:stats(Sup).

all_opts(Options) -> Options ++ ?DEFAULTS.
