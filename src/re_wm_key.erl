%% -------------------------------------------------------------------
%%
%% Copyright (c) 2012 Basho Technologies, Inc.  All Rights Reserved.
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
         resource_exists/2,
         provide_content/2]).

-record(ctx, {bucket_type, bucket, key, resource, id, response=undefined}).

-include_lib("webmachine/include/webmachine.hrl").
-include("riak_explorer.hrl").

-define(listKeys(BucketType, Bucket),
    #ctx{bucket_type=BucketType, bucket=Bucket, key=undefined}).
-define(keyInfo(BucketType, Bucket, Key),
    #ctx{bucket_type=BucketType, bucket=Bucket, key=Key, resource=undefined}).
-define(keyResource(BucketType, Bucket, Key, Resource),
    #ctx{bucket_type=BucketType, bucket=Bucket, key=Key, resource=Resource}).

%%%===================================================================
%%% API
%%%===================================================================

resources() -> 
    [].

routes() ->
    Bucket = lists:last(re_wm_bucket:routes()),
    Keys = Bucket ++ ["keys"],
    Key = Keys ++ [key],
    KeyResource = Key ++ [resource],
    [Keys, KeyResource, Key].

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
        bucket = wrq:path_info(bucket, RD),
        key = wrq:path_info(key, RD)},
    {true, RD, Ctx1}.

allowed_methods(RD, Ctx) ->
    Methods = ['GET'],
    {Methods, RD, Ctx}.

content_types_provided(RD, Ctx) ->
    Types = [{"application/vnd.api+json", provide_content}],
    {Types, RD, Ctx}.

resource_exists(RD, Ctx=?listKeys(_BucketType, _Bucket)) ->
    Response = [{keys, []}],
    {true, RD, Ctx#ctx{id=list, response=Response}};
resource_exists(RD, Ctx=?keyInfo(_BucketType, _Bucket, Key)) ->
    Response = [{key, list_to_binary(Key)}],
    {true, RD, Ctx#ctx{id=list_to_binary(Key), response=Response}};
resource_exists(RD, Ctx=?keyResource(BucketType, Bucket, Key, Resource)) ->
    Id = list_to_atom(Resource),
    case proplists:get_value(Id, resources()) of
        [M,F] -> 
            Response = M:F(BucketType, Bucket, Key),
            {true, RD, Ctx#ctx{id=Id, response=Response}};
        _ -> 
            {false, RD, Ctx}
    end;
resource_exists(RD, Ctx) ->
    {false, RD, Ctx}.

provide_content(RD, Ctx=#ctx{id=undefined}) ->
    JDoc = re_wm_jsonapi:doc(null, re_wm_jsonapi:links(RD)),
    render_json(JDoc, RD, Ctx);
provide_content(RD, Ctx=#ctx{id=Id, response=Response}) ->
    JRes = re_wm_jsonapi:res(type(), Id, Response, re_wm_jsonapi:links(RD)),
    JDoc = re_wm_jsonapi:doc(JRes),
    render_json(JDoc, RD, Ctx).

%% ====================================================================
%% Private
%% ====================================================================

type() -> <<"keys">>.

render_json(Data, RD, Ctx) ->
    Body = mochijson2:encode(Data),
    {Body, RD, Ctx}.