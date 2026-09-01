-module(wpool_test_utils).

-export([wait_for/2, wait_for/4, wait_for_success/1]).

-nominal task(T) :: fun(() -> T).
-export_type([task/1]).

-spec wait_for(task(T1), T2) -> {error, {timeout, {badmatch, T1}}} | T2 when is_subtype(T2, T1).
wait_for(Task, ExpectedAnswer) ->
    wait_for(Task, ExpectedAnswer, 200, 10).

-spec wait_for(task(T1), T2, pos_integer(), pos_integer()) ->
    {error, {timeout, {badmatch, T1}}} | T2
when
    is_subtype(T2, T1).
wait_for(Task, ExpectedAnswer, SleepTime, Retries) ->
    wait_for_success(fun() -> ExpectedAnswer = Task() end, SleepTime, Retries).

-spec wait_for_success(task(T)) -> {error, {timeout, term()}} | T.
wait_for_success(Task) ->
    wait_for_success(Task, 200, 10).

-spec wait_for_success(task(T), pos_integer(), pos_integer()) -> {error, {timeout, term()}} | T.
wait_for_success(Task, SleepTime, Retries) ->
    wait_for_success(Task, undefined, SleepTime, Retries).

wait_for_success(_Task, Exception, _SleepTime, 0) ->
    {error, {timeout, Exception}};
wait_for_success(Task, _Exception, SleepTime, Retries) ->
    try
        Task()
    catch
        _:NewException ->
            timer:sleep(SleepTime),
            wait_for_success(Task, NewException, SleepTime, Retries - 1)
    end.
