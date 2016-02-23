%%%-------------------------------------------------------------------
%%% @author Shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% Login gen_server. This server supports overall user login, logout,
%%% and register services as well as maintains logged in and registered uids.
%%%
%%% @end
%%% Created : 25. Aug 2015 9:11 PM
%%%-------------------------------------------------------------------
-module(login_server).
-author("Shuieryin").

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    is_uid_registered/1,
    is_in_registration/1,
    register_uid/2,
    registration_done/1,
    delete_player/1,
    login/2,
    is_uid_logged_in/1,
    logout/2,
    is_id_registered/1,
    start/0,
    stop/0,
    registered_player_uids/0,
    logout_all_players/0,
    logged_in_player_uids/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3,
    format_status/2
]).

-define(SERVER, ?MODULE).

-type uid_set() :: gb_sets:set(player_fsm:uid()).
-type id_set() :: gb_sets:set(player_fsm:id()).

-include("../data_type/player_profile.hrl").

-record(state, {
    registration_uids_set :: uid_set(),
    registered_uids_set :: uid_set(),
    logged_in_uids_set :: uid_set(),
    registering_uids_set :: uid_set(),
    registered_ids_set :: id_set(),
    born_type_info_map :: register_fsm:born_type_info_map()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts server by setting module name as server name.
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> gen:start_ret().
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Starts server by setting module name as server name without link.
%%
%% @end
%%--------------------------------------------------------------------
-spec start() -> gen:start_ret().
start() ->
    gen_server:start({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Stop server.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok.
stop() ->
    gen_server:cast(?SERVER, stop).

%%--------------------------------------------------------------------
%% @doc
%% Checks if uid has been registered.
%%
%% @end
%%--------------------------------------------------------------------
-spec is_uid_registered(Uid) -> boolean() when
    Uid :: player_fsm:uid().
is_uid_registered(Uid) ->
    gen_server:call(?MODULE, {is_uid_registered, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Checks if id has been registered.
%%
%% @end
%%--------------------------------------------------------------------
-spec is_id_registered(Id) -> boolean() when
    Id :: player_fsm:id().
is_id_registered(Id) ->
    gen_server:call(?MODULE, {is_id_registered, Id}).

%%--------------------------------------------------------------------
%% @doc
%% Retrieves all registered player uids.
%%
%% @end
%%--------------------------------------------------------------------
-spec registered_player_uids() -> uid_set().
registered_player_uids() ->
    gen_server:call(?MODULE, registered_player_uids).

%%--------------------------------------------------------------------
%% @doc
%% Checks if uid is in registration procedure.
%%
%% @end
%%--------------------------------------------------------------------
-spec is_in_registration(Uid) -> boolean() when
    Uid :: player_fsm:uid().
is_in_registration(Uid) ->
    gen_server:call(?MODULE, {is_in_registration, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Checks if uid is in registration procedure.
%%
%% @end
%%--------------------------------------------------------------------
-spec register_uid(DispatcherPid, Uid) -> ok when
    Uid :: player_fsm:uid(),
    DispatcherPid :: pid().
register_uid(DispatcherPid, Uid) ->
    gen_server:cast(?MODULE, {register_uid, DispatcherPid, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% This function is only called by regsiter_fsm when registration
%% procedure is done. It adds uid to registered uid set, save to
%% redis immediately, and log user in.
%%
%% @end
%%--------------------------------------------------------------------
-spec registration_done(PlayerProfile) -> ok when
    PlayerProfile :: #player_profile{}.
registration_done(PlayerProfile) ->
    gen_server:call(?MODULE, {registration_done, PlayerProfile}).

%%--------------------------------------------------------------------
%% @doc
%% This function deletes player in all states including redis. It logs
%% out player, delete player states from server state, and updates redis.
%%
%% @end
%%--------------------------------------------------------------------
-spec delete_player(Uid) -> ok when
    Uid :: player_fsm:uid().
delete_player(Uid) ->
    gen_server:call(?MODULE, {delete_user, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Logs user in by creating its own player_fsm process.
%%
%% @end
%%--------------------------------------------------------------------
-spec login(DispatcherPid, Uid) -> ok when
    DispatcherPid :: pid(),
    Uid :: player_fsm:uid().
login(DispatcherPid, Uid) ->
    gen_server:call(?MODULE, {login, DispatcherPid, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Checks if uid has logged in.
%%
%% @end
%%--------------------------------------------------------------------
-spec is_uid_logged_in(Uid) -> boolean() when
    Uid :: player_fsm:uid().
is_uid_logged_in(Uid) ->
    gen_server:call(?MODULE, {is_uid_logged_in, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Logs user out by destroying its player_fsm process.
%%
%% @end
%%--------------------------------------------------------------------
-spec logout(DispatcherPid, Uid) -> ok when
    DispatcherPid :: pid(),
    Uid :: player_fsm:uid().
logout(DispatcherPid, Uid) ->
    gen_server:call(?MODULE, {logout, DispatcherPid, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Force logout all players. This is function is called when stopping server only.
%% @see cm:q/0.
%%
%% @end
%%--------------------------------------------------------------------
-spec logout_all_players() -> ok.
logout_all_players() ->
    gen_server:call(?MODULE, logout_all_players).

%%--------------------------------------------------------------------
%% @doc
%% Retrieves all logged in player uids.
%%
%% @end
%%--------------------------------------------------------------------
-spec logged_in_player_uids() -> uid_set().
logged_in_player_uids() ->
    gen_server:call(?MODULE, logged_in_player_uids).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server by retrieves registered uid set from redis
%% and cache to a gb_set, and creates new gb_sets for registering uids
%% and logged in uids for caching.
%%
%% @end
%%--------------------------------------------------------------------
-spec init([]) ->
    {ok, State} |
    {ok, State, timeout() | hibernate} |
    {stop, Reason} |
    ignore when

    State :: #state{},
    Reason :: term(). % generic term
init([]) ->
    io:format("~p starting...", [?MODULE]),
    RegisteredUidsSet =
        case redis_client_server:get(registered_uids_set) of
            undefined ->
                NewRegisteredUidsSet = gb_sets:new(),
                true = redis_client_server:set(registered_uids_set, NewRegisteredUidsSet, true),
                NewRegisteredUidsSet;
            UidsSet ->
                UidsSet
        end,

    RegisteredIdsSet =
        case redis_client_server:get(registered_ids_set) of
            undefined ->
                NewRegisteredIdsSet = gb_sets:new(),
                true = redis_client_server:set(registered_uids_set, NewRegisteredIdsSet, true),
                NewRegisteredIdsSet;
            IdsSet ->
                IdsSet
        end,

    BornTypeInfoMap = common_server:runtime_data(born_type_info),
    State = #state{
        registering_uids_set = gb_sets:new(),
        registered_uids_set = RegisteredUidsSet,
        registered_ids_set = RegisteredIdsSet,
        logged_in_uids_set = gb_sets:new(),
        born_type_info_map = BornTypeInfoMap
    },

    io:format("started~n"),
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request, From, State) ->
    {reply, Reply, NewState} |
    {reply, Reply, NewState, timeout() | hibernate} |
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, Reply, NewState} |
    {stop, Reason, NewState} when

    Request :: {is_uid_registered | is_in_registration | delete_user, Uid} |
    registered_player_uids |
    logged_in_player_uids |
    {registration_done, PlayerProfile} |
    {login, DispatcherPid, Uid} |
    {logout, DispatcherPid, Uid},

    Reply :: IsUidRegistered | IsIdRegistered | IsInRegistration | IsUserLoggedIn | ok,

    Uid :: player_fsm:uid(),
    IsUidRegistered :: boolean(),
    IsIdRegistered :: boolean(),
    IsInRegistration :: boolean(),
    IsUserLoggedIn :: boolean(),
    PlayerProfile :: #player_profile{},
    DispatcherPid :: pid(),

    From :: {pid(), Tag :: term()}, % generic term
    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_call(
    {is_uid_registered, Uid},
    _From,
    #state{
        registered_uids_set = RegisteredUidsSet
    } = State
) ->
    {reply, gb_sets:is_element(Uid, RegisteredUidsSet), State};
handle_call(
    {is_id_registered, Id},
    _From,
    #state{
        registered_ids_set = RegisteredIdsSet
    } = State
) ->
    {reply, gb_sets:is_element(Id, RegisteredIdsSet), State};
handle_call(
    {is_in_registration, Uid},
    _From,
    #state{
        registering_uids_set = RegisteringUidsSet
    } = State
) ->
    Result = gb_sets:is_element(Uid, RegisteringUidsSet),
    {reply, Result, State};
handle_call(
    {delete_user, Uid},
    _From,
    #state{
        registered_uids_set = RegisteredUidsSet
    } = State
) ->
    LoggedOutState = logout(internal, Uid, State),
    ok = cm:until_process_terminated(Uid),
    UpdatedRegisteredUidsSet = gb_sets:delete(Uid, RegisteredUidsSet),

    ok = redis_client_server:async_del([Uid], false),
    ok = redis_client_server:async_set(registered_uids_set, UpdatedRegisteredUidsSet, true),

    {reply, ok, LoggedOutState#state{registered_uids_set = UpdatedRegisteredUidsSet}};
handle_call(
    {is_uid_logged_in, Uid},
    _From,
    #state{
        logged_in_uids_set = LoggedUidsSet
    } = State
) ->
    {reply, gb_sets:is_element(Uid, LoggedUidsSet), State};
handle_call(
    registered_player_uids,
    _From,
    #state{
        registered_uids_set = RegisteredUidsSet
    } = State
) ->
    {reply, RegisteredUidsSet, State};
handle_call(
    logged_in_player_uids,
    _From,
    #state{
        logged_in_uids_set = LoggedInUidsSet
    } = State
) ->
    {reply, LoggedInUidsSet, State};
handle_call(
    {
        registration_done,
        #player_profile{
            uid = Uid,
            id = Id
        } = PlayerProfile
    },
    _From,
    #state{
        registering_uids_set = RegisteringUidsSet,
        registered_uids_set = RegisteredUidsSet,
        registered_ids_set = RegisteredIdsSet
    } = State
) ->
    UpdatedRegisteredUidsSet = gb_sets:add(Uid, RegisteredUidsSet),

    ok = redis_client_server:async_set(registered_uids_set, UpdatedRegisteredUidsSet, false),

    UpdatedRegisteredIdsSet = gb_sets:add(Id,
        case redis_client_server:get(Uid) of
            #player_profile{
                id = ExistingId
            } ->
                gb_sets:del_element(ExistingId, RegisteredIdsSet);
            _NotFound ->
                RegisteredIdsSet
        end),
    ok = redis_client_server:async_set(registered_ids_set, UpdatedRegisteredIdsSet, false),
    true = redis_client_server:set(Uid, PlayerProfile, true),

    UpdatedState = State#state{
        registered_uids_set = UpdatedRegisteredUidsSet,
        registered_ids_set = UpdatedRegisteredIdsSet,
        registering_uids_set = gb_sets:del_element(Uid, RegisteringUidsSet)
    },
    {reply, ok, UpdatedState};
handle_call(
    {login, DispatcherPid, Uid},
    _From,
    #state{
        logged_in_uids_set = LoggedInUidsSet
    } = State
) ->
    UpdatedLoggedInUidsSet =
        case gb_sets:is_element(Uid, LoggedInUidsSet) of
            false ->
                {ok, _Pid} = player_fsm_sup:add_child(Uid, DispatcherPid),
                gb_sets:add(Uid, LoggedInUidsSet);
            true ->
                ok = player_fsm:response_content(Uid, [{nls, already_login}], DispatcherPid),
                LoggedInUidsSet
        end,

    {reply, ok, State#state{logged_in_uids_set = UpdatedLoggedInUidsSet}};
handle_call({logout, DispatcherPid, Uid}, _From, State) ->
    ok = player_fsm:response_content(Uid, [{nls, already_logout}], DispatcherPid),
    UpdatedState = logout(internal, Uid, State),
    {reply, ok, UpdatedState};
handle_call(
    logout_all_players,
    _From,
    #state{
        logged_in_uids_set = LoggedInUidsSet
    } = State
) ->
    {reply, logout_all_players(LoggedInUidsSet), State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request, State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, NewState} when

    Request ::
    {register_uid, DispatcherPid, Uid} |
    stop,

    DispatcherPid :: pid(),
    Uid :: player_fsm:uid(),
    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_cast(
    {register_uid, DispatcherPid, Uid},
    #state{
        born_type_info_map = BornTypeInfoMap
    } = State
) ->
    UpdatedState =
        case register_fsm_sup:add_child(DispatcherPid, Uid, BornTypeInfoMap) of
            {ok, _Pid} ->
                error_logger:info_msg("Started register fsm successfully.~nUid:~p~n", [Uid]),
                State#state{
                    registering_uids_set = gb_sets:add(Uid, State#state.registering_uids_set)
                };
            {error, Reason} ->
                error_logger:error_msg("Failed to start register fsm.~nUid:~p~nReason:~p~n", [Uid, Reason]),
                State
        end,
    {noreply, UpdatedState};
handle_cast(stop, State) ->
    {stop, normal, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info | timeout(), State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, NewState} when

    Info :: term(), % generic term
    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason, State) -> ok when
    Reason :: (normal | shutdown | {shutdown, term()} | term()), % generic term
    State :: #state{}.
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn, State, Extra) ->
    {ok, NewState} |
    {error, Reason} when

    OldVsn :: term() | {down, term()}, % generic term
    State :: #state{},
    Extra :: term(), % generic term
    NewState :: State,
    Reason :: term(). % generic term
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is useful for customising the form and
%% appearance of the gen_server status for these cases.
%%
%% @spec format_status(Opt, StatusData) -> Status
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt, StatusData) -> Status when
    Opt :: 'normal' | 'terminate',
    StatusData :: [PDict | State],
    PDict :: [{Key :: term(), Value :: term()}], % generic term
    State :: #state{},
    Status :: term(). % generic term
format_status(Opt, StatusData) ->
    gen_server:format_status(Opt, StatusData).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% This function is called by "delete_user" and "logout" from
%% handle_call/3 and handle_cast/2.
%%
%% Logs user out by destroying its player_fsm process.
%%
%% @end
%%--------------------------------------------------------------------
-spec logout(internal, Uid, State) -> UpdatedState when
    Uid :: player_fsm:uid(),
    State :: #state{},
    UpdatedState :: State.
logout(
    internal,
    Uid,
    #state{
        logged_in_uids_set = LoggedInUidsSet
    } = State
) ->
    UpdatedLoggedInUidsSet =
        case gb_sets:is_element(Uid, LoggedInUidsSet) of
            false ->
                LoggedInUidsSet;
            true ->
                ok = player_fsm:logout(Uid),
                gb_sets:del_element(Uid, LoggedInUidsSet)
        end,
    State#state{
        logged_in_uids_set = UpdatedLoggedInUidsSet
    }.

%%--------------------------------------------------------------------
%% @doc
%% Logout all players.
%% @see logout_all_players/0.
%%
%% @end
%%--------------------------------------------------------------------
-spec logout_all_players(LoggedInUidsSet) -> ok when
    LoggedInUidsSet :: gb_sets:set().
logout_all_players(LoggedInUidsSet) ->
    case gb_sets:is_empty(LoggedInUidsSet) of
        true ->
            ok;
        false ->
            Iter = gb_sets:iterator(LoggedInUidsSet),
            do_logout_all_players(gb_sets:next(Iter))
    end.

%%--------------------------------------------------------------------
%% @doc
%% Logout all players.
%% @see logout_all_players/1.
%%
%% @end
%%--------------------------------------------------------------------
-spec do_logout_all_players(Next) -> ok when
    Next :: {Uid, Iter} | none,
    Uid :: player_fsm:uid(),
    Iter :: gb_sets:iter().
do_logout_all_players({Uid, Iter}) ->
    ok = player_fsm:logout(Uid),
    do_logout_all_players(gb_sets:next(Iter));
do_logout_all_players(none) ->
    ok.