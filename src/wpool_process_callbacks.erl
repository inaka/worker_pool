-module(wpool_process_callbacks).

-include_lib("kernel/include/logger.hrl").

-behaviour(gen_event).

% The callbacks are called in an extremely dynamic fashion from call/3.
-hank([unused_callbacks]).

-export([init/1, handle_event/2, handle_call/2]).
-export([notify/3, add_callback_module/2, remove_callback_module/2]).

-doc """
Callback state. Basically, the module that handles the callbacks.
""".
-nominal state() :: module().
-export_type([state/0]).

-doc """
Event being reported.
""".
-nominal event() :: handle_init_start | handle_worker_creation | handle_worker_death.
-export_type([event/0]).

-doc """
Callback handler initialization.
""".
-callback handle_init_start(wpool:name()) -> term().
-doc """
Callback for new worker creation.
""".
-callback handle_worker_creation(wpool:name()) -> term().
-doc """
Callback for worker termination.
""".
-callback handle_worker_death(wpool:name(), term()) -> term().

-optional_callbacks([
    handle_init_start/1,
    handle_worker_creation/1,
    handle_worker_death/2
]).

-doc false.
-spec init(module()) -> {ok, state()}.
init(Module) ->
    {ok, Module}.

-doc false.
-spec handle_event({event(), [term()]}, state()) -> {ok, state()}.
handle_event({Event, Args}, Module) ->
    call(Module, Event, Args),
    {ok, Module}.

-doc false.
-spec handle_call(Msg, state()) -> {ok, {error, {unexpected_call, Msg}}, state()}.
handle_call(Msg, State) ->
    {ok, {error, {unexpected_call, Msg}}, State}.

-doc """
Sends a notification to all registered callback modules.
""".
-spec notify(event(), undefined | atom(), [term()]) -> ok.
notify(_, undefined, _) ->
    ok;
notify(Event, EventMgr, Args) ->
    gen_event:notify(EventMgr, {Event, Args}).

-doc """
Adds a callback module.
""".
-spec add_callback_module(wpool:name(), module()) -> ok | {error, term()}.
add_callback_module(EventManager, Module) ->
    case ensure_loaded(Module) of
        ok ->
            gen_event:add_handler(EventManager, {wpool_process_callbacks, Module}, Module);
        Other ->
            Other
    end.

-doc """
Removes a callback module.
""".
-spec remove_callback_module(wpool:name(), module()) -> ok | {error, term()}.
remove_callback_module(EventManager, Module) ->
    gen_event:delete_handler(EventManager, {wpool_process_callbacks, Module}, Module).

call(Module, Event, Args) ->
    try
        case erlang:function_exported(Module, Event, length(Args)) of
            true ->
                erlang:apply(Module, Event, Args);
            _ ->
                ok
        end
    catch
        E:R ->
            logger:warning(
                #{
                    what => "Could not call callback module",
                    error => E,
                    reason => R
                },
                ?LOCATION
            )
    end.

ensure_loaded(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} ->
            ok;
        %% We are in embedded mode so the module was loaded if exists
        {error, embedded} ->
            ok;
        Other ->
            Other
    end.
