-module(command_dispatcher).
%% API
-export([start/1,
    return_text/2,
    pending_text/3]).

%%%-------------------------------------------------------------------
%%% @author Shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 19. Aug 2015 10:06 PM
%%%-------------------------------------------------------------------
-author("Shuieryin").

-define(MAX_TEXT_SIZE, 2048).
-define(EMPTY_RESPONSE, <<>>).
-define(WECHAT_TOKEN, <<"collinguo">>).

-export_type([uid_profile/0]).

-type uid_profile() :: #{uid => atom(), gender => atom(), born_month => 1..12, args => [term()]}.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Validate signature and handel message
%%
%% @end
%%--------------------------------------------------------------------
-spec start(Req) -> string() when
    Req :: cowboy_req:req().
start(Req) ->
    case cowboy_req:qs(Req) of
        <<>> ->
            IsWechatDebug = common_server:is_wechat_debug(),
            case IsWechatDebug of
                true ->
                    process_request(Req);
                _ ->
                    error_logger:error_msg("Header params empty~n", []),
                    ?EMPTY_RESPONSE
            end;
        HeaderParams ->
            ParamsMap = gen_qs_params_map(size(HeaderParams) - 1, HeaderParams, #{}),
            error_logger:info_msg("ParamsMap:~p~n", [ParamsMap]),
            ValidationParamsMap = maps:with([signature, timestamp, nonce], ParamsMap),
            case validate_signature(ValidationParamsMap) of
                true ->
                    case maps:is_key(echostr, ParamsMap) of
                        false ->
                            process_request(Req);
                        _ ->
                            error_logger:info_msg("Connectivity success~n", []),
                            maps:get(echostr, ParamsMap)
                    end;
                _ ->
                    ?EMPTY_RESPONSE
            end
    end.

-spec gen_qs_params_map(Pos, Bin, ParamsMap) -> map() when
    Pos :: integer(),
    Bin :: binary(),
    ParamsMap :: map().
gen_qs_params_map(-1, _, ParamsMap) ->
    ParamsMap;
gen_qs_params_map(Pos, Bin, ParamsMap) ->
    {ValueBin, CurPosByValue} = qs_value(binary:at(Bin, Pos), [], Pos - 1, Bin),
    {KeyBin, CurPosByKey} = qs_key(binary:at(Bin, CurPosByValue), [], CurPosByValue - 1, Bin),
    gen_qs_params_map(CurPosByKey, Bin, maps:put(binary_to_atom(KeyBin, unicode), ValueBin, ParamsMap)).

-spec qs_key(CurByte, KeyBinList, Pos, SrcBin) -> {binary(), integer()} when
    CurByte :: byte(),
    KeyBinList :: [byte()],
    Pos :: integer(),
    SrcBin :: binary().
qs_key($&, KeyBinList, Pos, _) ->
    {list_to_binary(KeyBinList), Pos};
qs_key(CurByte, KeyBinList, -1, _) ->
    {list_to_binary([CurByte | KeyBinList]), -1};
qs_key(CurByte, KeyBinList, Pos, SrcBin) ->
    qs_key(binary:at(SrcBin, Pos), [CurByte | KeyBinList], Pos - 1, SrcBin).

-spec qs_value(CurByte, ValueBinList, Pos, SrcBin) -> {binary(), integer()} when
    CurByte :: byte(),
    ValueBinList :: [byte()],
    Pos :: integer(),
    SrcBin :: binary().
qs_value($=, ValueBinList, Pos, _) ->
    {list_to_binary(ValueBinList), Pos};
qs_value(CurByte, ValueBinList, Pos, SrcBin) ->
    qs_value(binary:at(SrcBin, Pos), [CurByte | ValueBinList], Pos - 1, SrcBin).

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec validate_signature(OriginalParamMap) -> boolean() when
    OriginalParamMap :: map().
validate_signature(OriginalParamMap) ->
    ParamList = maps:to_list(maps:without([signature], OriginalParamMap)),
    GeneratedSignature = generate_signature(ParamList),
    Signature = binary_to_list(maps:get(signature, OriginalParamMap)),
    case GeneratedSignature == Signature of
        true ->
            true;
        _ ->
            error_logger:error_msg("Validation signature failed:~nParamMap:~p~nGSignature:~p~nOSignature:~p~n", [OriginalParamMap, GeneratedSignature, Signature]),
            false
    end.

-spec generate_signature(OriginParamList) -> string() when
    OriginParamList :: list().
generate_signature(OriginParamList) ->
    ConcatedParamContent = [?WECHAT_TOKEN | concat_param_content(OriginParamList, [])],
    SortedParamContent = lists:sort(ConcatedParamContent),
    string:to_lower(sha1:hexstring(SortedParamContent)).

-spec process_request(Req) -> binary() when
    Req :: cowboy_req:req().
process_request(Req) ->
    case parse_xml_request(Req) of
        parse_failed ->
            ?EMPTY_RESPONSE;
        ReqParamsMap ->
            error_logger:info_msg("ReqParamsMap:~p~n", [ReqParamsMap]),
            #{'MsgType' := MsgType, 'ToUserName' := PlatformId, 'FromUserName' := UidBin} = ReqParamsMap,

            Uid = binary_to_atom(UidBin, utf8),
            {InputForUnregister, FuncForRegsiter} = get_action_from_message_type(MsgType, ReqParamsMap),
            ReplyText = case InputForUnregister of
                            no_reply ->
                                FuncForRegsiter();
                            _ ->
                                case login_server:is_in_registration(Uid) of
                                    true ->
                                        pending_text(register_fsm, input, [Uid, InputForUnregister]);
                                    _ ->
                                        case login_server:is_uid_registered(Uid) of
                                            false ->
                                                pending_text(login_server, register_uid, [Uid]);
                                            _ ->
                                                FuncForRegsiter(Uid)
                                        end
                                end
                        end,

            error_logger:info_msg("ReplyText:~p~n", [ReplyText]),
            Response = compose_response_xml(UidBin, PlatformId, ReplyText),
            error_logger:info_msg("Response:~ts~n", [Response]),
            Response
    end.

-spec get_action_from_message_type(MsgType, ReqParamsMap) -> {InputForUnregister, FuncForRegsiter} when
    MsgType :: binary(),
    ReqParamsMap :: map(),
    InputForUnregister :: binary() | no_reply,
    FuncForRegsiter :: function().
get_action_from_message_type(MsgType, ReqParamsMap) ->
    case binary_to_atom(MsgType, utf8) of
        event ->
            Event = binary_to_atom(maps:get('Event', ReqParamsMap), utf8),
            case Event of
                subscribe ->
                    {<<>>, fun(PlayerProfile) ->
                        Lang = maps:get(lang, PlayerProfile),
                        nls_server:get_text(?MODULE, [{nls, welcome_back}], Lang)
                    end};
                unsubscribe ->
                    {no_reply, fun() ->
                        ?EMPTY_RESPONSE
                    end};
                _ ->
                    {no_reply, fun() ->
                        ?EMPTY_RESPONSE
                    end}
            end;
        text ->
            % _MsgId = maps:get('MsgId', ReqParamsMap),
            RawInput = maps:get('Content', ReqParamsMap),
            [ModuleNameStr | RawCommandArgs] = binary:split(RawInput, <<" ">>),
            {RawInput, fun(Uid) ->
                try
                    RawModuleName = binary_to_atom(ModuleNameStr, utf8),
                    {ModuleName, CommandArgs} =
                        case common_api:is_module_exists(RawModuleName) of
                            true ->
                                {RawModuleName, RawCommandArgs};
                            _ ->
                                case direction(RawModuleName) of
                                    undefined ->
                                        throw(not_direction);
                                    Direction ->
                                        direction:module_info(),
                                        {direction, [Direction]}
                                end
                        end,

                    Arity = length(CommandArgs),
                    Args = [Uid] ++ CommandArgs,

                    case erlang:function_exported(ModuleName, exec, Arity + 2) of
                        true ->
                            pending_text(ModuleName, exec, Args);
                        _ ->
                            nls_server:get_text(ModuleName, [{nls, invalid_argument}, CommandArgs, <<"\n\n">>, {nls, info}], player_fsm:get_lang(Uid))
                    end
                catch
                    Type:Reason ->
                        error_logger:error_msg("Command error~n Type:~p~nReason:~p~n", [Type, Reason]),
                        case login_server:is_uid_logged_in(Uid) of
                            true ->
                                nls_server:get_text(?MODULE, [{nls, invalid_command}, ModuleNameStr], player_fsm:get_lang(Uid));
                            _ ->
                                nls_server:get_text(login, [{nls, please_login}], zh)
                        end
                end
            end};
        _ ->
            {<<>>, fun(Uid) ->
                nls_server:get_text(?MODULE, [{nls, message_type_not_support}], player_fsm:get_lang(Uid))
            end}
    end.

-spec pending_text(Module, Function, Args) -> [binary()] when
    Module :: atom(),
    Function :: atom(),
    Args :: [term()].
pending_text(Module, Function, Args) ->
    Self = self(),
    spawn_link(Module, Function, [Self] ++ Args),
    receive
        {execed, Self, ReturnText} ->
            ReturnText
    end.

-spec return_text(DispatcherPid, ReturnText) -> ok when
    ReturnText :: binary() | [binary()],
    DispatcherPid :: pid().
return_text(DispatcherPid, ReturnText) ->
    DispatcherPid ! {execed, DispatcherPid, ReturnText},
    ok.

-spec compose_response_xml(Uid, PlatformId, Content) -> binary() when
    Uid :: term(),
    PlatformId :: term(),
    Content :: term().
compose_response_xml(Uid, PlatformId, Content) ->
    case Content of
        ?EMPTY_RESPONSE ->
            ?EMPTY_RESPONSE;
        Response ->
            ResponseList = lists:flatten([<<"<xml><Content><![CDATA[">>,
                Response,
                <<"]]></Content><ToUserName><![CDATA[">>,
                Uid,
                <<"]]></ToUserName><FromUserName><![CDATA[">>,
                PlatformId,
                <<"]]></FromUserName><CreateTime>">>,
                integer_to_binary(common_api:timestamp()),
                <<"</CreateTime><MsgType><![CDATA[text]]></MsgType></xml>">>]),

            error_logger:info_msg("ResponseList:~p~n", [ResponseList]),
            list_to_binary(ResponseList)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% [{"ToUserName", [], [PlatFormId]},
%% {"FromUserName", [], [Uid]},
%% {"CreateTime", [], [CreateTime]},
%% {"MsgType", [], [MsgType]},
%% {"Content", [], [Content]},
%% {"MsgId", [], [MsgId]}]
%%
%% @end
%%--------------------------------------------------------------------
-spec parse_xml_request(Req) -> Result when
    Req :: cowboy_req:req(),
    Result :: parse_failed | map().
parse_xml_request(Req) ->
    {ok, Message, _} = cowboy_req:body(Req),
    error_logger:info_msg("Message:~p~n", [Message]),
    case Message of
        <<>> ->
            parse_failed;
        _ ->
            {ok, {"xml", [], Params}, _} = erlsom:simple_form(Message),
            unmarshall_params(Params, #{})
    end.

-spec unmarshall_params(SrcList, ParamsMap) -> map() when
    SrcList :: list(),
    ParamsMap :: map().
unmarshall_params([], ParamsMap) ->
    ParamsMap;
unmarshall_params([{Key, [], [Value]} | Tail], ParamsMap) ->
    unmarshall_params(Tail, maps:put(list_to_atom(Key), unicode:characters_to_binary(string:strip(Value)), ParamsMap)).

-spec concat_param_content(SrcList, ConcatedParamContent) -> list() when
    SrcList :: list(),
    ConcatedParamContent :: list().
concat_param_content([], ConcatedParamContent) ->
    lists:reverse(ConcatedParamContent);
concat_param_content([{_, ParamContent} | Tail], ConcatedParamContent) ->
    concat_param_content(Tail, [ParamContent | ConcatedParamContent]).

-spec direction(atom()) -> direction:direction().
direction(e) -> east;
direction(east) -> east;
direction('6') -> east;
direction(s) -> south;
direction(south) -> south;
direction('8') -> south;
direction(w) -> west;
direction(west) -> west;
direction('4') -> west;
direction(n) -> north;
direction(north) -> north;
direction('2') -> north;
direction(ne) -> northeast;
direction(northeast) -> northeast;
direction('3') -> northeast;
direction(se) -> southeast;
direction(southeast) -> southeast;
direction('9') -> southeast;
direction(sw) -> southwest;
direction(southwest) -> southwest;
direction('7') -> southwest;
direction(nw) -> northwest;
direction(northwest) -> northwest;
direction('1') -> northwest;
direction(look) -> look;
direction('5') -> look;
direction(_) -> undefined.