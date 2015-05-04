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

-module(re_wm_bucket_type).
-export([resources/0, routes/0, dispatch/0]).
-export([init/1]).
-export([service_available/2,
         allowed_methods/2, 
         content_types_provided/2,
         resource_exists/2,
         provide_content/2]).

-record(ctx, {bucket_type, resource, response=undefined}).

-include_lib("webmachine/include/webmachine.hrl").
-include("riak_explorer.hrl").

-define(listBucketTypes(),
    #ctx{bucket_type=undefined}).
-define(bucketTypeInfo(BucketType),
    #ctx{bucket_type=BucketType, resource=undefined}).
-define(bucketTypeResource(BucketType, Resource),
    #ctx{bucket_type=BucketType, resource=Resource}).

%%%===================================================================
%%% API
%%%===================================================================

resources() -> 
    [].

routes() ->
    Base = lists:last(re_wm_base:routes()),
    BucketTypes = Base ++ ["bucket_types"],
    BucketType = BucketTypes ++ [bucket_type],
    BucketTypeResource = BucketType ++ [resource],
    [BucketTypes, BucketTypeResource, BucketType].

dispatch() -> lists:map(fun(Route) -> {Route, ?MODULE, []} end, routes()).

%%%===================================================================
%%% Callbacks
%%%===================================================================

init(_) ->
    {ok, #ctx{}}.

service_available(RD, Ctx0) ->
    Ctx1 = Ctx0#ctx{
        resource = wrq:path_info(resource, RD),
        bucket_type = wrq:path_info(bucket_type, RD)},
    {true, RD, Ctx1}.

allowed_methods(RD, Ctx) ->
    Methods = ['GET'],
    {Methods, RD, Ctx}.

content_types_provided(RD, Ctx) ->
    Types = [{"application/json", provide_content}],
    {Types, RD, Ctx}.

resource_exists(RD, Ctx=?listBucketTypes()) ->
    Response = riak_explorer:bucket_types(),
    {true, RD, Ctx#ctx{response=Response}};
resource_exists(RD, Ctx=?bucketTypeInfo(BucketType)) ->
    Response = [{bucket_type, list_to_binary(BucketType)}],
    {true, RD, Ctx#ctx{response=Response}};
resource_exists(RD, Ctx=?bucketTypeResource(BucketType, Resource)) ->
    RKey = list_to_atom(Resource),
    case proplists:get_value(RKey, resources()) of
        [M,F] -> 
            Response = M:F(BucketType),
            {true, RD, Ctx#ctx{response=Response}};
        _ -> 
            {false, RD, Ctx}
    end;
resource_exists(RD, Ctx) ->
    {false, RD, Ctx}.

provide_content(RD, Ctx=#ctx{response=Response}) ->
    render_json(Response, RD, Ctx).

%% ====================================================================
%% Private
%% ====================================================================

render_json(Data, RD, CTX) ->
    Body = mochijson2:encode(Data),
    {Body, RD, CTX}.