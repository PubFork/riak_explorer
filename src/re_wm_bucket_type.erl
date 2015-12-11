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

-module(re_wm_bucket_type).
-export([resources/0, routes/0, dispatch/0]).
-export([init/1]).
-export([service_available/2,
         allowed_methods/2,
         content_types_provided/2,
         content_types_accepted/2,
         resource_exists/2,
         accept_content/2,
         provide_jsonapi_content/2,
         provide_content/2]).

-record(ctx, {cluster, node, bucket_type, resource, id, method, response=undefined}).

-include_lib("webmachine/include/webmachine.hrl").
-include("riak_explorer.hrl").

-define(noNode(),
    #ctx{node=[{error, no_nodes}]}).
-define(listBucketTypes(),
    #ctx{method='GET', bucket_type=undefined}).
-define(bucketTypeInfo(BucketType),
    #ctx{method='GET', bucket_type=BucketType, resource=undefined}).
-define(createBucketType(BucketType),
    #ctx{method='PUT', bucket_type=BucketType, resource=undefined}).
-define(bucketTypeResource(BucketType, Resource),
    #ctx{method='GET', bucket_type=BucketType, resource=Resource}).

%%%===================================================================
%%% API
%%%===================================================================

resources() ->
    [{jobs, [riak_explorer, jobs_for_resource]}].

routes() ->
    re_config:build_routes(?RE_BASE_ROUTE, [
        ["clusters", cluster],
        ["nodes", node]
    ], [
        ["bucket_types"],
        ["bucket_types", bucket_type],
        ["bucket_types", bucket_type, resource]
    ]).

dispatch() -> lists:map(fun(Route) -> {Route, ?MODULE, []} end, routes()).

%%%===================================================================
%%% Callbacks
%%%===================================================================

init(_) ->
    {ok, #ctx{}}.

service_available(RD, Ctx0) ->
    Ctx1 = Ctx0#ctx{
        resource = wrq:path_info(resource, RD),
        bucket_type = wrq:path_info(bucket_type, RD),
        node = wrq:path_info(node, RD),
        cluster = wrq:path_info(cluster, RD),
        method = wrq:method(RD)},
    {true, RD, Ctx1#ctx{node = node_from_context(Ctx1)}}.

allowed_methods(RD, Ctx) ->
    Methods = ['GET', 'PUT'],
    {Methods, RD, Ctx}.

content_types_accepted(RD, Ctx) ->
    Types = [{"application/json", accept_content},
             {"application/vnd.api+json", accept_content}],
    {Types, RD, Ctx}.

content_types_provided(RD, Ctx) ->
    Types = [{"application/json", provide_content},
             {"application/vnd.api+json", provide_jsonapi_content}],
    {Types, RD, Ctx}.

resource_exists(RD, Ctx=?noNode()) ->
    {false, RD, Ctx};
resource_exists(RD, Ctx=?listBucketTypes()) ->
    Node = Ctx#ctx.node,
    Response = re_riak:bucket_types(Node),
    {true, RD, Ctx#ctx{id=bucket_types, response=Response}};
resource_exists(RD, Ctx=?createBucketType(_)) ->
    {true, RD, Ctx};
resource_exists(RD, Ctx=?bucketTypeInfo(BucketType)) ->
    Id = list_to_binary(BucketType),
    Node = Ctx#ctx.node,
    case lists:flatten([proplists:get_value(props, Prop) ||
                           Prop <- proplists:get_value(bucket_types, re_riak:bucket_types(Node)),
                           Id =:= proplists:get_value(name, Prop)]) of
        [] -> {false, RD, Ctx};
        Props ->
            Response = [{bucket_types, [{id,Id}, {props, Props}]}],
            {true, RD, Ctx#ctx{id=bucket_type, response=Response}}
    end;
resource_exists(RD, Ctx=?bucketTypeResource(BucketType, Resource)) ->
    Node = Ctx#ctx.node,
    Id = list_to_atom(Resource),
    case proplists:get_value(Id, resources()) of
        [M,F] ->
            Response = M:F(Node, BucketType),
            {true, RD, Ctx#ctx{id=Id, response=Response}};
        _ ->
            {false, RD, Ctx}
    end;
resource_exists(RD, Ctx) ->
    {false, RD, Ctx}.

accept_content(RD, Ctx=?createBucketType(BucketType)) ->
    Node = Ctx#ctx.node,
    RawValue = wrq:req_body(RD),
    case re_riak:create_bucket_type(Node, BucketType, RawValue) of
        ok -> {true, RD, Ctx};
        error -> {false, RD, Ctx}
    end;
accept_content(RD, Ctx) ->
    {false, RD, Ctx}.

provide_content(RD, Ctx=#ctx{response=undefined}) ->
    JDoc = re_wm_jsonapi:doc(RD, data, null, re_wm_jsonapi:links(RD, "/explore/routes"), [], []),
    {mochijson2:encode(JDoc), RD, Ctx};
provide_content(RD, Ctx=#ctx{id=Id, response=[{_, Objects}]}) ->
    JRes = re_wm_jsonapi:res(RD, [], Objects, [], []),
    JDoc = re_wm_jsonapi:doc(RD, Id, JRes, [], [], []),
    {mochijson2:encode(JDoc), RD, Ctx}.

provide_jsonapi_content(RD, Ctx=#ctx{response=undefined}) ->
    JDoc = re_wm_jsonapi:doc(RD, data, null, re_wm_jsonapi:links(RD, "/explore/routes"), [], []),
    {mochijson2:encode(JDoc), RD, Ctx};
provide_jsonapi_content(RD, Ctx=#ctx{id=Id, response=[{Type, Objects}]}) ->
    JRes = re_wm_jsonapi:res(RD, Type, Objects, [], []),
    JDoc = re_wm_jsonapi:doc(RD, Id, JRes, [], [], []),
    {mochijson2:encode(JDoc), RD, Ctx}.

%% ====================================================================
%% Private
%% ====================================================================

node_from_context(Ctx) ->
    case Ctx of
        #ctx{cluster=undefined, node=N} ->
            Node = list_to_atom(N),
            re_config:set_adhoc_cluster(Node),
            Node;
        #ctx{cluster=C} -> re_riak:first_node(list_to_atom(C))
    end.
