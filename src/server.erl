%% encd -- erlang netchannel daemon
%% Copyright Matthew Veety, 2021. Under BSD license.

-module(server).
-export([start/1, start/2, stats/1, listen_loop/4, handler/2]).

start(Ns) ->
    start(Ns, 2426).
start(Ns, Port) ->
    {ok, Listen} = gen_tcp:listen(Port, [{ip, {127,0,0,1}}
					,{active, false}
					,{keepalive, true}
					,binary]),
    listen(Listen, Ns).

stats(Server) ->
    Server ! {self(), stats},
    receive
	{ok, Npids, Pids} -> {Npids, Pids}
    end.

accepter(Listen, Pid) ->
    case gen_tcp:accept(Listen) of
	{ok, Accept} ->
	    gen_tcp:controlling_process(Accept, Pid),
	    Pid ! {accept, Accept},
	    accepter(Listen, Pid);
	{error, closed} ->
	    exit(ok)
    end.

killer([]) -> ok;
killer([H|T]) ->
    exit(H, kill),
    killer(T).

listen(Listen, Ns) ->
    Me = self(),
    process_flag(trap_exit, true),
    Accepter = spawn_link(fun() -> accepter(Listen, Me) end),
    link(Ns),
    listen_loop(Listen, Ns, Accepter, []).

listen_loop(Listen, Ns, Accepter, Pids) ->
    receive
	{accept, Accept} ->
	    Handler = spawn_link(fun() -> ?MODULE:handler(Accept, Ns) end),
	    gen_tcp:controlling_process(Accept, Handler),
	    io:format("listener(~p): got connection~n",[self()]),
	    ?MODULE:listen_loop(Listen, Ns, Accepter, [Handler|Pids]);
	{'EXIT', Ns, _} ->
	    io:format("listener(~p): name_server died~n",[self()]),
	    stop_server(Listen, Accepter, Pids);
	{'EXIT', Accepter, _} ->
	    io:format("listener(~p): accepter died~n",[self()]),
	    stop_server(Listen, Accepter, Pids);
	{'EXIT', Pid, _} ->
	    NewPids = lists:delete(Pid, Pids),
	    io:format("listener(~p): lost pid ~p~n",[self(), Pid]),
	    ?MODULE:listen_loop(Listen, Ns, Accepter, NewPids);
	{Proc, stats} ->
	    Proc ! {ok, {npids, length(Pids)}, {pids, Pids}},
	    ?MODULE:listen_loop(Listen, Ns, Accepter, Pids);
	reset ->
	    ?MODULE:listen_loop(Listen, Ns, Accepter, Pids);
	terminate ->
	    stop_server(Listen, Accepter, Pids)
    end.

stop_server(Listen, Accepter, Pids) ->
    io:format("listener(~p): stopping server ... ~n",[self()]),
    gen_tcp:close(Listen),
    exit(Accepter, kill),
    io:format("listener(~p): killing ~p pids~n", [self(), length(Pids)]),
    killer(Pids),
    io:format("done~n", []),
    exit(ok).

disconnect(Sock) ->
    %% reply: close
    io:format("client(~p): disconnect~n", [self()]),
    gen_tcp:send(Sock, <<"DS",0>>),
    gen_tcp:close(Sock),
    exit(ok).

server_error(Sock) ->
    io:format("client(~p): error~n", [self()]),
    gen_tcp:close(Sock),
    exit(error).

handler(Sock, Ns) ->
    inet:setopts(Sock, [{active, true}]),
    receive
	{tcp, Sock, <<"OK",0>>} ->
	    gen_tcp:send(Sock, <<"OK",0>>),
	    main_loop(Sock, Ns);
	{tcp, Sock, <<"DS",0>>} ->
	    disconnect(Sock)
    after
	30000 ->
	    server_error(Sock)
    end.

main_loop(Sock, Ns) ->
    receive
	{tcp, Sock, <<"NM", Len:1/little-integer-unit:8, Bstring:Len/binary>>} ->
	    Namestring = binary_to_list(Bstring),
	    name_to_id(Sock, Ns, Namestring);
	{tcp, Sock, <<"CO", Id:1/little-integer-unit:32>>} ->
	    connect(Sock, Ns, Id);
	{tcp, Sock, <<"CR",0>>} ->
	    create(Sock, Ns);
	{tcp, Sock, <<"DS",0>>} ->
	    disconnect(Sock)
    end.

name_to_id(Sock, Ns, Namestring) ->
    case ns:lookup(Ns, Namestring) of
	error ->
	    gen_tcp:send(Sock, <<"NF",0>>);
	Id ->
	    Msg = <<"ID",Id:1/little-integer-unit:32>>,
	    gen_tcp:send(Sock, Msg)
    end,
    main_loop(Sock, Ns).

connect(Sock, Ns, Id) ->
    case ns:lookup(Ns, Id) of
	error ->
	    gen_tcp:send(Sock, <<"NF",0>>),
	    main_loop(Sock, Ns);
	Chan ->
	    gen_tcp:send(Sock, <<"OK",0>>),
	    chan_loop({Sock, Ns, Id, Chan, client})
    end.

create(Sock, Ns) ->
    Chan = channel:new(),
    {ok, Id} = ns:add(Ns, Chan),
    Msg = <<"ID",Id:1/little-integer-unit:32>>,
    gen_tcp:send(Sock, Msg),
    chan_loop({Sock, Ns, Id, Chan, server}).

close(Sock, Ns) ->
    gen_tcp:send(Sock, <<"CL",0>>),
    main_loop(Sock, Ns).

chan_loop(State = {Sock, Ns, _Id, Chan, _Type}) ->
    receive
	{tcp, Sock, <<"SN",Len:1/little-integer-unit:32,Data:Len/binary>>} ->
	    case channel:send(Chan, Data) of
		ok ->
		    gen_tcp:send(Sock,<<"OK",0>>),
		    chan_loop(State);
		close ->
		    close(Sock, Ns)
	    end;
	{tcp, Sock, <<"RV",0>>} ->
	    case channel:recv(Chan) of
		{ok, Data} ->
		    Dlen = byte_size(Data),
		    Msg = <<"R0",Dlen:1/little-integer-unit:32,Data:Dlen/binary>>,
		    gen_tcp:send(Sock, Msg),
		    chan_loop(State);
		close ->
		    close(Sock, Ns)
	    end;
	{tcp, Sock, <<"CL",0>>} ->
	    channel:close(Chan),
	    close(Sock, Ns);
	{tcp, Sock, <<"DS",0>>} ->
	    gen_tcp:send(Sock, <<"DS",0>>),
	    main_loop(Sock, Ns);
	{tcp, Sock, <<"RG",Len:1/little-integer-unit:8,Bstring:Len/binary>>} ->
	    server_register(State, Bstring)
    end.

server_register(State = {Sock, _Ns, _Id, _Chan, client}, _) ->
    gen_tcp:send(Sock, <<"ER",0>>),
    chan_loop(State);
server_register(State = {Sock, Ns, Id, _Chan, server}, Bstring) ->
    Namestring = binary_to_list(Bstring),
    ns:add(Ns, Namestring, Id),
    gen_tcp:send(Sock, <<"OK",0>>),
    chan_loop(State).
