%% encd -- erlang netchannel daemon
%% Copyright Matthew Veety, 2021. Under BSD license.

-module(nchan).
-export([name/1, name/2, name/3, connect/1, connect/2, connect/3, create/0,
	 create/1, create/2, send/2, recv/1, disconnect/1, close/1,
	 register/2]).

main_disconnect(Client) ->
    Client ! {self(), disconnect},
    receive
	{Client, disconnect} -> ok
    after
	30000 ->
	    timeout
    end.

name(Name, Addr, Port) ->
    {ok, Client} = client:start(Addr, Port),
    Client ! {self(), name, Name},
    receive
	{Client, ok, Id} ->
	    ok = main_disconnect(Client),
	    {ok, Id};
	{Client, error, not_found} ->
	    ok = main_disconnect(Client),
	    error
    end.
name(Name, Port) -> name(Name, {127,0,0,1}, Port).
name(Name) -> name(Name, 2426).

connect(Id, Addr, Port) ->
    {ok, Client} = client:start(Addr, Port),
    Client ! {self(), connect, Id},
    receive
	{Client, ok} ->
	    {ok, Client};
	{Client, error, _} ->
	    ok = main_disconnect(Client),
	    error
    end.
connect(Id, Port) -> connect(Id, {127,0,0,1}, Port).
connect(Id) -> connect(Id, 2426).

create(Addr, Port) ->
    {ok, Client} = client:start(Addr, Port),
    Client ! {self(), create},
    receive
	{Client, ok, Id} ->
	    {ok, Client, Id}
    end.
create(Port) -> create({127,0,0,1}, Port).
create() -> create(2426).

send(Chan, Data) ->
    Chan ! {self(), send, Data},
    receive
	{Chan, ok} ->
	    ok;
	{Chan, close} ->
	    main_disconnect(Chan),
	    close
    end.

recv(Chan) ->
    Chan ! {self(), recv},
    receive
	{Chan, ok, Data} ->
	    {ok, Data};
	{Chan, close} ->
	    main_disconnect(Chan),
	    close
    end.

disconnect(Client) ->
    Client ! {self(), disconnect},
    receive
	{Client, ok} ->
	    main_disconnect(Client)
    end.

close(Chan) ->
    Chan ! {self(), close},
    receive
	{Chan, ok} ->
	    main_disconnect(Chan),
	    close
    end.

register(Chan, Name) ->
    Chan ! {self(), register, Name},
    receive
	{Chan, error} ->
	    error;
	{Chan, ok} ->
	    ok
    end.
