%%%-------------------------------------------------------------------
%%% @author shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 24. Nov 2015 7:42 PM
%%%-------------------------------------------------------------------
-module(wechat_mud_SUITE).
-author("shuieryin").

%% API
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2,
    groups/0,
    suite/0,
    mod_input/2,
    mod_input/3
]).

-export([
    register_test/1,
    player_action_test/1,
    login_test/1,
    logout_test/1
]).

-include_lib("common_test/include/ct.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Comment starts here
%%
%% @end
%%--------------------------------------------------------------------
suite() ->
    [].

all() ->
    [
        {group, register_regression},
        {group, player_action_regression},
        {group, login_logout_regression}
    ].

groups() ->
    SpawnAmount = 30,
    PlayerActionRegression = {
        player_action_regression,
        [parallel, {repeat, SpawnAmount - SpawnAmount div 2}],
        [player_action_test || _X <- lists:seq(1, SpawnAmount * 2)]
    },

    [
        {
            register_regression,
            [parallel, {repeat, 1}],
            [register_test || _X <- lists:seq(1, SpawnAmount)]
        }
    ]

    ++ [PlayerActionRegression || _X <- lists:seq(1, 2)] ++

        [
            {
                login_logout_regression,
                [parallel, shuffle],
                    [login_test || _X <- lists:seq(1, SpawnAmount div 2)] ++ [logout_test || _X <- lists:seq(1, SpawnAmount div 2)]
            }
        ].

register_test(Cfg) -> run_test(register_test, 1, Cfg).
player_action_test(Cfg) -> run_test(player_action_test, 1, Cfg).
login_test(Cfg) -> run_test(login_test, 1, Cfg).
logout_test(Cfg) -> run_test(logout_test, 1, Cfg).

%%%===================================================================
%%% Init states
%%%===================================================================
init_per_suite(Config) ->
    Self = self(),
    error_logger:tty(false),
    register(?MODULE, Self),

    net_kernel:start(['wechat_mud@wechatmud.local', longnames]),

    spawn(
        fun() ->
            ct:pal("~p~n", [os:cmd("redis-server")])
        end),

    ct:pal("
        InetsStart:~p~n
        CryptoStart:~p~n
        Asn1Start:~p~n
        PublickeyStart:~p~n
        SslStart:~p~n
        SaslStart:~p~n
        CowlibStart:~p~n
        RanchStart:~p~n
        CowboyStart:~p~n
        ErlsomStart:~p~n
        EredisStart:~p~n
        EcsvStart:~p~n
        QuickrandStart:~p~n
        UuidStart:~p~n
        ReconStart:~p~n
        WechatmudStart:~p~n
    ", [
        application:start(inets),
        application:start(crypto),
        application:start(asn1),
        application:start(public_key),
        application:start(ssl),
        application:start(sasl),
        application:start(cowlib),
        application:start(ranch),
        application:start(cowboy),
        application:start(erlsom),
        application:start(eredis),
        application:start(ecsv),
        application:start(quickrand),
        application:start(uuid),
        application:start(recon),
        application:start(wechat_mud)
    ]),

    receive
        {Self, wechat_started} ->
            ct:pal("wechat_started~n"),
            ok
    end,

    Config.

end_per_suite(_Config) ->
    ct:pal("
        WechatmudStop:~p~n
        ReconStop:~p~n
        UuidStop:~p~n
        QuickrandStop:~p~n
        EcsvStop:~p~n
        EredisStop:~p~n
        ErlsomStop:~p~n
        CowboyStop:~p~n
        RanchStop:~p~n
        CowlibStop:~p~n
        SaslStop:~p~n
        SslStop:~p~n
        PublickeyStop:~p~n
        Asn1Stop:~p~n
        CryptoStop:~p~n
        InetsStop:~p~n
    ", [
        application:stop(wechat_mud),
        application:stop(recon),
        application:stop(uuid),
        application:stop(quickrand),
        application:stop(ecsv),
        application:stop(eredis),
        application:stop(erlsom),
        application:stop(cowboy),
        application:stop(ranch),
        application:stop(cowlib),
        application:stop(sasl),
        application:start(ssl),
        application:start(public_key),
        application:start(asn1),
        application:start(crypto),
        application:start(inets)
    ]),

    spawn(
        fun() ->
            ct:pal("~p~n", [os:cmd("redis-cli shutdown")])
        end),
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

mod_input(Uid, Command) ->
    mod_input(Uid, <<"text">>, Command).
mod_input(RawUid, Type, Command) ->
    io:format("Command:~p~n", [Command]),
    Uid = case is_atom(RawUid) of
              true ->
                  atom_to_binary(RawUid, utf8);
              false ->
                  RawUid
          end,
    Body = case Type of
               <<"text">> ->
                   <<"<Content><![CDATA[", Command/binary, "]]></Content>
                        <MsgId>6369791908936651106</MsgId>">>;
               <<"event">> ->
                   <<"<Event><![CDATA[", Command/binary, "]]></Event>
                        <EventKey><![CDATA[]]></EventKey>">>
           end,
    httpc:request(
        % Method
        post,

        % Request
        {
            % URI
            "http://localhost:13579/hapi/command_dispatcher?signature=09212eba69ae16975c347a14b94991ad5790d58e&timestamp=1483082058&nonce=165858907&openid=ogD_CvtfTf1fGpNV-dVrbgQ9I76c",

            % Headers
            [
                {"Content-Type", "application/x-www-form-urlencoded"}
            ],

            % Content type
            "raw",

            %Body
            <<"<xml>
                <ToUserName><![CDATA[gh_ef2d2b36ebec]]></ToUserName>
                <FromUserName><![CDATA[", Uid/binary, "]]></FromUserName>
                <CreateTime>1483082750</CreateTime>
                <MsgType><![CDATA[", Type/binary, "]]></MsgType>",
                Body/binary,
                "</xml>">>
        },

        % Http options
        [{ssl, [{verify, 0}]}],

        % Options
        []
    ).

run_test(Module, Times, Cfg) ->
    lists:foreach(
        fun(_Index) ->
            % ct:pal("Module:~p~nCfg:~p~n", [Module, Cfg]),
            apply(Module, test, [Cfg])
        end,
        lists:seq(1, Times)
    ).
