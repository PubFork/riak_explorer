%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(re_wm).

-export([resources/0,
         routes/0,
         dispatch/0,
         dispatch/1,
         base_route/0]).

-export([rd_url/1,
         rd_accepts/2,
         add_content/2,
         add_error/2,
         rd_content/2,
         rd_cluster_exists/1,
         rd_cluster/1,
         rd_node_exists/1,
         rd_node/1,
         maybe_atomize/1,
         maybe_to_list/1,
         url_decode/1
        ]).

-export([init/1,
         service_available/2,
         allowed_methods/2,
         content_types_provided/2,
         content_types_accepted/2,
         resource_exists/2,
         provide_content/2,
         delete_resource/2,
         process_post/2,
         provide_text_content/2,
         provide_static_content/2,
         accept_content/2,
         post_is_create/2,
         create_path/2,
         last_modified/2]).

-include_lib("webmachine/include/webmachine.hrl").
-include("re_wm.hrl").

-record(ctx, {
          proxy :: {module(), atom()} | undefined,
          route :: route()
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%% Routing

-spec resources() -> [module()].
resources() ->
    [
     re_wm_explore,
     re_wm_control,
     re_wm_proxy,
     re_wm_static
    ].

-spec routes() -> [route()].
routes() ->
    routes(resources(), []).

-spec routes([module()], [route()]) -> [route()].
routes([], Routes) ->
    Routes;
routes([Resource|Rest], Routes) ->
    routes(Rest, Routes ++ Resource:routes()).

-spec dispatch() -> [{[string() | atom], module(), [term()]}].
dispatch() ->
    dispatch([]).

-spec dispatch([term()]) -> [{[string() | atom], module(), [term()]}].
dispatch(Args) ->
    WmRoutes = build_wm_routes(base_route(), routes(), []),
    [ {R, M, A ++ Args} || {R, M, A} <- WmRoutes ].

-spec base_route() -> string().
base_route() ->
    case riak_explorer:is_riak() of
        false -> [];
        true -> ["admin"]
    end.

%%% Utility

-spec rd_url(#wm_reqdata{}) -> string().
rd_url(ReqData) ->
    BaseUrl = wrq:base_uri(ReqData),
    case base_route() of
        [] ->
            BaseUrl ++ "/";
        [R] ->
            BaseUrl ++ "/" ++ R ++ "/"
    end.

-spec rd_accepts(string(), #wm_reqdata{}) -> boolean().
rd_accepts(CT, ReqData) ->
    case wrq:get_req_header("Accept", ReqData) of
        undefined ->
            true;
        Accept ->
            string:str(Accept,CT) > 0
    end.

-spec add_content(term(), #wm_reqdata{}) -> {boolean(), #wm_reqdata{}}.
add_content({error, not_found}, ReqData) ->
    {{halt, 404}, ReqData};
add_content({error, Reason}, ReqData) ->
    {{halt, 500}, add_error(Reason, ReqData)};
add_content(ok, ReqData) ->
    {true, ReqData};
add_content(Content, ReqData) ->
    Tokens = string:tokens(wrq:path(ReqData), "/"),
    Last = lists:nth(length(Tokens), Tokens),
    {true, wrq:append_to_response_body(mochijson2:encode([{list_to_binary(Last), Content}]), ReqData)}.

-spec add_error(term(), #wm_reqdata{}) -> #wm_reqdata{}.
add_error(Error, ReqData) ->
    wrq:append_to_response_body(mochijson2:encode([{error, format_error(Error)}]), ReqData).

-spec format_error(term()) -> binary().
format_error(Error) when is_list(Error) ->
    list_to_binary(io_lib:format("~s", [Error]));
format_error(Error) ->
    list_to_binary(io_lib:format("~p", [Error])).

-spec rd_content(term(), #wm_reqdata{}) ->
                        {[{binary(), term()}], #wm_reqdata{}}.
rd_content({error, not_found}, ReqData) ->
    {{halt, 404}, ReqData};
rd_content({error, Reason}, ReqData) ->
    {{halt, 500}, add_error(Reason, ReqData)};
rd_content(Content, ReqData) ->
    Tokens = string:tokens(wrq:path(ReqData), "/"),
    Last = lists:nth(length(Tokens), Tokens),
    {[{list_to_binary(Last), Content}], ReqData}.

-spec rd_cluster_exists(#wm_reqdata{}) -> {boolean(), #wm_reqdata{}}.
rd_cluster_exists(ReqData) ->
    C = rd_cluster(ReqData),
    {re_cluster:exists(C), ReqData}.

-spec rd_cluster(#wm_reqdata{}) -> re_cluster:re_cluster().
rd_cluster(ReqData) ->
    maybe_atomize(wrq:path_info(cluster, ReqData)).

-spec rd_node_exists(#wm_reqdata{}) -> {boolean(), #wm_reqdata{}}.
rd_node_exists(ReqData) ->
    case rd_cluster_exists(ReqData) of
        {true,_} ->
            case rd_node(ReqData) of
                {error, not_found} ->
                    {false, ReqData};
                N ->
                    {re_node:exists(N), ReqData}
            end;
        _ ->
            {false, ReqData}
    end.

-spec rd_node(#wm_reqdata{}) -> {error, not_found} | re_node:re_node().
rd_node(ReqData) ->
    N = url_decode(wrq:path_info(node, ReqData)),
    N1 = maybe_atomize(N),

    case N1 of
        undefined ->
            C = rd_cluster(ReqData),
            re_cluster:riak_node(maybe_atomize(C));
        N2 ->
            N2
    end.

maybe_to_list(Data) when is_list(Data) -> Data;
maybe_to_list(Data) when is_atom(Data) -> atom_to_list(Data).

maybe_atomize(Data) when is_list(Data) -> list_to_atom(Data);
maybe_atomize(Data) when is_atom(Data) -> Data.

url_decode(Data) ->
    re:replace(maybe_to_list(Data), "%40", "@", [{return, list}]).

%%%===================================================================
%%% Webmachine Callbacks
%%%===================================================================

init(Args) ->
    Ctx =
        case proplists:get_value(proxy, Args) of
            undefined ->
                #ctx{};
            {PM, PF} ->
                #ctx{proxy = {PM, PF}}
        end,
    {ok, Ctx}.

service_available(ReqData, Ctx) ->
    Route = case get_route(base_route(), routes(), ReqData) of
                #route{}=R ->
                    R;
                _ ->
                    [R] = re_wm_static:routes(),
                    R
            end,
    {Available, ReqData1} =
        case Route#route.available of
            {M, F} -> maybe_proxy_request(M, F, ReqData, Ctx);
            Bool -> {Bool, ReqData}
        end,
    {Available, ReqData1, Ctx#ctx{route = Route}}.

allowed_methods(ReqData, Ctx = #ctx{route = Route}) ->
    {Route#route.methods, ReqData, Ctx}.

content_types_provided(ReqData, Ctx = #ctx{route = Route}) ->
    case Route#route.provides of
        {M, F} ->
            {CTs, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
            {CTs, ReqData1, Ctx};
        Provides ->
            {Provides, ReqData, Ctx}
     end.

content_types_accepted(ReqData, Ctx = #ctx{route = Route}) ->
    {Route#route.accepts, ReqData, Ctx}.

resource_exists(ReqData, Ctx = #ctx{route = #route{exists = {M, F}}}) ->
    {Success, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {Success, ReqData1, Ctx};
resource_exists(ReqData, Ctx = #ctx{route = #route{exists = Exists}})
  when is_boolean(Exists) ->
    {Exists, ReqData, Ctx}.

delete_resource(ReqData, Ctx = #ctx{route = #route{delete = {M, F}}}) ->
    {Success, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {Success, ReqData1, Ctx}.

provide_content(ReqData, Ctx = #ctx{route = #route{content = {M, F}}}) ->
    case maybe_proxy_request(M, F, ReqData, Ctx) of
        {{halt,_}=Body, ReqData1} ->
            {Body, ReqData1, Ctx};
        {Body, ReqData1} ->
            {mochijson2:encode(Body), ReqData1, Ctx}
    end.

provide_text_content(ReqData, Ctx = #ctx{route = #route{content = {M, F}}}) ->
    {Body, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    case Body of
        {{halt,_}=B, ReqData1} ->
            {B, ReqData1, Ctx};
        B when is_binary(B) ->
            {binary_to_list(B), ReqData1, Ctx};
        [{_,Props}]=B ->
            %% TODO: Improve
            case {proplists:get_value(lines, Props),
                  proplists:get_value(keys, Props),
                  proplists:get_value(buckets, Props)} of
                {undefined, undefined, undefined} ->
                    {mochijson2:encode(B), ReqData1, Ctx};
                {Values, undefined, undefined} ->
                    Lines = [binary_to_list(L) || L <- Values],
                    {string:join(Lines, io_lib:nl()), ReqData1, Ctx};
                {undefined, Values, undefined} ->
                    Lines = [binary_to_list(L) || L <- Values],
                    {string:join(Lines, io_lib:nl()), ReqData1, Ctx};
                {undefined, undefined, Values} ->
                    Lines = [binary_to_list(L) || L <- Values],
                    {string:join(Lines, io_lib:nl()), ReqData1, Ctx}
            end
    end.

provide_static_content(ReqData, Ctx = #ctx{route = #route{content = {M, F}}}) ->
    {Body, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {Body, ReqData1, Ctx}.

accept_content(ReqData, Ctx = #ctx{route = #route{accept = {M, F}}}) ->
    {Success, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {Success, ReqData1, Ctx};
accept_content(ReqData, Ctx = #ctx{route = #route{accept = undefined}}) ->
    {false, ReqData, Ctx}.

process_post(ReqData, Ctx = #ctx{route = #route{accept = {M, F}}}) ->
    {Success, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {Success, ReqData1, Ctx}.

post_is_create(ReqData, Ctx = #ctx{route = #route{post_create = PostCreate}}) ->
    {PostCreate, ReqData, Ctx}.

create_path(ReqData, Ctx = #ctx{route = #route{post_path = {M, F}}}) ->
    {Path, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {Path, ReqData1, Ctx}.

last_modified(ReqData, Ctx = #ctx{route = #route{last_modified = undefined}}) ->
    {undefined, ReqData, Ctx};
last_modified(ReqData, Ctx = #ctx{route = #route{last_modified = {M, F}}}) ->
    {LM, ReqData1} = maybe_proxy_request(M, F, ReqData, Ctx),
    {LM, ReqData1, Ctx}.

%% ====================================================================
%% Private
%% ====================================================================

get_route(_, [], _ReqData) ->
    undefined;
get_route(BaseRoute, [Route=#route{base=[],path=Paths} | Rest], ReqData) ->
    case get_route_path(BaseRoute, [], Paths, Route, ReqData) of
        undefined ->
            get_route(BaseRoute, Rest, ReqData);
        R -> R
    end;
get_route(BaseRoute, [Route=#route{base=Bases,path=[]} | Rest], ReqData) ->
    case get_route_path(BaseRoute, [], Bases, Route, ReqData) of
        undefined ->
            get_route(BaseRoute, Rest, ReqData);
        R -> R
    end;
get_route(BaseRoute, [Route=#route{base=Bases,path=Paths} | Rest], ReqData) ->
    case get_route_base(BaseRoute, Bases, Paths, Route, ReqData) of
        undefined ->
            get_route(BaseRoute, Rest, ReqData);
        R -> R
    end.

get_route_base(_, [], _, _, _) ->
    undefined;
get_route_base(BaseRoute, [Base|Rest], Paths, Route, ReqData) ->
    case get_route_path(BaseRoute, Base, Paths, Route, ReqData) of
        undefined ->
            get_route_base(BaseRoute, Rest, Paths, Route, ReqData);
        R -> R
    end.

get_route_path(_, _, [], _, _) ->
    undefined;
get_route_path(BaseRoute, Base, [Path|Rest], Route, ReqData) ->
    ReqPath = string:tokens(wrq:path(ReqData), "/"),
    case expand_path(BaseRoute ++ Base ++ Path, ReqData, []) of
        ReqPath ->
            Route;
        _ ->
            get_route_path(BaseRoute, Base, Rest, Route, ReqData)
    end.

expand_path([], _ReqData, Acc) ->
    lists:reverse(Acc);
expand_path([Part|Rest], ReqData, Acc) when is_list(Part) ->
    expand_path(Rest, ReqData, [Part | Acc]);
expand_path(['*'|Rest], ReqData, Acc) ->
    Tokens = string:tokens(wrq:path(ReqData), "/"),
    case length(Acc) > length(Tokens) of
        true ->
            undefined;
        false ->
            expand_path(Rest, ReqData, lists:reverse(lists:nthtail(length(Acc), Tokens)) ++ Acc)
    end;
expand_path([Part|Rest], ReqData, Acc) when is_atom(Part) ->
    expand_path(Rest, ReqData, [wrq:path_info(Part, ReqData) | Acc]).

build_wm_routes(_BaseRoute, [], Acc) ->
    lists:reverse(lists:flatten(Acc));
build_wm_routes(BaseRoute, [#route{base = [], path = Paths} | Rest], Acc) ->
    build_wm_routes(BaseRoute, Rest, [build_wm_route(BaseRoute, [], Paths, []) | Acc]);
build_wm_routes(BaseRoute, [#route{base = Bases, path = []} | Rest], Acc) ->
    build_wm_routes(BaseRoute, Rest, [build_wm_route(BaseRoute, [], Bases, []) | Acc]);
build_wm_routes(BaseRoute, [#route{base = Bases, path = Paths} | Rest], Acc) ->
    build_wm_routes(BaseRoute, Rest, [build_wm_routes(BaseRoute, Bases, Paths, []) | Acc]).

build_wm_routes(_BaseRoute, [], _, Acc) ->
    Acc;
build_wm_routes(BaseRoute, [Base|Rest], Paths, Acc) ->
    build_wm_routes(BaseRoute, Rest, Paths, [build_wm_route(BaseRoute, Base, Paths, [])|Acc]).

build_wm_route(_, _, [], Acc) ->
    Acc;
build_wm_route(BaseRoute, Base, [Path|Rest], Acc) ->
    build_wm_route(BaseRoute, Base, Rest, [{BaseRoute ++ Base ++ Path, ?MODULE, []}|Acc]).

maybe_proxy_request(M, F, ReqData, #ctx{proxy = undefined}) ->
    M:F(ReqData);
maybe_proxy_request(M, F, ReqData, #ctx{proxy = {PM, PF}}) ->
    case PM:PF(M, F, ReqData) of
        {ok, Result} ->
            Result;
        {forward, local} ->
            M:F(ReqData);
        {forward, {location, Location, Path, NewPath}} ->
            re_wm_proxy:send_proxy_request(Location, Path, NewPath, ReqData)
    end.
