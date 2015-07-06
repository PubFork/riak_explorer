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

-module(re_keyjournal).
-export([cache_for_each/4,
         clean/1,
         read_cache/3,
         write/1,
         write_cache/2,
         handle_list/1]).

-include("riak_explorer.hrl").

%%%===================================================================
%%% API
%%%===================================================================

cache_for_each({Operation, Node, Path}, Fun, Mode, InitAccum) ->
    Cluster = re_riak:cluster_id_for_node(Node),
    Dir = re_file_util:ensure_data_dir([atom_to_list(Operation), atom_to_list(Cluster)] ++ Path),
    {ok, Files} = file:list_dir(Dir),
    case Files of
       [File|_] ->
          DirFile = filename:join([Dir, File]),
          re_file_util:for_each_line_in_file(DirFile,Fun, Mode, InitAccum);
       [] -> {error, not_found}
    end.

clean({Operation, Node, Path}) ->
   Cluster = re_riak:cluster_id_for_node(Node),
   Dir = re_file_util:ensure_data_dir([atom_to_list(Operation), atom_to_list(Cluster)] ++ Path),
   {ok, Files} = file:list_dir(Dir),

   case Files of
        [] ->
            {error, not_found};
        _ ->
            lists:foreach(fun(File) ->
                DirFile = filename:join([Dir, File]),
                file:delete(DirFile)
            end, Files),
            ok
   end.

read_cache({Operation, Node, Path}, Start, Rows) ->
   Cluster = re_riak:cluster_id_for_node(Node),
   Dir = re_file_util:ensure_data_dir([atom_to_list(Operation), atom_to_list(Cluster)] ++ Path),
   {ok, Files} = file:list_dir(Dir),
   case Files of
      [File|_] ->
         DirFile = filename:join([Dir, File]),
         {Total, ResultCount, _S, _E, Entries} = entries_from_file(DirFile, Start - 1, Rows - 1),
         [{Operation, [{total, Total},{count, ResultCount},{created, list_to_binary(timestamp_human(File))},{Operation, Entries}]}];
      [] -> {error, not_found}
   end.

write({Operation, _, _}=Meta) ->
   re_job_manager:create(Operation, {?MODULE, handle_list, [Meta]}).

write_cache({Operation, Node, Path}, Objects) ->
   Cluster = re_riak:cluster_id_for_node(Node),
   Dir = re_file_util:ensure_data_dir([atom_to_list(Operation), atom_to_list(Cluster)] ++ Path),
   {ok, Files} = file:list_dir(Dir),
   DirFile = case Files of
      [File|_] -> filename:join([Dir, File]);
      [] -> filename:join([Dir, timestamp_string()])
   end,

   {ok, Device} = file:open(DirFile, [append]),
   update_cache(Objects, Device),
   file:close(Device),
   ok.

%%%===================================================================
%%% Callbacks
%%%===================================================================

handle_list({buckets, Node, [BucketType]}=Meta) ->
   C = re_riak:client(Node),
   Stream = riakc_pb_socket:stream_list_buckets(C, list_to_binary(BucketType)),
   handle_stream(Meta, Stream);
handle_list({keys, Node, [BucketType, Bucket]}=Meta) ->
   C = re_riak:client(Node),
   B = {list_to_binary(BucketType), list_to_binary(Bucket)},
   Stream = riakc_pb_socket:stream_list_keys(C, B),
   handle_stream(Meta, Stream).

handle_stream({Operation, Node, Path}=Meta, {ok, ReqId}) ->
   Cluster = re_riak:cluster_id_for_node(Node),
   Dir = re_file_util:ensure_data_dir([atom_to_list(Operation), atom_to_list(Cluster)] ++ Path),
   TimeStamp = timestamp_string(),
   FileName = filename:join([Dir, TimeStamp]),
   file:write_file(FileName, "", [write]),
   clean(Meta),
   lager:info("list started for file: ~p at: ~p", [FileName, TimeStamp]),
   {ok, Device} = file:open(FileName, [append]),
   write_loop(Meta, ReqId, Device, 0);
handle_stream({Operation, _Node, Path}, Error) ->
   lager:error(atom_to_list(Operation) ++ " list failed for path: ~p with reason: ~p", [Path, Error]).

write_loop({Operation, _,_}=Meta, ReqId, Device, Count) ->
    receive
        {ReqId, done} ->
            re_job_manager:finish(Operation),
            lager:info("list finished for file with ~p", [{count, Count}]),
            file:close(Device);
        {ReqId, {error, Reason}} ->
            re_job_manager:error(Operation, [{error, Reason}]),
            lager:error("list failed for file with reason: ~p", [Reason]),
            file:close(Device);
        {ReqId, {_, Res}} ->
            Count1 = Count + length(Res),
            Device1 = case Res of
               "" -> Device;
               Entries ->
                  re_job_manager:set_meta(Operation, [{count, Count1}]),
                  update_cache(Entries, Device)
            end,
            write_loop(Meta, ReqId, Device1, Count1)
    end.

%%%===================================================================
%%% Private
%%%===================================================================

update_cache([], Device) ->
   Device;
update_cache([Object|Rest], Device) ->
   io:fwrite(Device, binary_to_list(Object) ++ "~n", []),
   update_cache(Rest, Device).

timestamp_string() ->
    {{Year,Month,Day},{Hour,Min,Sec}} = calendar:now_to_universal_time(now()),
    lists:flatten(io_lib:fwrite("~4..0B~2.10.0B~2.10.0B~2.10.0B~2.10.0B~2.10.0B",[Year, Month, Day, Hour, Min, Sec])).

timestamp_human(Time) ->
   Year = lists:sublist(Time, 4),
   Month = lists:sublist(Time, 5, 2),
   Day = lists:sublist(Time, 7, 2),
   Hour = lists:sublist(Time, 9, 2),
   Min = lists:sublist(Time, 11, 2),
   Sec = lists:sublist(Time, 13, 2),
   lists:flatten(io_lib:fwrite("~s-~s-~s ~s:~s:~s",[Year, Month, Day, Hour, Min, Sec])).

entries_from_file(File, Start, Rows) ->
   re_file_util:for_each_line_in_file(File,
      fun(Entry, {T, RC, S, E, Accum}) ->
         case should_add_entry(T, S, E) of
            true ->
               B = re:replace(Entry, "(^\\s+)|(\\s+$)", "", [global,{return,list}]),
               {T + 1, RC + 1, S, E, [list_to_binary(B)|Accum]};
            _ -> {T + 1, RC, S, E, Accum}
         end
      end, [read], {0, 0, Start, Start+Rows,[]}).

should_add_entry(Total, _Start, Stop) when Total > Stop -> false;
should_add_entry(Total, Start, _Stop) when Total >= Start -> true;
should_add_entry(_Total, _Start, _Stop) -> false.
