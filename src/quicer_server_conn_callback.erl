%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(quicer_server_conn_callback).
-behavior(quicer_conn_acceptor).
-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include("quicer_types.hrl").
-export([ init/1
        , new_conn/2
        , resumed/3
        , new_stream/3
        , connected/2
        , shutdown/3
        , transport_shutdown/3
        , peer_address_changed/3
        , local_address_changed/3
        , streams_available/4
        , peer_needs_streams/2
        , stream_closed/4
        , closed/3
        ]).

init(ConnOpts) when is_list(ConnOpts) ->
    init(maps:from_list(ConnOpts));
init(#{stream_opts := SOpts} = S) when is_list(SOpts) ->
    init(S#{stream_opts := maps:from_list(SOpts)});
init(ConnOpts) when is_map(ConnOpts) ->
    ConnOpts.

closed(_Conn, #{} = _Flags, S)->
    S.

new_conn(Conn, #{stream_opts := SOpts} = S) ->
    %% @TODO configurable behavior of spawing stream acceptor
    case quicer_stream:start_link(Conn, SOpts) of
        {ok, Pid} ->
            ok = quicer:async_handshake(Conn),
            {ok, S#{streams => [{Pid, undefined}]}};
        {error, _} = Error ->
            Error
    end.

resumed(Conn, Data, #{resumed_callback := ResumeFun} = S)
  when is_function(ResumeFun) ->
    ResumeFun(Conn, Data, S);
resumed(_Conn, _Data, S) ->
    {ok, S}.

connected(Conn, #{slow_start := false, stream_opts := SOpts} = S) ->
    %% @TODO configurable behavior of spawing stream acceptor
    quicer_stream:start_link(Conn, SOpts),
    {ok, S#{conn => Conn}};
connected(Conn, S) ->
    {ok, S#{conn => Conn}}.

%% handles stream when there is no stream acceptors.
new_stream(Conn, Stream, #{conn := Conn, streams := Streams, stream_opts := SOpts} = CBState) ->
    %% spawn new stream
    case quicer_stream:start_link(Stream, Conn, SOpts) of
        {ok, StreamOwner} ->
            handoff_stream(Stream, StreamOwner),
            {ok, CBState#{ streams := [ {StreamOwner, Stream} | Streams] }};
        Other ->
            Other
    end.

shutdown(Conn, _ErrorCode, S) ->
    quicer:async_close_connection(Conn),
    {ok, S}.

transport_shutdown(_C, _Reason, S) ->
    {ok, S}.

peer_address_changed(_C, _NewAddr, S) ->
    {ok, S}.

local_address_changed(_C, _NewAddr, S) ->
    {ok, S}.

streams_available(_C, _BidirCnt, _UnidirCnt, S) ->
    {ok, S}.

peer_needs_streams(_C, S) ->
    {ok, S}.

stream_closed(_Connecion, _Stream, _Flags, S) ->
    {ok, S}.


%% Internals
%% @doc
%%  handoff stream to another proc
%%  1) change stream owner to new pid
%%  2) forward all data to new pid
-spec handoff_stream(stream_handler(), pid()) -> ok.
handoff_stream(Stream, Owner) ->
    ?tp(debug, #{event=>?FUNCTION_NAME , module=>?MODULE, stream=>Stream, owner => Owner}),
    case quicer:controlling_process(Stream, Owner) of
        ok ->
            forward_stream_msgs(Stream, Owner, _ACC = []);
        {error, _Reason} = E->
            E
    end.

%% @doc Forward all erl msgs of the Stream to the Stream Owner
%% Stream Owner should block for the {owner_handoff, Msg} and then 'flush_done' msg,
%% -spec forward_stream_msgs(stream_handler(), pid()) -> ok.
-spec forward_stream_msgs(stream_handler(), pid(), list()) -> ok.
forward_stream_msgs(Stream, Owner, Acc) ->
    receive
        {quic, Data, Stream, _Offset, _Len, _Flag} = Msg when is_binary(Data) ->
            forward_stream_msgs(Stream, Owner, [Msg | Acc])
    after 0 ->
            Owner ! {stream_owner_handoff, self(), aggr_steam_data(Acc)},
            ok
    end.

aggr_steam_data([]) ->
    undefined;
aggr_steam_data(Acc) ->
    %% Maybe assert offset is 0
    lists:foldl(fun({quic, Bin, _Stream, _Offset, Len, Flag},
                    {BinAcc, LenAcc, FlagAcc}) ->
                        {[Bin | BinAcc], LenAcc + Len, FlagAcc bor Flag}
                end, {[], _Len = 0, _Flag = 0}, Acc).

-ifdef(EUNIT).


-endif.
