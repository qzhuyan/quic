-module(prop_quicer_fuzz).

-include_lib("proper/include/proper.hrl").
-include_lib("stdlib/include/assert.hrl").

%%%%%%%%%%%%%%%%%%
%%% Properties %%%
%%%%%%%%%%%%%%%%%%
prop_connect_badargs() ->
    ?FORALL({Host, Port, Opts, Timeout}, {term(), term(), opts(), timeout_max_1000()},
        begin
            should_error(quicer:connect(Host, Port, Opts, Timeout))
        end).

prop_handshake_badargs() ->
    ?FORALL({Conn, Timeout}, {term(), timeout_max_1000()},
            begin
                ok =/= quicer:handshake(Conn, Timeout)
            end).

prop_accept_badargs() ->
    ?FORALL({Sock, Opts, Timeout}, {term(), opts(), timeout_max_1000()},
            begin
                should_error(quicer:accept(Sock, Opts, Timeout))
            end).

prop_shutdown_connection_badarg() ->
    ?FORALL({Conn, Timeout}, {term(), timeout_max_1000()},
            begin
                should_error(quicer:shutdown_connection(Conn, Timeout))
            end).

prop_accept_stream_badarg() ->
    ?FORALL({Conn, Opts, Timeout}, {term(), opts(), timeout_max_1000()},
            begin
                should_error(quicer:accept_stream(Conn, Opts, Timeout))
            end).

prop_start_stream_badarg() ->
    ?FORALL({Conn, Opts}, {term(), opts()},
            begin
                should_error(quicer:start_stream(Conn, Opts))
            end).

prop_send_badarg() ->
    ?FORALL({Stream, Data, Flag}, {term(), term(), integer()},
            begin
                should_error(quicer:send(Stream, Data, Flag))
            end).

prop_recv_badarg() ->
    ?FORALL({Stream, Count}, {term(), term()},
            begin
                should_error(quicer:recv(Stream, Count))
            end).

prop_send_dgram_badarg() ->
    ?FORALL({Stream, Data}, {term(), term()},
            begin
                should_error(quicer:send_dgram(Stream, Data))
            end).

prop_shutdown_stream_badarg() ->
    ?FORALL({Stream, Flags, ErrorCode, Timeout}, {term(), integer(), term(), timeout_max_1000()},
            begin
                should_error(quicer:shutdown_stream(Stream, Flags, ErrorCode, Timeout))
            end).

prop_close_stream_badarg() ->
    ?FORALL({Stream, Flags, ErrorCode, Timeout}, {term(), integer(), term(), timeout_max_1000()},
            begin
                should_error(quicer:close_stream(Stream, Flags, ErrorCode, Timeout))
            end).

prop_setopt_badarg() ->
    ?FORALL({Handle, Opt, Val, Level}, {handle(), term(), term(), optlevel()},
            begin
                should_error(quicer:setopt(Handle, Opt, Val, Level))
            end).

prop_getstat_badarg() ->
    ?FORALL({Handle, Cnts}, {handle(), oneof([list(atom()), list(string())])},
            begin
                should_error(quicer:getstat(Handle, Cnts))
            end).

prop_peername_badarg() ->
    ?FORALL(Handle, handle(),
            begin
                should_error(quicer:peername(Handle))
            end).

prop_controlling_process_badarg() ->
    ?FORALL({Handle, Owner}, {handle(), owner()},
            begin
                should_error(quicer:controlling_process(Handle, Owner))
            end).


%%%%%%%%%%%%%%%
%%% Helpers %%%
%%%%%%%%%%%%%%%
should_error({error, _}) -> true;
should_error({error, _, _}) -> true;
should_error(ok) -> false;
should_error(_) -> false.

%%%%%%%%%%%%%%%%%%
%%% Generators %%%
%%%%%%%%%%%%%%%%%%
opts() ->
    oneof([map(term(), term()), list({term(), term()})]).

timeout_max_1000() ->
    range(0, 1000).

optlevel() ->
    term().

handle() ->
    term().

owner() ->
    %% some pid
    oneof([term(), self()]).
