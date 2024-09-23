-module(echo_supervisor).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, noargs).

init(noargs) ->
    Children =
        #{id => undefined,
          start => {echo_server, start_link, []},
          restart => transient,
          shutdown => 5000,
          type => worker,
          modules => [echo_server]},
    Strategy =
        #{strategy => simple_one_for_one,
          intensity => 5,
          period => 60},
    {ok, {Strategy, [Children]}}.
