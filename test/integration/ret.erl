%% @doc Test helper functions.
-module(ret).

-compile(export_all).

-include("../../include/riak_explorer.hrl").
-include_lib("eunit/include/eunit.hrl").

-ifdef(integration_test).

fmt(S, Args) ->
    lists:flatten(io_lib:format(S, Args)).

re_host() ->
    case os:getenv("RIAK_HOST") of
        false -> "localhost";
        Host -> Host
    end.

re_port() ->
    case os:getenv("RIAK_PORT") of
        false -> 8080;
        Port -> list_to_integer(Port)
    end.

url(Path) ->
    fmt("http://~s:~B/" ++ ?RE_BASE_ROUTE ++ "/~s", [re_host(), re_port(), Path]).

ensure_ibrowse() ->
    case whereis(ibrowse) of
        undefined -> ibrowse:start();
        Any when is_pid(Any)-> ok
    end.

http(Method, URL, Body, H0, ReturnHeader) ->
    ensure_ibrowse(),
    Opts = [],
    
    Headers = H0 ++ [
        {"content-type", "application/json"},
        {"accept", "application/json"}
    ],

    Res = ibrowse:send_req(URL, Headers, Method, Body, Opts),

    case ReturnHeader of
        true -> Res;
        _ ->
            {ok, S, _, B} = Res,
            {ok, S, B}
    end.

http(Method, URL) ->
    http(Method, URL, <<>>, [], false).
http(Method, URL, Body) ->
    http(Method, URL, Body, [], false).
http(Method, URL, Body, Headers) ->
    http(Method, URL, Body, Headers, false).

-endif.
