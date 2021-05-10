%% encd -- erlang netchannel daemon
%% Copyright Matthew Veety, 2021. Under BSD license.

-module(channel).
-export([new/0, send/2, recv/1, close/1]).

proc(wait,_) ->
    receive
	{Proc, status} ->
	    Proc ! wait,
	    proc(wait, nil);
	{Proc, send, Data} ->
	    proc(send, {Proc, Data});
	{Proc, recv} ->
	    proc(recv, {Proc});
	{Proc, close} ->
	    proc(close, {Proc})
    end;
proc(send, State = {Psend, Data}) ->
    receive
	{Precv, status} ->
	    Precv ! send,
	    proc(send, State);
	{Precv, recv} ->
	    Precv ! {ok, Data},
	    Psend ! ok,
	    proc(wait, nil);
	{Precv, close} ->
	    Psend ! close,
	    Precv ! close,
	    exit(close)
    end;
proc(recv, State = {Precv}) ->
    receive
	{Psend, status} ->
	    Psend ! recv,
	    proc(recv, State);
	{Psend, send, Data} ->
	    Precv ! {ok, Data},
	    Psend ! ok,
	    proc(wait, nil);
	{Psend, close} ->
	    Psend ! close,
	    Precv ! close,
	    exit(close)
    end;
proc(close, {Pclose}) ->
    Pclose ! close,
    receive
	{Proc, _} ->
	    Proc ! close,
	    exit(close);
	{Proc, _, _} ->
	    Proc ! close,
	    exit(close)
    after
	600000 ->
	    %% after 10 minutes, forget about it
	    exit(close)
    end.

new() ->
    spawn(fun() -> proc(wait, nil) end).

send(Chan, Data) ->
    Chan ! {self(), send, Data},
    receive
	ok -> ok;
	close -> close
    end.

recv(Chan) ->
    Chan ! {self(), recv},
    receive
	{ok, Data} -> {ok, Data};
	close -> close
    end.

close(Chan) ->
    Chan ! {self(), close},
    receive
	close -> ok
    end.
