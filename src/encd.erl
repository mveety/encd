%% encd -- erlang netchannel daemon
%% Copyright Matthew Veety, 2021. Under BSD license.

-module(encd).
-export([start/2, stop/1, stats/0, start_or_find_ns/0,
	 close_all_channels/0]).

start_or_find_ns() ->
    case global:whereis_name(encd_ns) of
	undefined ->
	    NewNs = ns:start(),
	    global:register_name(encd_ns, NewNs),
	    NewNs;
	Ns -> Ns
    end.

start(normal, []) ->
    Ns = start_or_find_ns(),
    proc_lib:start_link(server, init, [self(), Ns, 2426]).

stop([]) ->
    ok.

ns_stats() ->
    case global:whereis_name(encd_ns) of
	undefined ->
	    error;
	Ns ->
	    NChans = ns:stats(Ns),
	    Chans = ns:list(Ns),
	    {ok, {nchans, NChans}, {chans, Chans}}
    end.

server_stats() ->
    case whereis(encd) of
	undefined ->
	    error;
	Server ->
	    {Npids, Pids} = server:stats(Server),
	    {ok, Npids, Pids}
    end.

stats() ->
    {ok, Nchans, Chans} = ns_stats(),
    {ok, Npids, Pids} = server_stats(),
    {ok, Nchans, Npids, Chans, Pids}.

close_all_channels() ->
    {_, _, _, {_, Chans}, _} = encd:stats(),
    [channel:close(X) || {_, X} <- Chans].
