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

-module(re_wm_proxy).

-export([routes/0]).

-export([send_proxy_request/4]).

-export([proxy_available/1]).

-define(BASE, "riak").
-define(PROXY_BASE, [?BASE]).

-include_lib("webmachine/include/webmachine.hrl").
-include("re_wm.hrl").

%%%===================================================================
%%% API
%%%===================================================================

-spec routes() -> [route()].
routes() ->
    [#route{base=[?PROXY_BASE],
            path=[["clusters", cluster, '*']],
            available={?MODULE,proxy_available}},
     #route{base=[?PROXY_BASE],
            path=[["nodes", node, '*']],
            available={?MODULE,proxy_available}}
    ].

send_proxy_request(Location, RelPath, NewLocation, ReqData) ->
    Path = lists:append(
             [Location,
              RelPath,
              case wrq:req_qs(ReqData) of
                  [] -> [];
                  Qs -> [$?|mochiweb_util:urlencode(Qs)]
              end]),

    lager:info("Sending Explorer Proxy Request to: ~p", [Path]),

    %% translate webmachine details to ibrowse details
    Headers = clean_request_headers(
                mochiweb_headers:to_list(wrq:req_headers(ReqData))),
    Method = wm_to_ibrowse_method(wrq:method(ReqData)),
    ReqBody = case wrq:req_body(ReqData) of
                  undefined -> [];
                  B -> B
              end,

    case ibrowse:send_req(Path, Headers, Method, ReqBody) of
        {ok, Status, RiakHeaders, RespBody} ->
            RespHeaders = fix_location(RiakHeaders, NewLocation),
            {{halt, list_to_integer(Status)},
             wrq:set_resp_headers(RespHeaders,
                                  wrq:set_resp_body(RespBody, ReqData))};
        {error, Reason} ->
            re_wm:add_content({error, Reason}, ReqData);
        _ ->
            {false, ReqData}
    end.

%%%===================================================================
%%% Callbacks
%%%===================================================================

proxy_available(ReqData) ->
    case {re_wm:rd_cluster_exists(ReqData),
          re_wm:rd_node_exists(ReqData)} of
        {{true,_}, {true,_}} ->
            send_proxy_request(ReqData);
        E ->
            lager:info("E: ~p", [E]),
            {{halt, 404}, ReqData}
    end.

%% ====================================================================
%% Private
%% ====================================================================

send_proxy_request(ReqData) ->
    N = re_wm:rd_node(ReqData),
    C = re_wm:rd_cluster(ReqData),

    case re_node:http_listener(N) of
        {error, Reason} ->
            re_wm:add_content({error, Reason}, ReqData);
        Listener ->
            RiakPath = "http://" ++ binary_to_list(Listener) ++ "/",
            Path = wrq:disp_path(ReqData),
            NewLocation = re_wm:rd_url(ReqData) ++ ?BASE++"/clusters/"++atom_to_list(C),
            send_proxy_request(RiakPath, Path, NewLocation, ReqData)
    end.

clean_request_headers(Headers) ->
    [{K,V} || {K,V} <- Headers,
              K /= 'Host',
              K /= 'Content-Length',
              K /= 'X-Requested-With',
              K /= 'Referer'].

wm_to_ibrowse_method(Method) when is_list(Method) ->
    list_to_atom(string:to_lower(Method));
wm_to_ibrowse_method(Method) when is_atom(Method) ->
    wm_to_ibrowse_method(atom_to_list(Method)).

fix_location([], _) -> [];
fix_location([{"Location", RiakDataPath}|Rest], NewLocation) ->
    [{"Location", NewLocation++RiakDataPath}|Rest];
fix_location([H|T], NewLocation) ->
    [H|fix_location(T, NewLocation)].
