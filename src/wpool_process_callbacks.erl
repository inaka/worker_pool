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
  {ok, Module};
handle_event(_, State) ->
  {ok, State}.

-spec handle_call(any(), state()) -> {ok, ok, state()}.
handle_call(_, State) ->
  {ok, ok, State}.

-spec handle_info(any(), state()) -> {ok, state()}.
handle_info(_, State) ->
  {ok, State}.

-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

-spec terminate(any(), state()) -> ok.
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
