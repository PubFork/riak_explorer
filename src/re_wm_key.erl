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

-module(re_wm_key).
-export([resources/0, routes/0, dispatch/0]).
-export([init/1]).
-export([service_available/2,
         allowed_methods/2,
         content_types_provided/2,
         content_types_accepted/2,
         resource_exists/2,
         delete_resource/2,
         accept_content/2,
         accept_text_content/2,
         provide_japi_content/2,
         provide_json_content/2]).

-record(ctx, {method, start, rows, sort, cluster, node, bucket_type, bucket, resource, id, response=undefined}).

-include_lib("webmachine/include/webmachine.hrl").
-include("riak_explorer.hrl").

-define(noNode(Error),
    #ctx{node=[_]=Error}).
-define(putKeys(Node, BucketType, Bucket),
    #ctx{node=Node, method='PUT', bucket_type=BucketType, bucket=Bucket}).
-define(cleanKeys(Node, BucketType, Bucket),
    #ctx{node=Node, method='DELETE', bucket_type=BucketType, bucket=Bucket}).
-define(listKeysCache(Node, BucketType, Bucket),
    #ctx{node=Node, method='GET', bucket_type=BucketType, bucket=Bucket}).
-define(listKeys(Node, BucketType, Bucket, Sort),
    #ctx{node=Node, method='POST', bucket_type=BucketType, bucket=Bucket, sort=Sort}).

%%%===================================================================
%%% API
%%%===================================================================

resources() ->
    [].

routes() ->
    re_config:build_routes(?RE_BASE_ROUTE, [
        ["clusters", cluster, "bucket_types", bucket_type, "buckets", bucket],
        ["nodes", node, "bucket_types", bucket_type, "buckets", bucket]
    ], [
        ["refresh_keys", "source", "riak_kv"],
        ["keys"]
    ]).

dispatch() -> lists:map(fun(Route) -> {Route, ?MODULE, []} end, routes()).

%%%===================================================================
%%% Callbacks
%%%===================================================================

init(_) ->
    {ok, #ctx{}}.

service_available(RD, Ctx) ->
    Cluster = re_wm_util:maybe_atomize(wrq:path_info(cluster, RD)),
    Node = re_wm_util:maybe_atomize(wrq:path_info(node, RD)),

    {true, RD, Ctx#ctx{
        resource = wrq:path_info(resource, RD),
        bucket_type = wrq:path_info(bucket_type, RD),
        bucket = wrq:path_info(bucket, RD),
        node = re_wm_util:node_from_context(Cluster, Node),
        cluster = Cluster,
        method = wrq:method(RD),
        start = list_to_integer(wrq:get_qs_value("start","0",RD)),
        rows = list_to_integer(wrq:get_qs_value("rows","1000",RD)),
        sort = list_to_atom(wrq:get_qs_value("sort","true",RD))
    }}.

allowed_methods(RD, Ctx) ->
    Methods = ['POST', 'GET', 'PUT', 'DELETE'],
    {Methods, RD, Ctx}.

content_types_provided(RD, Ctx) ->
    Types = [{"application/json", provide_json_content},
             {"application/vnd.api+json", provide_japi_content}],
    {Types, RD, Ctx}.

content_types_accepted(RD, Ctx) ->
    Types = [{"application/json", accept_content},
             {"plain/text", accept_text_content},
             {"application/octet-stream", accept_text_content},
             {"application/vnd.api+json", accept_content}],
    {Types, RD, Ctx}.

resource_exists(RD, Ctx=?noNode(Error)) ->
    set_response(RD, Ctx, error, Error);
resource_exists(RD, Ctx=?putKeys(_Node, _BucketType, _Bucket)) ->
    {true, RD, Ctx};
resource_exists(RD, Ctx=?cleanKeys(Node, BucketType, Bucket)) ->
    Cluster = Ctx#ctx.cluster,
    re_riak:clean_keys(Cluster, Node, BucketType, Bucket),
    {true, RD, Ctx};
resource_exists(RD, Ctx=?listKeysCache(Node, BucketType, Bucket)) ->
    Cluster = Ctx#ctx.cluster,
    set_response(RD, Ctx, keys,
        re_riak:list_keys_cache(Cluster, Node, BucketType, Bucket, Ctx#ctx.start, Ctx#ctx.rows));
resource_exists(RD, Ctx=?listKeys(Node, BucketType, Bucket, Sort)) ->
    Cluster = Ctx#ctx.cluster,
    Options = [{sort, Sort}],
    JobsPath = string:substr(wrq:path(RD),1, string:str(wrq:path(RD), "refresh_keys") - 1) ++ "jobs",
    re_wm_util:set_jobs_response(RD, Ctx, JobsPath,
        re_riak:list_keys(Cluster, Node, BucketType, Bucket, Options));
resource_exists(RD, Ctx) ->
    {false, RD, Ctx}.

delete_resource(RD, Ctx) ->
    {true, RD, Ctx}.

accept_content(RD, Ctx=?putKeys(Node, BucketType, Bucket)) ->
    write_cache_json(RD, Ctx, Node, BucketType, Bucket).

accept_text_content(RD, Ctx=?putKeys(Node, BucketType, Bucket)) ->
    write_cache_text(RD, Ctx, Node, BucketType, Bucket).

provide_json_content(RD, Ctx=#ctx{id=Id, response=Response}) ->
    {re_wm_util:provide_content(json, RD, Id, Response), RD, Ctx}.

provide_japi_content(RD, Ctx=#ctx{id=Id, response=Response}) ->
    {re_wm_util:provide_content(jsonapi, RD, Id, Response), RD, Ctx}.

%% ====================================================================
%% Private
%% ====================================================================

write_cache_json(RD, Ctx, Node, BucketType, Bucket) ->
    Cluster = Ctx#ctx.cluster,
    RawValue = wrq:req_body(RD),
    {struct, [{<<"keys">>, Keys}]} = mochijson2:decode(RawValue),
    re_riak:put_keys(Cluster, Node, BucketType, Bucket, Keys),
    {true, RD, Ctx}.

write_cache_text(RD, Ctx, Node, BucketType, Bucket) ->
    Cluster = Ctx#ctx.cluster,
    RawValue = binary_to_list(wrq:req_body(RD)),
    KeysStr = string:tokens(RawValue, "\n"),
    Keys = lists:map(fun(B) -> list_to_binary(B) end, KeysStr),
    re_riak:put_keys(Cluster, Node, BucketType, Bucket, Keys),
    {true, RD, Ctx}.

set_response(RD, Ctx, Id, Response) ->
    re_wm_util:resource_exists(RD, Ctx#ctx{id=Id, response=Response}, Response).
