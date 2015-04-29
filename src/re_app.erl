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

-module(re_app).
-behaviour(application).
-export([start/2, stop/1]).
-include("riak_explorer.hrl").

%%%===================================================================
%%% Callbacks
%%%===================================================================

start(_StartType, _StartArgs) ->
    % Enabled = ?RE_ENABLED,
    Enabled = true,
    case re_sup:start_link(Enabled) of
        {ok, Pid} ->
            maybe_setup(Enabled),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    ok.

%%%===================================================================
%%% Private
%%%===================================================================

%% @private
%%
%% @doc Conditionally add routes to webmachine
maybe_setup(false) ->
    ok;
maybe_setup(true) ->
    Routes = [
        {[?RE_BASE_ROUTE], re_wm_explore, []},
        {[?RE_BASE_ROUTE, resource], re_wm_explore, []}],
    add_routes(Routes),
    ok.

%% @private
%%
%% @doc Add list of webmachine routes to the router.
add_routes(Routes) ->
    [webmachine_router:add_route(R) || R <- Routes].