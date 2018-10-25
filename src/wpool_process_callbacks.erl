-module(wpool_process_callbacks).

-behaviour(gen_event).

%% gen_event callbacks

-export([ init/1
        , handle_event/2
        , handle_call/2
        ]).

-export([ notify/3
        , add_callback_module/2
        , remove_callback_module/2
        ]).
-type state() :: module().

-type event() :: handle_init_start | handle_worker_creation | handle_worker_death.

-callback handle_init_start(wpool:name()) -> any().
-callback handle_worker_creation(wpool:name()) -> any().
-callback handle_worker_death(wpool:name(), term()) -> any().

-optional_callbacks([handle_init_start/1, handle_worker_creation/1, handle_worker_death/2]).

-spec init(module()) -> {ok, state()}.
init(Module) ->
  {ok, Module}.

-spec handle_event({event(), [any()]}, state()) -> {ok, state()}.
handle_event({Event, Args}, Module) ->
  call(Module, Event, Args),
  {ok, Module}.

-spec handle_call(Msg, state()) -> {ok, {error, {unexpected_call, Msg}}, state()}.
handle_call(Msg, State) ->
  {ok, {error, {unexpected_call, Msg}}, State}.

-spec notify(event(), [wpool:option()], [any()]) -> ok.
notify(Event, Options, Args) ->
  case lists:keyfind(event_manager, 1, Options) of
    {event_manager, EventMgr} ->
      gen_event:notify(EventMgr, {Event, Args});
    _ ->
      ok
  end.

-spec add_callback_module(wpool:name(), module()) -> ok | {error, any()}.
add_callback_module(EventManager, Module) ->
  case ensure_loaded(Module) of
    ok ->
      gen_event:add_handler(EventManager,
                            {wpool_process_callbacks, Module}, Module);
    Other ->
      Other
  end.


-spec remove_callback_module(wpool:name(), module()) -> ok | {error, any()}.
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
      error_logger:warning_msg("Could not call callback module, error:~p, reason:~p", [E, R])
  end.

ensure_loaded(Module) ->
  case code:ensure_loaded(Module) of
    {module, Module} ->
      ok;
    {error, embedded} -> %% We are in embedded mode so the module was loaded if exists
      ok;
    Other ->
      Other
  end.
