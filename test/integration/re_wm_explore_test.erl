%% @doc Test the API in various ways.
-module(re_wm_explore_test).

-compile(export_all).
-ifdef(integration_test).
-include_lib("eunit/include/eunit.hrl").
-include("re_wm.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% TEST DESCRIPTIONS %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%
re_wm_explore_test_() ->
    {setup,
     fun () ->
             {ok, "204", _} = ret:http(put, "http://localhost:8098/types/mytype/buckets/test/keys/test", <<"testing">>)
     end,
     fun (_) -> ok end,
     {timeout, 60, [
                    all_routes()
                   ]}
    }.

%%%%%%%%%%%%%%%%%%%%
%%% ACTUAL TESTS %%%
%%%%%%%%%%%%%%%%%%%%

all_routes() ->
    Routes = re_wm:routes(),
    RiakType = riak_type(),
    lists:flatten([ [ assert_paths(Method, Base, Paths, RiakType, [])
        || Method <- Methods ]
      || #route{base=[Base|_],path=Paths,methods=Methods} <- Routes ]).

assert_paths(_, _, [], _, Accum) -> lists:reverse(Accum);
assert_paths(Method, Base, [Path|Paths], RiakType, Accum) ->
    case is_testable_path(Path, RiakType) of
        true ->
            Url = ret:url(to_path_str(Base) ++ "/" ++ to_path_str(Path)),
            Body = path_body(Method, Path),
            {ok, Code, Content} = ret:http(Method, Url, Body),
            ExpectedCode = path_code(Method, Path),
            assert_paths(Method, Base, Paths, RiakType, [?_assertEqual({ExpectedCode, Method, Url, Content}, {Code, Method, Url, Content})|Accum]);
        false ->
            assert_paths(Method, Base, Paths, RiakType, Accum)
    end.


to_path_str(["config", "files", file]) ->
    string:join(["config", "files", "riak.conf"], "/");
to_path_str(["log", "files", file]) ->
    string:join(["log", "files", "console.log"], "/");
to_path_str(Path) ->
    string:join([ path_part(P, Path) || P <- Path ], "/").

path_part(P, _) when is_list(P) -> P;
path_part(cluster, _) -> "default";
path_part(node, _) -> "riak@127.0.0.1";
path_part(bucket_type, _) -> "mytype";
path_part(bucket, _) -> "test";
path_part(table, _) -> "GeoCheckin";
path_part(arg1, _) -> "riak@127.0.0.1";
path_part(arg2, _) -> "riak@127.0.0.1";
path_part('*',["clusters",cluster,'*']) -> "ping";
path_part('*',["nodes",node,'*']) -> "ping";
path_part('*',['*']) -> "index.html".

path_body('PUT', ["keys"]) ->
    <<"{\"keys\":[\"test\"]}">>;
path_body('PUT', ["tables", table, "keys"]) ->
    <<"{\"keys\":[[\"family1\", \"series1\", 25]]}">>;
path_body('PUT', ["buckets"]) ->
    <<"{\"buckets\":[\"test\"]}">>;
path_body('PUT', ["bucket_types", bucket_type]) ->
    <<"{\"props\":{\"n_val\":3}}">>;
path_body('PUT', ["tables", table]) ->
   <<"[[\"family1\", \"series1\", 25, \"hot\", 23]]">>;
path_body('POST', ["tables", "query"]) ->
    <<"select * from GeoCheckin where time > 24 and time < 26 and myfamily = 'family1' and myseries = 'series1'">>;
path_body('POST', ["tables", table, "query"]) ->
   <<"[\"family2\", \"series99\", 26]">>;
path_body(_, _) ->
   <<>>.

path_code('POST', ["tables", "query"]) -> "200";
path_code('POST', ["tables", table, "query"]) -> "200";
path_code('POST', _) -> "202";
path_code('GET', ["staged-leave"]) -> "500";
path_code('GET', ["commit"]) -> "500";
path_code('GET', ["join", arg1]) -> "500";
path_code('GET', ["leave", arg1]) -> "500";
path_code('GET', ["staged-join", arg1]) -> "500";
path_code('GET', ["staged-leave", arg1]) -> "500";
path_code('GET', ["force-remove", arg1]) -> "500";
path_code('GET', ["repl-fullsync-start", arg1]) -> "500";
path_code('GET', _) -> "200";
path_code('DELETE', ["buckets",bucket]) -> "202";
path_code('DELETE', _) -> "204";
path_code('PUT', ["bucket_types", bucket_type]) -> "200";
path_code('PUT', _) -> "204".

%%%%%%%%%%%%%%%%%%%%%%%%
%%% HELPER FUNCTIONS %%%
%%%%%%%%%%%%%%%%%%%%%%%%

home() ->
    render_json([{explore, <<"riak_explorer api">>}]).

ping() ->
    render_json([{ping, pong}]).

render_json(Data) ->
    Body = binary_to_list(list_to_binary(mochijson2:encode(Data))),
    Body.

riak_type() ->
    {_, _, Data} = ret:http(get, "http://localhost:9000/explore/clusters/default"),
    {struct, JsonData} = mochijson2:decode(Data),
    {struct, Cluster} = proplists:get_value(<<"default">>, JsonData),
    RiakType = binary_to_list(proplists:get_value(<<"riak_type">>, Cluster)),
    case {lists:prefix("ts", RiakType),
          lists:suffix("ee", RiakType)} of
        {false, false} -> {kv, oss};
        {false, true} -> {kv, ee};
        {true, false} -> {ts, oss};
        {true, true} -> {ts, ee}
    end.

%% The '*repl*' paths are not testable when Riak OSS is being used
is_testable_path([Path|_], RiakType) ->
    case {lists:prefix("repl", Path),
          lists:prefix("tables", Path),
          RiakType} of
        {true, _, {_, oss}} ->
            ?debugFmt("Skipping ~p because we are on Riak OSS.~n", [Path]),
            false;
        {_, true, {kv, _}} ->
            ?debugFmt("Skipping ~p because we are on Riak KV.~n", [Path]),
            false;
        _ -> true
    end.

-endif.
