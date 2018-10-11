-module(wpool_process_callbacks).

-behaviour(gen_event).

%% gen_event callbacks

-export([ init/1
        , handle_event/2
        , handle_call/2
        , handle_info/2
        , code_change/3
        , terminate/2]).

-export([notify/3]).
-type state() :: ordset:ordset(module()).

-type event() :: on_init_start | on_new_worker | on_worker_dead.

-spec init([wpool:option()]) -> {ok, state()}.
init(WPoolOpts) ->
{ok, maybe_initial_callbacks(WPoolOpts)}.

-spec handle_event({event(), [any()]}, state()) -> {ok, state()}.
handle_event({Event, Args}, Callbacks) ->
  [call(Callback, Event, Args) || Callback <- Callbacks],
  {ok, Callbacks};
handle_event(_, State) ->
  {ok, State}.

-spec handle_call(Call, state()) -> {ok, ok, state()} when
    Call :: {add_callback, module()} | {remove_callback, module()}.
handle_call({add_callback, Module}, Callbacks) ->
  {ok, ok, ordsets:add_element(Module, Callbacks)};
handle_call({remove_callback, Module}, Callbacks) ->
  {ok, ok, ordsets:del_element(Module, Callbacks)};
handle_call(_, State) ->
  {ok, ok, State}.

handle_info(_, State) ->
  {ok, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _State) ->
  ok.

-spec notify(event(), [wpool:option()], [any()]) -> ok.
notify(Event, Options, Args) ->
  case lists:keyfind(event_manager, 1, Options) of
    {event_manager, EventMgr} ->
      gen_event:notify(EventMgr, {Event, Args});
    _ ->
      ok
  end.

maybe_initial_callbacks(Options) ->
  case lists:keyfind(callbacks, 1, Options) of
    {callbacks, Modules} ->
      ordsets:from_list(Modules);
    _ ->
      []
  end.

call(Module, Event, Args) ->
  try
    erlang:apply(Module, Event, Args)
  catch
    E:R ->
      error_logger:warning_msg("Could not call callback module, error:~p, reason:~p", [E, R])
  end.
