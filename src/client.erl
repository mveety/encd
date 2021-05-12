%% encd -- erlang netchannel daemon
%% Copyright Matthew Veety, 2021. Under BSD license.

-module(client).
-export([start/0, start/1, start/2, handler/2]).

start() ->
    start(2426).
start(Port) ->
    start({127,0,0,1}, Port).
start(Addr, Port) ->
    Starter = self(),
    {ok, Sock} = gen_tcp:connect(Addr, Port, [{active, false}
					     ,{keepalive, true}
					     ,binary]),
    Client = spawn(fun() -> ?MODULE:handler(Sock, Starter) end),
    gen_tcp:controlling_process(Sock, Client),
    receive
	{Client, ok} ->
	    {ok, Client};
	{Client, error} ->
	    error
    end.

handler(Sock, Starter) ->
    inet:setopts(Sock, [{active, true}]),
    gen_tcp:send(Sock, <<"OK",0>>),
    receive
	{tcp, Sock, <<"OK",0>>} ->
	    Starter ! {self(), ok},
	    main_loop(Sock);
	{tcp_close, Sock} ->
	    Starter ! {self(), error},
	    exit(disconnect)
    end.

heartbeat(Sock) ->
    gen_tcp:send(Sock, <<"HB", 0>>),
    receive
	{tcp, Sock, <<"HB", 0>>} ->
	    ok
    after
	10000 ->
	    error
    end.

server_lost() ->
    receive
	{Proc, _, _} ->
	    Proc ! {self(), lost};
	{Proc, _} ->
	    Proc ! {self(), lost}
    end,
    exit(disconnect).

main_loop(Sock) ->
    receive
	{Proc, name, Name} ->
	    name_to_id(Sock, Proc, Name);
	{Proc, connect, Id} ->
	    connect(Sock, Proc, Id);
	{Proc, create} ->
	    create(Sock, Proc);
	{Proc, disconnect} ->
	    disconnect(Sock, Proc)
    after
	10000 ->
	    case heartbeat(Sock) of
		ok ->
		    main_loop(Sock);
		error ->
		    server_lost()
	    end
    end.

name_to_id(Sock, Proc, Name) ->
    Len = length(Name),
    Bstr = list_to_binary(Name),
    gen_tcp:send(Sock, <<"NM", Len:1/little-integer-unit:8, Bstr:Len/binary>>),
    receive
	{tcp, Sock, <<"NF",0>>} ->
	    Proc ! {self(), error, not_found},
	    main_loop(Sock);
	{tcp, Sock, <<"ID",Id:1/little-integer-unit:32>>} ->
	    Proc ! {self(), ok, Id},
	    main_loop(Sock)
    end.

disconnect(Sock, Proc) ->
    gen_tcp:send(Sock, <<"DS",0>>),
    receive
	{tcp, Sock, <<"DS",0>>} ->
	    Proc ! {self(), disconnect},
	    gen_tcp:close(Sock),
	    exit(ok);
	{tcp_close, Sock} ->
	    Proc ! {self(), disconnect},
	    exit(ok)
    end.

connect(Sock, Proc, Id) ->
    Msg = <<"CO", Id:1/little-integer-unit:32>>,
    gen_tcp:send(Sock, Msg),
    receive
	{tcp, Sock, <<"OK",0>>} ->
	    Proc ! {self(), ok},
	    chan_loop(Sock);
	{tcp, Sock, <<"NF",0>>} ->
	    Proc ! {self(), error, not_found},
	    main_loop(Sock)
    end.

create(Sock, Proc) ->
    gen_tcp:send(Sock, <<"CR",0>>),
    receive
	{tcp, Sock, <<"ID", Id:1/little-integer-unit:32>>} ->
	    Proc ! {self(), ok, Id},
	    chan_loop(Sock)
    end.

chan_loop(Sock) ->
    receive
	{Proc, send, Data} ->
	    send(Sock, Proc, Data);
	{Proc, recv} ->
	    recv(Sock, Proc);
	{Proc, close} ->
	    close(Sock, Proc);
	{Proc, disconnect} ->
	    chan_disconnect(Sock, Proc);
	{Proc, register, Name} ->
	    chan_register(Sock, Proc, Name)
    after
	10000 ->
	    case heartbeat(Sock) of
		ok ->
		    chan_loop(Sock);
		error ->
		    server_lost()
	    end
    end.

send(Sock, Proc, Data) ->
    Len = byte_size(Data),
    Msg = <<"SN", Len:1/little-integer-unit:32, Data:Len/binary>>,
    gen_tcp:send(Sock, Msg),
    send_loop(Sock, Proc, Data).
send_loop(Sock, Proc, Data) ->
    receive
	{tcp, Sock, <<"OK",0>>} ->
	    Proc ! {self(), ok},
	    chan_loop(Sock);
	{tcp, Sock, <<"CL",0>>} ->
	    Proc ! {self(), close},
	    main_loop(Sock)
    after
	10000 ->
	    case heartbeat(Sock) of
		ok ->
		    send_loop(Sock, Proc, Data);
		error ->
		    Proc ! {self(), lost}
	    end
    end.

recv(Sock, Proc) ->
    gen_tcp:send(Sock, <<"RV",0>>),
    recv_loop(Sock, Proc).
recv_loop(Sock, Proc) ->
    receive
	{tcp, Sock, <<"R0", Dlen:1/little-integer-unit:32, Data:Dlen/binary>>} ->
	    Proc ! {self(), ok, Data},
	    chan_loop(Sock);
	{tcp, Sock, <<"CL",0>>} ->
	    Proc ! {self(), close},
	    main_loop(Sock)
    after
	10000 ->
	    case heartbeat(Sock) of
		ok ->
		    recv_loop(Sock, Proc);
		error ->
		    Proc ! {self(), lost}
	    end
    end.

chan_disconnect(Sock, Proc) ->
    gen_tcp:send(Sock, <<"DS",0>>),
    receive
	{tcp, Sock, <<"DS",0>>} ->
	    Proc ! {self(), ok},
	    main_loop(Sock)
    end.

chan_register(Sock, Proc, Name) ->
    Bname = list_to_binary(Name),
    Len = length(Name),
    Msg = <<"RG", Len:1/little-integer-unit:8, Bname:Len/binary>>,
    gen_tcp:send(Sock, Msg),
    receive
	{tcp, Sock, <<"ER",0>>} ->
	    Proc ! {self(), error},
	    chan_loop(Sock);
	{tcp, Sock, <<"OK",0>>} ->
	    Proc ! {self(), ok},
	    chan_loop(Sock)
    end.

close(Sock, Proc) ->
    gen_tcp:send(Sock, <<"CL",0>>),
    receive
	{tcp, Sock, <<"CL",0>>} ->
	    Proc ! {self(), ok},
	    main_loop(Sock)
    end.
