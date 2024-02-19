%%--------------------------------------------------------------------
%% Copyright (c) 2021 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(quicer_echo_server_stream_callback).
-behavior(quicer_stream).

-export([
    init_handoff/4,
    post_handoff/3,
    new_stream/3,
    start_completed/3,
    send_complete/3,
    peer_send_shutdown/3,
    peer_send_aborted/3,
    peer_receive_aborted/3,
    send_shutdown_complete/3,
    stream_closed/3,
    peer_accepted/3,
    passive/3,
    handle_call/4
]).

-export([handle_stream_data/4]).

%% @doc handle handoff from other stream owner.
init_handoff(Stream, _StreamOpts, Conn, #{is_orphan := true, flags := Flags}) ->
    InitState = #{
        stream => Stream,
        conn => Conn,
        is_local => false,
        is_unidir => quicer:is_unidirectional(Flags),
        echo_stream => undefined,
        sent_bytes => 0
    },
    %ct:pal("init_handoff ~p", [{InitState, StreamOpts}]),
    {ok, InitState}.

post_handoff(Stream, _PostData, State) ->
    quicer:setopt(Stream, active, true),
    {ok, State}.

%% @doc accepted new stream.
new_stream(Stream, #{flags := Flags} = StreamOpts, Conn) ->
    InitState = #{
        stream => Stream,
        conn => Conn,
        is_local => false,
        echo_stream => undefined,
        stream_opts => StreamOpts,
        is_unidir => quicer:is_unidirectional(Flags),
        sent_bytes => 0
    },
    {ok, InitState}.

peer_accepted(_Stream, _Flags, S) ->
    {ok, S}.

peer_receive_aborted(_Stream, _Flags, S) ->
    {ok, S}.

peer_send_aborted(Stream, _Flags, S) ->
    quicer:async_close_stream(Stream),
    {ok, S}.

peer_send_shutdown(Stream, _Flags, S) ->
    quicer:async_close_stream(Stream),
    {ok, S}.

send_complete(_Stream, _Flags, S) ->
    {ok, S}.

send_shutdown_complete(_Stream, _Flags, S) ->
    {ok, S}.

start_completed(_Stream, _Flags, S) ->
    {ok, S}.

handle_stream_data(
    Stream,
    Bin,
    _Opts,
    #{
        sent_bytes := Cnt,
        stream_opts := StreamOpts,
        conn := Conn,
        echo_stream := undefined,
        stream := Stream
    } = State
) ->
    case maps:get(is_echo_new_stream, StreamOpts, false) of
        false ->
            case quicer:send(Stream, echo_msg(Bin, State)) of
                {ok, Size} ->
                    {ok, State#{sent_bytes => Cnt + Size}};
                _ ->
                    %% handle error in test aborted.
                    {ok, State}
            end;
        true ->
            %% echo reply with a new stream from server to client.
            {ok, EchoStream} = quicer:start_stream(Conn, StreamOpts),
            case quicer:send(EchoStream, echo_msg(Bin, State)) of
                {ok, Size} ->
                    {ok, State#{sent_bytes => Cnt + Size, echo_stream => EchoStream}};
                _ ->
                    %% handle error in test aborted.
                    {ok, State}
            end
    end;
handle_stream_data(
    Stream,
    Bin,
    _Opts,
    #{
        sent_bytes := Cnt,
        echo_stream := _Ignore
    } = State
) ->
    {ok, Size} = quicer:send(Stream, Bin),
    {ok, State#{sent_bytes => Cnt + Size}}.

passive(_Stream, undefined, S) ->
    ct:fail("Steam go into passive mode"),
    {stop, no_passive, S}.

handle_call(_Stream, _Request, _Opts, _CBState) ->
    ok.

stream_closed(_Stream, _Flags, S) ->
    {stop, normal, S}.

%% For snabbkaffe, RID is meaningful on the same node.
echo_msg(<<"__STATE__">>, State) ->
    quicer_test_lib:encode_stream_term(State);
echo_msg(Msg, _State) ->
    Msg.
