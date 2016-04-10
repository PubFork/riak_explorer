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

-module(re_node).

-type(re_node() :: node()).
-export_type([re_node/0]).

-type(re_node_type() :: oss | ee | ts | ts_ee).
-export_type([re_node_type/0]).

-type(re_node_prop() ::
        {id, node()} |
        {riak_type, re_node_type() | unavailable} |
        {riak_version, binary() | unavailable} |
        {available, boolean()}).

-type(re_node_props() :: [re_node_prop()]).
-export_type([re_node_props/0]).

-type(ts_table() :: string() | binary()).
-type(ts_key() :: [term()]).
-type(ts_result() :: [{atom(), term()}]).

-export([exists/1,
         props/1,
         type/1,
         version/1,
         available/1,
         ring_members/1]).

-export([delete_bucket/4,
         delete_bucket/5,
         delete_bucket_job/1,
         get_ts/3,
         put_ts/3,
         query_ts/2]).

-export([list_buckets_cache/5,
         list_buckets/4,
         clean_buckets/3,
         put_buckets/4,
         list_keys_cache/6,
         list_keys/5,
         clean_keys/4,
         put_keys/5]).

-export([log_files/1,
         log_file/3,
         log_file_exists/2,
         config_file/2,
         config_files/1,
         config_file_exists/2,
         config/1,
         http_listener/1,
         pb_listener/1,
         bucket_type_exists/2,
         bucket_type/2,
         bucket_types/1,
         table_exists/2,
         table/2,
         tables/1,
         create_bucket_type/3]).

-export([command/4,
         client/1]).

%%%===================================================================
%%% API
%%%===================================================================

-spec exists(re_node()) -> boolean().
exists(N) ->
    available(N).

-spec props(re_node()) -> re_node_props().
props(N) ->
    [{id,N},
     {riak_type, type(N)},
     {riak_version, version(N)},
     {available, available(N)}].

-spec type(re_node()) -> re_node_type() | unavailable.
type(N) ->
    case {command(N, re_riak_patch, is_enterprise, []),
          command(N, re_riak_patch, is_timeseries, [])} of
        {false, false} -> oss;
        {true, false} -> ee;
        {false, true} -> ts;
        {true, true} -> ts_ee;
        _ -> unavailable
    end.

-spec version(re_node()) -> binary() | unavailable.
version(N) ->
    case re_call:call(N, re_riak_patch, riak_version, []) of
        {error, _} ->
            unavailable;
        Version ->
            Version
    end.

-spec available(re_node()) -> boolean().
available(N) ->
    is_atom(command(N, erlang, node, [])).

-spec ring_members(re_node()) -> {error, term()} | [re_node()].
ring_members(N) ->
    case command(N, riak_core_ring_manager, get_my_ring, []) of
        {error, Reason} -> 
            {error, Reason};
        {ok, MyRing} ->
            case command(N, riak_core_ring, all_members, [MyRing]) of
                {error, Reason} ->
                    {error, Reason};
                Members ->
                    lists:sort(Members)
            end
    end.

-spec get_ts(re_node(), ts_table(), ts_key()) ->
                    {error, term()} | ts_result().
get_ts(Node, Table, Key) ->
    C = client(Node),
    case riakc_ts:get(C, Table, Key, []) of
        {ok, {Fields, Rows}} -> 
            [{fields, Fields},{rows, Rows}];
        {error, Reason} ->
            {error, Reason}
    end.

-spec put_ts(re_node(), ts_table(), [term()]) ->
                    {error, term()} | ok.
put_ts(Node, Table, Rows) ->
    C = client(Node),
    case riakc_ts:put(C, Table, Rows) of
        ok -> 
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

-spec query_ts(re_node(), binary()) ->
                      {error, term()} | ts_result().
query_ts(Node, Query) ->
    C = client(Node),
    {Fields, Rows} = 
        case riakc_ts:query(C, Query) of
            {[],[]} ->
                {[],[]};
            {Fields1, TupleRows} ->
                TupleToRowFun = 
                    fun(Tuple) ->
                            [element(I,Tuple) 
                             || I <- lists:seq(1,tuple_size(Tuple))]
                    end,
                Rows1 = lists:map(TupleToRowFun, TupleRows),
                {Fields1, Rows1};
            {error, Reason} -> 
                {error, Reason}
        end,
    case {Fields, Rows} of
        {error, Reason1} ->
            {error, Reason1};
        _ ->
            [{fields, Fields},{rows, Rows}]
    end.

-spec delete_bucket(re_cluster:re_cluster(), re_node(), binary(), binary()) ->
                           {error, term()} | ok.
delete_bucket(Cluster, Node, BucketType, Bucket) ->
    delete_bucket(Cluster, Node, BucketType, Bucket, true).

-spec delete_bucket(re_cluster:re_cluster(), re_node(), binary(), binary(), binary()) ->
                           {error, term()} | ok.
delete_bucket(Cluster, Node, BucketType, Bucket, RefreshCache) ->
    case re_cluster:development_mode(Cluster) of
        true ->
            JobType = delete_bucket,
            Meta = {JobType, Cluster, Node, [BucketType, Bucket, RefreshCache]},
            re_job_manager:create(JobType, {?MODULE, delete_bucket_job, [Meta]});
        false ->
            lager:warning("Failed request to delete types/~p/buckets/~p because developer mode is off", [BucketType, Bucket]),
            {error, developer_mode_off}
    end.

%%TODO: this is a callback, organize it better.
-spec delete_bucket_job({atom(), re_cluster:re_cluster(), re_node(), [term()]}) ->
                           {error, term()} | ok.
delete_bucket_job({delete_bucket, Cluster, Node, [BucketType, Bucket, RefreshCache]}) ->
    C = client(Node),
    case re_keyjournal:cache_for_each({keys, Cluster, Node, [BucketType, Bucket]},
            fun(Entry0, {Oks0, Errors0}) ->
                RT = list_to_binary(BucketType),
                RB = list_to_binary(Bucket),
                RK = list_to_binary(re:replace(Entry0, "(^\\s+)|(\\s+$)", "", [global,{return,list}])),
                {Oks1,Errors1} = case riakc_pb_socket:delete(C, {RT,RB}, RK) of
                    ok ->
                        riakc_pb_socket:get(C, {RT,RB}, RK),
                        {Oks0+1, Errors0};
                    {error, Reason} ->
                        lager:warning("Failed to delete types/~p/buckets/~p/keys/~p with reason ~p", [RT, RB, RK, Reason]),
                        {Oks0, Errors0+1}
                end,
                re_job_manager:set_meta(delete_bucket, [{oks, Oks1},{errors,Errors1}]),
                {Oks1,Errors1}
            end, [read], {0, 0}) of
        [{error, not_found}] ->
            lager:warning("Deletetion of types/~p/buckets/~p could not be completed because no cache was found", [BucketType, Bucket]),
            re_job_manager:error(delete_bucket, [{error, cache_not_found}]);
        {Os,Es} ->
            lager:info("Completed deletion of types/~p/buckets/~p with ~p successful deletes and ~p errors", [BucketType, Bucket, Os, Es]),
            re_job_manager:finish(delete_bucket),
            case RefreshCache of
                true ->
                    %% TODO: track errors?
                    clean_buckets(Cluster, Node, BucketType),
                    clean_keys(Cluster, Node, BucketType, Bucket);
                    %% TODO: Want to list keys here eventually, but need to deal with
                    %% tombstone reaping
                false ->
                    ok
            end
    end.

list_buckets(Cluster, Node, BucketType, Options) ->
    case re_config:development_mode(Cluster) of
        true ->
            re_keyjournal:write({buckets, Cluster, Node, [BucketType]}, Options);
        false ->
            {error, developer_mode_off}
    end.

list_buckets_cache(Cluster, Node, BucketType, Start, Rows) ->
    re_keyjournal:read_cache({buckets, Cluster, Node, [BucketType]}, Start, Rows).

clean_buckets(Cluster, Node, BucketType) ->
    re_keyjournal:clean({buckets, Cluster, Node, [BucketType]}).

put_buckets(Cluster, Node, BucketType, Buckets) ->
    re_keyjournal:write_cache({buckets, Cluster, Node, [BucketType]}, Buckets).

list_keys(Cluster, Node, BucketType, Bucket, Options) ->
    case re_config:development_mode(Cluster) of
        true ->
            re_keyjournal:write({keys, Cluster, Node, [BucketType, Bucket]}, Options);
        false ->
            {error, developer_mode_off}
    end.

list_keys_cache(Cluster, Node, BucketType, Bucket, Start, Rows) ->
    re_keyjournal:read_cache({keys, Cluster, Node, [BucketType, Bucket]}, Start, Rows).

clean_keys(Cluster, Node, BucketType, Bucket) ->
    re_keyjournal:clean({keys, Cluster, Node, [BucketType, Bucket]}).

put_keys(Cluster, Node, BucketType, Bucket, Keys) ->
    re_keyjournal:write_cache({keys, Cluster, Node, [BucketType, Bucket]}, Keys).

log_files(Node) ->
    Files = command(Node, re_riak_patch, get_log_files, []),
    WithIds = lists:map(fun(N) -> [{id, list_to_binary(N)}] end, Files),
    [{files, WithIds}].

log_file_exists(Node, File) ->
    Files = command(Node, re_riak_patch, get_log_files, []),
    lists:member(File, Files).

log_file(Node, File, NumLines) ->
    case re:run(File, ".log(.[0-9])?$") of
        {match,_} ->
            case command(Node, re_riak_patch, tail_log, [File, NumLines]) of
                {error, _} ->
                    [{error, not_found}];
                {Total, Lines} ->
                    [{log, [{total_lines, Total},{lines, Lines}]}]
            end;
        _ ->
            [{error, not_found}]
    end.

config_files(Node) ->
    Files = command(Node, re_riak_patch, get_config_files, []),
    WithIds = lists:map(fun(N) -> [{id, list_to_binary(N)}] end, Files),
    [{files, WithIds}].

config_file_exists(Node, File) ->
    Files = command(Node, re_riak_patch, get_config_files, []),
    lists:member(File, Files).

config_file(Node, File) ->
    case command(Node, re_riak_patch, get_config, [File]) of
        {error, _} ->
            [{error, not_found}];
        Lines ->
            [{files, [{lines, Lines}]}]
    end.

config(Node) ->
    try
        case command(Node, re_riak_patch, effective_config, []) of
            {error, legacy_config} ->
                [{error, not_found, [{error, <<"Legacy configuration files found, effective config not available.">>}]}];
            Config ->
                [{config, Config}]
        end
    catch
        Exception:Reason ->
            Error = list_to_binary(io_lib:format("~p:~p", [Exception,Reason])),
            lager:info("~p:~p", [Exception, Reason]),
            lager:info("Backtrace: ~p", [erlang:get_stacktrace()]),
            [{config, [{error, Error}]}]
    end.

http_listener(Node) ->
    NodeStr = atom_to_list(Node),
    [_,Addr] = string:tokens(NodeStr, "@"),
    {ok,[{_,Port}]} = command(Node, application, get_env, [riak_api, http]),
    [{http_listener, list_to_binary(Addr ++ ":" ++ integer_to_list(Port))}].

pb_listener(Node) ->
    NodeStr = atom_to_list(Node),
    [_,Addr] = string:tokens(NodeStr, "@"),
    {ok,[{_,Port}]} = command(Node, application, get_env, [riak_api, pb]),
    [{pb_listener, list_to_binary(Addr ++ ":" ++ integer_to_list(Port))}].

bucket_type_exists(Node, BucketType) ->
    case bucket_type(Node, BucketType) of
        [{error, not_found}] ->
            false;
        _ ->
            true
    end.

bucket_type(Node, BucketType) ->
    FlatProps = lists:flatten([proplists:get_value(props, Prop) ||
                           Prop <- proplists:get_value(bucket_types, bucket_types(Node)),
                           BucketType =:= proplists:get_value(name, Prop)]),
    case FlatProps of
        [] ->
            [{error, not_found}];
        Props ->
            [{bucket_types, [{id,BucketType}, {props, Props}]}]
    end.

bucket_types(Node) ->
    List0 = command(Node, re_riak_patch, bucket_types, []),
    List1 = lists:filtermap(
              fun([{name, _}, {props, Props}]) ->
                      proplists:get_value(ddl, Props) =:= undefined
              end, List0),
    List = lists:sort(fun([{name, N1}|_], [{name, N2}|_]) -> N1 < N2 end, List1),
    [{bucket_types, List}].

table_exists(Node, Table) ->
    case table(Node, Table) of
        [{error, not_found}] -> false;
        _ -> true
    end.

table(Node, Table) ->
    FlatProps = lists:flatten([proplists:get_value(props, Prop) ||
                           Prop <- proplists:get_value(tables, tables(Node)),
                           Table =:= proplists:get_value(name, Prop)]),
    case FlatProps of
        [] ->
            [{error, not_found}];
        Props ->
            [{tables, [{id,Table}, {props, Props}]}]
    end.

tables(Node) ->
    List0 = command(Node, re_riak_patch, bucket_types, []),
    List1 = lists:filtermap(
              fun([{name, _}, {props, Props}]) ->
                      proplists:get_value(ddl, Props) =/= undefined
              end, List0),
    List = lists:sort(fun([{name, N1}|_], [{name, N2}|_]) -> N1 < N2 end, List1),
    [{tables, List}].

create_bucket_type(Node, BucketType, RawValue) ->
    {Created, Active} = case bucket_type(Node, list_to_binary(BucketType)) of
        [{error, not_found}] -> {false, false};
        [{bucket_types, Type}] ->
            Props = proplists:get_value(props, Type),
            {true, proplists:get_value(active, Props, false)}
    end,

    case {Created, Active} of
        {false, _} ->
            bucket_type_action(Node, BucketType, RawValue, [create, activate], []);
        {true, false} ->
            bucket_type_action(Node, BucketType, RawValue, [activate], []);
        {true, true} ->
            bucket_type_action(Node, BucketType, RawValue, [update], [])
    end.

-spec command(re_node(), module(), atom(), [term()]) -> {error, term()} | term().
command(N, M, F, A) ->
    case riak_explorer:is_riak() and is_self(N) of
        true ->
            local_command(M, F, A);
        _ ->
            remote_command(N, M, F, A)
    end.

-spec client(re_node()) -> {error, term()} | pid().
client(Node) ->
    case command(Node, application, get_env, [riak_api, pb]) of
        {error, Reason} -> 
            {error, Reason};
        {ok,[{Ip,Port}]} -> 
            case riakc_pb_socket:start_link(Ip, Port) of
                {error, Reason} ->
                    {error, Reason};
                {ok, Pid} ->
                    Pid
            end
    end.

%%%===================================================================
%%% Private
%%%===================================================================

-spec remote_command(re_node(), module(), atom(), [term()]) -> {error, term()} | term().
remote_command(N, re_riak_patch, F, A) ->
    case ensure_patch_loaded(N) of
        {error, Reason} -> 
            {error, Reason};
        {module, re_riak_patch} ->
            safe_rpc(N, re_riak_patch, F, A, 60000)
    end;
remote_command(N, M, F, A) ->
    safe_rpc(N, M, F, A, 60000).

-spec local_command(module(), atom(), [term()]) -> term().
local_command(M, F, A) ->
    erlang:apply(M, F, A).

-spec safe_rpc(re_node(), module(), atom(), [term()]) -> {error, term()} | term().
safe_rpc(N, M, F, A) ->
    safe_rpc(N, M, F, A, 10000).

-spec safe_rpc(re_node(), module(), atom(), [term()], timeout()) -> {error, term()} | term().
safe_rpc(N, M, F, A, Timeout) ->
    Result = try rpc:call(N, M, F, A, Timeout) of
                 R ->
                     R
             catch
                 'EXIT':{noproc, _NoProcDetails} ->
                     {badrpc, rpc_process_down}
             end,
    case Result of
        {badrpc, Reason} -> {error, Reason};
        _ -> Result
    end.

-spec is_self(re_node()) -> boolean().
is_self(N) -> is_self(N, node()).

-spec is_self(re_node(), atom()) -> boolean().
is_self(N, N) -> true;
is_self(_, _) -> false.

-spec ensure_patch_loaded(re_node()) -> {error, term()} | {module, module()}.
ensure_patch_loaded(N) ->
    case safe_rpc(N, code, ensure_loaded, [re_riak_patch]) of
        {module, re_riak_patch} ->
            LocalVersion = re_riak_patch:version(),
            RemoteVersion = safe_rpc(N, re_riak_patch, version, []),
            lager:info("Found version ~p of re_riak_patch on node[~p], current version is ~p.", [RemoteVersion, N, LocalVersion]),
            case LocalVersion =:= RemoteVersion of
                false -> load_patch(N);
                _ -> {module, re_riak_patch}
            end;
        _ ->
            load_patch(N)
    end.

-spec load_patch(re_node()) -> {error, term()} | {module, module()}.
load_patch(N) ->
    lager:info("Loading re_riak_patch module into ~p.", [N]),
    {Mod, Bin, _} = code:get_object_code(re_riak_patch),
    safe_rpc(N, code, load_binary, [Mod, "/tmp/re_riak_patch.beam", Bin], 60000).
