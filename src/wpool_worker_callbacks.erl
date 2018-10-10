-module(wpool_worker_callbacks).

-export([call/3]).

-type event() :: on_init_start | on_new_worker | on_worker_dead.

-spec call(event(), [wpool:option()], [any()]) -> any().
call(Event, Options, Args) ->
  case get_callback_fun(Event, Options) of
    undefined ->
      ok;
    Fun ->
      erlang:apply(Fun, Args)
  end.

get_callback_fun(Event, Options) ->
  case lists:keyfind(callbacks, 1, Options) of
    {_, Callbacks} ->
      maps:get(Event, Callbacks, undefined);
    _ ->
      undefined
  end.

