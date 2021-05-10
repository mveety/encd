%% encd -- erlang netchannel daemon
%% Copyright Matthew Veety, 2021. Under BSD license.

-module(ns).
-export([start/0, add/2, add/3, lookup/2, stats/1, name_server/2, list/1, key_lookup/2]).

schan_gc(NSpid, Chanpid, Chanid) ->
    process_flag(trap_exit, true),
    link(Chanpid),
    link(NSpid),
    io:format("name_server(~p): registered channel id ~p~n",[NSpid, Chanid]),
    receive
	{'EXIT', Chanpid, _} ->
	    NSpid ! {self(), remove, Chanid},
	    io:format("name_server: removed dead channel ~p~n",[Chanid]);
	{'EXIT', NSpid, _} ->
	    io:format("error: name_server died. removing channel ~p~n",[Chanid])
    end.

name_gc(NSpid, Name, Chanpid) ->
    process_flag(trap_exit, true),
    link(Chanpid),
    link(NSpid),
    io:format("name_server: registered name ~p~n",[Name]),
    receive
	{'EXIT', Chanpid, _} ->
	    NSpid ! {self(), remove, Name},
	    io:format("name_server: removing name of dead channel: ~p~n",[Name]);
	{'EXIT', NSpid, _} ->
	    io:format("error: name_server died. removing name ~p~n",[Name])
    end.

name_server(State, N) ->
    NSpid = self(),
    receive
	{Src, add, Chanpid} ->
	    NewState = dict:store(N, Chanpid, State),
	    spawn(fun() -> schan_gc(NSpid, Chanpid, N) end),
	    Src ! {ok, N},
	    name_server(NewState, N+1);
	{Src, name, Name, Id} ->
	    case dict:find(Id, State) of
		{ok, ChanPid} ->
		    case dict:find(Name, State) of
			error ->
			    NewState = dict:store(Name, Id, State),
			    spawn(fun() -> name_gc(NSpid, Name, ChanPid) end),
			    Src ! {ok, {Name, Id}},
			    name_server(NewState, N);
			{ok, _} ->
			    Src ! error,
			    name_server(State, N)
		    end;
		error ->
		    Src ! error,
		    name_server(State, N)
	    end;
	{Src, lookup, Id} ->
	    try dict:fetch(Id, State) of
		Val -> Src ! {ok, Val}
	    catch
		error:badarg -> Src ! error
	    end,
	    name_server(State, N);
	{Src, remove, Id} ->
	    NewState = dict:erase(Id, State),
	    Src ! ok,
	    name_server(NewState, N);
	{Src, list} ->
	    Src ! {ok, dict:to_list(State)},
	    name_server(State, N);
	{Src, stats} ->
	    Src ! {ok, dict:size(State)},
	    name_server(State, N);
	{'EXIT', _, _} -> %% do nothing
	    name_server(State, N);
	terminate ->
	    exit(ok)
    end.

name_server_start(State, N) ->
    process_flag(trap_exit, true),
    name_server(State, N).

start() ->
    spawn(fun() -> name_server_start(dict:new(), 0) end).

add(Ns, Chanpid) ->
    Ns ! {self(), add, Chanpid},
    receive
	{ok, N} -> {ok, N}
    end.
add(Ns, Name, Id) ->
    Ns ! {self(), name, Name, Id},
    receive
	{ok, {Rname, Rid}} -> {ok, {Rname, Rid}};
	error -> error
    end.

lookup(Ns, Id) ->
    Ns ! {self(), lookup, Id},
    receive
	{ok, Val} -> Val;
	error -> error
    end.

stats(Ns) ->
    Ns ! {self(), stats},
    receive
	{ok, Len} -> Len
    end.

list(Ns) ->
    Ns ! {self(), list},
    receive
	{ok, List} -> List
    end.

find_key([], _) ->
    error;
find_key([{DKey, DVal}|T], Val) ->
    case DVal of
	Val -> {ok, DKey};
	_ -> find_key(T, Val)
    end.

key_lookup(Ns, Val) ->
    List = ns:list(Ns),
    {ok, Key} = find_key(List, Val),
    Key.
