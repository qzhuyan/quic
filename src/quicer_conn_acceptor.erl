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
-module(quicer_conn_acceptor).
-include_lib("snabbkaffe/include/snabbkaffe.hrl").
-include("quicer_types.hrl").

-behaviour(gen_server).

%%      init while spawn
%%      a. init callback state
-callback init(_Args) -> _State.

%%      Handle new incoming connection
%%      a. Reject (close) the connection
%%      b. Continue handshake,
%%      c. Spawn stream acceptors and continue with handshake. (accept new stream call could be sync/async)
-callback new_conn(connection_handler(), _OldState) -> {ok, _NewState} | {error, term()}.

%%      Handle new stream
%%      a. spawn new process to handle this stream
%%      b. just be the owner of stream
%%
%%      Suggest to keep a stream & owner pid mapping in the callback state
-callback new_stream(stream_handler(), _OldState) -> {ok, pid()} | {error, term()}.

%%      Handle connection handshake done
%%      a. init new streams from the Server
-callback connected(connection_handler(), _OldState) -> {ok, _NewState} | {error, term()}.

%%      Handle connection shutdown initiated by peer
%%
-callback shutdown(connection_handler(), _OldState) -> {ok, _State}.

%%      Handle stream closed, this means peer side shutdown the receiving
%%      but our end could still keep sending
%% a. forward a msg to the (new) owner process
%%
-callback stream_closed(stream_handler(), _OldState) -> {ok, _State}.

-optional_callbacks([stream_closed/2]).
%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).

-record(state, { listener :: quicer:listener_handler()
               , sup :: pid()
               , conn = undefined
               , opts :: {quicer_listener:listener_opts(),
                          conn_opts(),
                          quicer_steam:stream_opts()}
               , callback :: module()
               , callback_state :: map()
               }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link(Listener::quicer:listener_handler(),
                 ConnOpts :: map(), Sup :: pid()) -> {ok, Pid :: pid()} |
          {error, Error :: {already_started, pid()}} |
          {error, Error :: term()} |
          ignore.
start_link(Listener, ConnOpts, Sup) ->
    gen_server:start_link(?MODULE, [Listener, ConnOpts, Sup], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) -> {ok, State :: term()} |
          {ok, State :: term(), Timeout :: timeout()} |
          {ok, State :: term(), hibernate} |
          {stop, Reason :: term()} |
          ignore.
init([Listener, {LOpts, COpts, SOpts}, Sup]) when is_list(COpts) ->
    init([Listener, {LOpts, maps:from_list(COpts), SOpts}, Sup]);
init([Listener, {_, #{conn_callback := CallbackModule} = COpts, SOpts} = Opts, Sup]) ->
    process_flag(trap_exit, true),
    %% Async Acceptor
    {ok, Listener} = quicer_nif:async_accept(Listener, COpts),
    {ok, #state{ listener = Listener
               , callback = CallbackModule
               , callback_state = CallbackModule:init(COpts#{stream_opts => SOpts})
               , opts = Opts
               , sup = Sup}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), term()}, State :: term()) ->
          {reply, Reply :: term(), NewState :: term()} |
          {reply, Reply :: term(), NewState :: term(), Timeout :: timeout()} |
          {reply, Reply :: term(), NewState :: term(), hibernate} |
          {noreply, NewState :: term()} |
          {noreply, NewState :: term(), Timeout :: timeout()} |
          {noreply, NewState :: term(), hibernate} |
          {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
          {stop, Reason :: term(), NewState :: term()}.
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request :: term(), State :: term()) ->
          {noreply, NewState :: term()} |
          {noreply, NewState :: term(), Timeout :: timeout()} |
          {noreply, NewState :: term(), hibernate} |
          {stop, Reason :: term(), NewState :: term()}.
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info :: timeout() | term(), State :: term()) ->
          {noreply, NewState :: term()} |
          {noreply, NewState :: term(), Timeout :: timeout()} |
          {noreply, NewState :: term(), hibernate} |
          {stop, Reason :: normal | term(), NewState :: term()}.
handle_info({quic, new_conn, C},
            #state{callback = M, sup = Sup, callback_state = CBState} = State) ->
    ?tp(quic_new_conn, #{module=>?MODULE, conn=>C}),
    %% I become the connection owner, I should start an new acceptor.
    supervisor:start_child(Sup, [Sup]),
    {ok, NewCBState} = M:new_conn(C, CBState),
    {noreply, State#state{conn = C, callback_state = NewCBState} };

handle_info({quic, connection_resumed, C, ResumeData},
            #state{callback = M, callback_state = CBState} = State) ->
    case erlang:function_exported(M, resumed, 3) of
        true ->
            {ok, NewCBState} = M:resumed(C, ResumeData, CBState),
            {noreply, State#state{callback_state = NewCBState}};
        false ->
            {noreply, State}
    end;

handle_info({quic, connected, C}, #state{ conn = C
                                        , callback = M
                                        , callback_state = CbState} = State) ->
    ?tp(quic_connected_slow, #{module=>?MODULE, conn=>C}),
    {ok, NewCBState} = M:connected(C, CbState),
    {noreply, State#state{ callback_state = NewCBState }};

handle_info({quic, new_stream, Stream}, #state{ conn = C
                                              , callback = M
                                              , callback_state = CbState} = State) ->
    %% Best practice:
    %%   One connection will have a control stream that have the same life cycle as the connection.
    %%   The connection may spawn one *control stream* acceptor before starting the handshake
    %%   AND the stream acceptor should accept new stream so it will likely pick up the control stream
    %% note, by desgin, control stream doesn't have to be the first stream initiated.
    %% here, it handles new stream when there is no available stream acceptor for the connection.
    ?tp(debug, #{module=>?MODULE, conn=>C, stream=>Stream, event=>new_stream}),
    NewCBState = case erlang:function_exported(M, new_stream, 2) of
                     true ->
                         case M:new_stream(Stream, CbState) of
                             {ok, NewS} -> NewS;
                             {error, Reason} when is_integer(Reason) -> %% @TODO most likely it won't be a integer
                                 %% We ignore the return, stream could be closed already.
                                 _ = quicer:async_shutdown_connection(Stream,
                                                                      ?QUIC_STREAM_SHUTDOWN_FLAG_ABORT, Reason)
                         end;
                     false ->
                         %% Backward compatibility
                         CbState
                 end,
    {noreply, State#state{ callback_state = NewCBState }};


%% handle stream close, the process is the owner of stream or it is during ownership handoff.
handle_info({quic, closed, Stream, ConnectionShutdownFlag},
            #state{callback = M,
                   conn = C,
                   callback_state = CbState} = State)->
    ?tp(debug, #{module=>?MODULE, conn=>C, stream=>Stream, event=>stream_closed}),
    NewCBState = case erlang:function_exported(M, stream_closed, 3) of
                     true ->
                         case M:stream_closed(Stream, ConnectionShutdownFlag, CbState) of
                             {ok, NewCBState0} ->
                                 NewCBState0;
                             {error, _Reason} ->
                                 CbState
                         end;
                     false ->
                         CbState
                 end,
    {noreply, State#state{ callback_state = NewCBState }};

handle_info({'EXIT', _Pid, {shutdown, normal}}, State) ->
    %% exit signal from stream
    {noreply, State};

handle_info({'EXIT', _Pid, {shutdown, _Other}}, State) ->
    %% @todo
    {noreply, State};

handle_info({'EXIT', _Pid, normal}, State) ->
    %% @todo
    {noreply, State};

handle_info({quic, transport_shutdown, C, Reason}, #state{ conn = C
                                                         , callback = M
                                                         , callback_state = CbState} = State) ->
    ?tp(quic_transport_shutdown, #{module=>?MODULE, conn=>C}),
    case erlang:function_exported(M, transport_shutdown, 3) of
        true ->
            {ok, NewCBState} = M:transport_shutdown(C, Reason, CbState),
            {noreply, State#state{ callback_state = NewCBState }};
        false ->
            {noreply, State}
    end;

handle_info({quic, shutdown, C}, #state{conn = C, callback = M,
                                        callback_state = CBState} = State) ->
    ?tp(quic_shutdown, #{module=>?MODULE}),
    M:shutdown(C, CBState),
    {noreply, State};

handle_info({quic, closed, C}, #state{conn = C} = State) ->
    %% @todo, connection closed
    ?tp(quic_closed, #{module=>?MODULE}),
    {stop, normal, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason :: normal | shutdown | {shutdown, term()} | term(),
                State :: term()) -> any().
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn :: term() | {down, term()},
                  State :: term(),
                  Extra :: term()) -> {ok, NewState :: term()} |
          {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for changing the form and appearance
%% of gen_server status when it is returned from sys:get_status/1,2
%% or when it appears in termination error logs.
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt :: normal | terminate,
                    Status :: list()) -> Status :: term().
format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
