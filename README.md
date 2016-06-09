# Riak Explorer

[![Join the chat at https://gitter.im/basho-labs/riak_explorer](https://badges.gitter.im/basho-labs/riak_explorer.svg)](https://gitter.im/basho-labs/riak_explorer?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Riak Explorer provides browsing and admin capabilities for [Riak
KV](http://basho.com/products/riak-kv/) and [Riak TS](http://basho.com/products/riak-ts/), a distributed NoSQL data
store that offers high availability, fault tolerance, operational simplicity,
and scalability.

Riak Explorer is useful while in a development or production. It includes
convenient methods to browse Bucket Types, Buckets, Keys, view and edit Riak
Objects, and more. To prevent heavy I/O requests from key listings, be sure to
edit the config file to reflect the environment as [explained in Using Riak
Explorer](#using-riak-explorer).

* [Demo](http://104.236.156.86/)
* [Installation](#installation)
* [System Architecture](#system-architecture)
* [Using Riak Explorer](#using-riak-explorer)
* [Development / Contributing](#development--contributing)

## Installation

### Installing from pre-built Package

The easiest way to install Riak Explorer (for non-developers) is to use one of
the pre-compiled packages below. These include both the Erlang backend API code
(this repository), and the front-end Ember.js GUI code (from
[riak-explorer-gui](https://github.com/basho-labs/riak-explorer-gui)).

#### Standalone Version

1. Download and extract a `.tar.gz` release from the releases page: [https://github.com/basho-labs/riak_explorer/releases](https://github.com/basho-labs/riak_explorer/releases).
     * *Note: If you'd like to support further OSes, please [open an Issue](https://github.com/basho-labs/riak_explorer/issues)*

2. Verify the default settings in `riak_explorer/etc/riak_explorer.conf`
    will work for your configuration (primarily that port 9000 is available on your
    host). Pay special attention to development mode settings, this should be `off`
    for use with a production environment to prevent accidental keylistings.

3. Run `./riak_explorer/bin/riak_explorer start` to start the `riak_explorer`
    application

4. Navigate to [http://localhost:9000/](http://localhost:9000/)

#### Riak Patch Version

1. Download and extract a `patch` release from the releases page: [https://github.com/basho-labs/riak_explorer/releases](https://github.com/basho-labs/riak_explorer/releases).

2. Locate your Riak installation and `cp -R root/riak/lib/basho-patches/* /path/to/riak/lib/basho-patches/`, `cp -R /root/riak/priv /path/to/riak/priv`.

3. Run `riak/bin/riak start`

4. Navigate to [http://localhost:8098/admin](http://localhost:8098/admin)

### Installing the Dev Environment

For developer install instructions (and contribution guidelines), see the
[Development / Contributing](#development--contributing) section, below.

## System Architecture

*Front-end GUI:* [Ember.js](http://emberjs.com/).
    See [riak-explorer-gui](https://github.com/basho-labs/riak-explorer-gui)
    repository for the front-end code and setup instructions.

*Back-end:* [Erlang](http://www.erlang.org/) is the primary development language
    and [WebMachine](http://webmachine.github.io/) is used to serve a RESTful
    API (and, optionally, to serve the Ember.js GUI app).
    
## Using Riak Explorer

### Development Mode

The concept of "Development Mode" is crucial to Riak Explorer.

Because Explorer allows users to perform operations that are disastrous in
production (such as List Keys or List Buckets operations), the app is careful
to enable those operations *only in Development Mode*. This setting is
toggled in the Explorer config file, on a per-cluster basis.

If you take a look in `rel/riak_explorer/etc/riak_explorer.conf`, you will see
a line like:

```
clusters.default.development_mode = on
```

This means that the `default` cluster has Dev Mode *enabled*, and *WILL* allow
prohibitive operations such as Streaming List Keys. Operators are strongly
encouraged to either:

a. Not point Explorer at production clusters, or

b. If used with production clusters, be sure to set `development_mode = off` for
    that cluster.

### Table Row, Key, and Bucket List Caches (in Dev Mode only)

Even in Dev Mode, Explorer tries not to run listing operations
more than necessary. To that end, the API runs the List command once requested by the user and then *caches* the
result in a text file, on disk. The GUI app user, when browsing a list, only
interacts with those caches.

### Explorer API endpoints

The three types of API endpoints available are:

1. The **Riak proxy** endpoints, `/riak/nodes/` and `/riak/clusters/`. The app
    uses these endpoints to make calls to the plain [Riak HTTP
    API](http://docs.basho.com/riak/latest/dev/references/http/). The proxy
    endpoints are used for several reasons, primarily due to CORS issues
    (on the Riak API side).

    So, for example, `curl localhost:9000/riak/nodes/riak@127.0.0.1/ping`
    proxies the request to that specific node's [ping HTTP API](http://docs.basho.com/riak/latest/dev/references/http/ping/).

    Similarly, using `curl localhost:9000/riak/clusters/default/ping`
    proxies the request to the *cluster* (which also ends up going to that same
    node, since this cluster just has one node in it).

    In general, it is preferable to use the `clusters/` proxy endpoint (unless
    you specifically want to access an individual node's REST API).

2. **Explore** endpoints, at `/explore/`. Think of it as an enhancement to
    Riak's own HTTP API, to fill in missing functionality. For example,
    the plain Riak API doesn't have a 'list bucket types' functionality --
    that can only be done via `riak-admin` CLI. The Explorer endpoints enable
    this, at `/explore/clusters/$cluster/bucket_types`.

3. **Control** endpoints at `/control/`. These provide a REST API to cluster
    operations that are normally available only through the [Riak Admin
    CLI](http://docs.basho.com/riak/latest/ops/running/tools/riak-admin/)
    (for example, `riak-admin cluster join`).

### API Documentation

For in-depth documentation of the available API endpoints, complete with
sample responses, see [Riak Explorer API](http://basho-labs.github.io/riak_explorer/docs/api.html).

You can also generate this API documentation locally, using
[aglio](https://github.com/danielgtaylor/aglio):

```
# install the Aglio renderer for the API Blueprint markdown format
npm install -g aglio

# generate the documentation
aglio -i API.apib.md --theme-full-width -o docs/api.html

# open them in your browser
open docs/api.html
```

The source code for these docs is in [API Blueprint Format](https://github.com/apiaryio/api-blueprint/blob/master/API Blueprint Specification.md) (see also the [sample API markup example](https://raw.githubusercontent.com/danielgtaylor/aglio/master/example.apib)),
and is located in the [API.apib.md](https://github.com/basho-labs/riak_explorer/blob/gh-pages/API.apib.md) file on the `gh-pages` branch.

**To add to the API documentation:**

1. Check out the `gh-pages` branch:

    ```
    git checkout gh-pages
    ```

2. Make changed to the source markup.
3. Generate the HTML using `aglio` (see above).
4. Commit both the source markup and the generated HTML.
5. `git push origin gh-pages`

#### Full API Endpoint Listing

Riak Explorer exposes a REST API (by default located at [http://localhost:9000/explore](http://localhost:9000/explore)).

Following are the available routes (these can also be obtained from `/explore/routes`):

```
/explore/nodes/$node/bucket_types/$bucket_type/buckets/$bucket/keys
/explore/nodes/$node/bucket_types/$bucket_type/buckets/$bucket/refresh_keys/source/riak_kv
/explore/clusters/$cluster/bucket_types/$bucket_type/buckets/$bucket/keys
/explore/clusters/$cluster/bucket_types/$bucket_type/buckets/$bucket/refresh_keys/source/riak_kv
/explore/nodes/$node/bucket_types/$bucket_type/buckets/$bucket/$resource (Resources: [jobs])
/explore/nodes/$node/bucket_types/$bucket_type/buckets/$bucket
/explore/nodes/$node/bucket_types/$bucket_type/buckets
/explore/nodes/$node/bucket_types/$bucket_type/refresh_buckets/source/riak_kv
/explore/clusters/$cluster/bucket_types/$bucket_type/buckets/$bucket/$resource (Resources: [jobs])
/explore/clusters/$cluster/bucket_types/$bucket_type/buckets/$bucket
/explore/clusters/$cluster/bucket_types/$bucket_type/buckets
/explore/clusters/$cluster/bucket_types/$bucket_type/refresh_buckets/source/riak_kv
/explore/nodes/$node/bucket_types/$bucket_type/$resource (Resources: [jobs])
/explore/nodes/$node/bucket_types/$bucket_type
/explore/nodes/$node/bucket_types
/explore/clusters/$cluster/bucket_types/$bucket_type/$resource (Resources: [jobs])
/explore/clusters/$cluster/bucket_types/$bucket_type
/explore/clusters/$cluster/bucket_types
/explore/nodes/$node
/explore/nodes/$node/$resource (Resources: [config]
/explore/clusters/$cluster/nodes/$node
/explore/clusters/$cluster/nodes/$node/$resource (Resources: [config])
/explore/clusters/$cluster/nodes
/explore/nodes/$node/config/files/$file
/explore/nodes/$node/config/files
/explore/clusters/$cluster/nodes/$node/config/files/$file
/explore/clusters/$cluster/nodes/$node/config/files
/explore/nodes/$node/log/files/$file
/explore/nodes/$node/log/files
/explore/clusters/$cluster/nodes/$node/log/files/$file
/explore/clusters/$cluster/nodes/$node/log/files
/explore/clusters/$cluster
/explore/clusters
/explore
/explore/$resource (Resources: [routes,props,jobs,ping])
/control/nodes/$node/repl-fullsync-stop/$arg1
/control/nodes/$node/repl-fullsync-stop
/control/nodes/$node/repl-fullsync-start/$arg1
/control/nodes/$node/repl-fullsync-start
/control/nodes/$node/repl-fullsync-disable/$arg1
/control/nodes/$node/repl-fullsync-enable/$arg1
/control/nodes/$node/repl-realtime-stop/$arg1
/control/nodes/$node/repl-realtime-stop
/control/nodes/$node/repl-realtime-start/$arg1
/control/nodes/$node/repl-realtime-start
/control/nodes/$node/repl-realtime-disable/$arg1
/control/nodes/$node/repl-realtime-enable/$arg1
/control/nodes/$node/repl-clusterstats-realtime
/control/nodes/$node/repl-clusterstats-proxy_get
/control/nodes/$node/repl-clusterstats-fullsync
/control/nodes/$node/repl-clusterstats-fs_coordinate
/control/nodes/$node/repl-clusterstats-cluster_mgr
/control/nodes/$node/repl-clusterstats/$arg1/$arg2
/control/nodes/$node/repl-clusterstats
/control/nodes/$node/repl-connections
/control/nodes/$node/repl-disconnect/$arg1
/control/nodes/$node/repl-connect/$arg1/$arg2
/control/nodes/$node/repl-clustername/$arg1
/control/nodes/$node/repl-clustername
/control/nodes/$node/aae-status
/control/nodes/$node/transfers
/control/nodes/$node/ringready
/control/nodes/$node/status
/control/nodes/$node/clear
/control/nodes/$node/commit
/control/nodes/$node/plan
/control/nodes/$node/force-replace/$arg1/$arg2
/control/nodes/$node/staged-replace/$arg1/$arg2
/control/nodes/$node/replace/$arg1/$arg2
/control/nodes/$node/force-remove/$arg1
/control/nodes/$node/staged-leave/$arg1
/control/nodes/$node/staged-leave
/control/nodes/$node/staged-join/$arg1
/control/nodes/$node/leave/$arg1
/control/nodes/$node/join/$arg1
/control/nodes/$node/repair
/control/clusters/$cluster/repl-fullsync-stop/$arg1
/control/clusters/$cluster/repl-fullsync-stop
/control/clusters/$cluster/repl-fullsync-start/$arg1
/control/clusters/$cluster/repl-fullsync-start
/control/clusters/$cluster/repl-fullsync-disable/$arg1
/control/clusters/$cluster/repl-fullsync-enable/$arg1
/control/clusters/$cluster/repl-realtime-stop/$arg1
/control/clusters/$cluster/repl-realtime-stop
/control/clusters/$cluster/repl-realtime-start/$arg1
/control/clusters/$cluster/repl-realtime-start
/control/clusters/$cluster/repl-realtime-disable/$arg1
/control/clusters/$cluster/repl-realtime-enable/$arg1
/control/clusters/$cluster/repl-clusterstats-realtime
/control/clusters/$cluster/repl-clusterstats-proxy_get
/control/clusters/$cluster/repl-clusterstats-fullsync
/control/clusters/$cluster/repl-clusterstats-fs_coordinate
/control/clusters/$cluster/repl-clusterstats-cluster_mgr
/control/clusters/$cluster/repl-clusterstats/$arg1/$arg2
/control/clusters/$cluster/repl-clusterstats
/control/clusters/$cluster/repl-connections
/control/clusters/$cluster/repl-disconnect/$arg1
/control/clusters/$cluster/repl-connect/$arg1/$arg2
/control/clusters/$cluster/repl-clustername/$arg1
/control/clusters/$cluster/repl-clustername
/control/clusters/$cluster/aae-status
/control/clusters/$cluster/transfers
/control/clusters/$cluster/ringready
/control/clusters/$cluster/status
/control/clusters/$cluster/clear
/control/clusters/$cluster/commit
/control/clusters/$cluster/plan
/control/clusters/$cluster/force-replace/$arg1/$arg2
/control/clusters/$cluster/staged-replace/$arg1/$arg2
/control/clusters/$cluster/replace/$arg1/$arg2
/control/clusters/$cluster/force-remove/$arg1
/control/clusters/$cluster/staged-leave/$arg1
/control/clusters/$cluster/staged-leave
/control/clusters/$cluster/staged-join/$arg1
/control/clusters/$cluster/leave/$arg1
/control/clusters/$cluster/join/$arg1
/control/clusters/$cluster/repair
/riak/nodes/$node/$* (Riak Direct HTTP Proxy)
/riak/clusters/$cluster/$* (Riak Direct HTTP Proxy)
/$* (Static Endpoint)
```

Explanation:

* `$cluster`: Specifying `default` will use the cluster that this riak_explorer is connected to.
* `$node`: Example: `riak@127.0.0.1`
* `$bucket_type`: Example: `default`
* `$bucket`: Example: `mybucket`
* `$key`: Example: `mykey`
* `$schema`: Example: `_yz_default`
* `$index`: Example: `myindex`
* `$*`: Wildcard with deep paths. Example: `assets/ember-riak-explorer.js` for the static route, or `ping` for the riak_proxy route
* `$resource`: A list of valid `resources` for a given module can be found in `explore.resources`

## Development / Contributing

For developer installation instructions and environment setup, visit
[DEVELOPMENT.md](DEVELOPMENT.md).

* Whether your contribution is for a bug fix or a feature request, **create an [Issue](https://github.com/basho/riak_explorer/issues)** and let us know what you are thinking.
* **For bugs**, if you have already found a fix, feel free to submit a Pull Request referencing the Issue you created.
* **For feature requests**, we want to improve upon the library incrementally which means small changes at a time. In order ensure your PR can be reviewed in a timely manner, please keep PRs small, e.g. <10 files and <500 lines changed. If you think this is unrealistic, then mention that within the Issue and we can discuss it.

Once you're ready to contribute code back to this repo, start with these steps:

* Fork the appropriate sub-projects that are affected by your change
* Create a topic branch for your change and checkout that branch
     `git checkout -b some-topic-branch`
* Make your changes and run the test suite if one is provided (see below)
* Commit your changes and push them to your fork
* Open a pull request for the appropriate project
* Contributors will review your pull request, suggest changes, and merge it when it’s ready and/or offer feedback
* To report a bug or issue, please open a new issue against this repository

You can [read the full guidelines for bug reporting and code contributions](http://docs.basho.com/riak/latest/community/bugs/) on the Riak Docs.

And **thank you!** Your contribution is incredibly important to us. It'd be great for you to add it to a current or past community release note [here](https://github.com/basho-labs/the-riak-community/tree/master/release-notes).

### Seeding Data (For developers and testers)

Some suggestions on how to create some sample data, to try out the Explorer GUI.

1. Set up a couple of clusters in `riak_explorer.conf`. Have one or more with
    `development_mode = on`, and one or more with it set to `off` (meaning, in
    production mode).

2. Enable Search in Riak's config file (`riak.conf`). Set up a [Search
    Index](http://docs.basho.com/riak/latest/dev/using/search/#Simple-Setup).
    For example, to create a search index named `test-users-idx` that uses
    the default schema, do a PUT from the command-line (assuming your Riak
    node is available on `localhost`, using the default HTTP port `8098`):

    ```
    curl -XPUT http://localhost:8098/search/index/test-users-idx
    ```

3. Set up a `users` Bucket Type, and associate it with the `users-idx` Search
    index created above:

    ```
    riak-admin bucket-type create test-users '{"props":{"search_index":"test-users-idx"}}'
    riak-admin bucket-type activate test-users
    ```

4. Create and activate a Bucket Type for each main [Riak Data
    Type](http://docs.basho.com/riak/latest/dev/using/data-types/):

    ```
    riak-admin bucket-type create maps '{"props":{"datatype":"map"}}'
    riak-admin bucket-type activate maps
    riak-admin bucket-type create sets '{"props":{"datatype":"set"}}'
    riak-admin bucket-type activate sets
    riak-admin bucket-type create counters '{"props":{"datatype":"counter"}}'
    riak-admin bucket-type activate counters
    ```

5. Create and activate a `test-carts` Bucket Type, with [Siblings](http://docs.basho.com/riak/latest/dev/using/conflict-resolution/#Siblings)
    enabled:

    ```
    riak-admin bucket-type create test-carts '{"props":{"allow_mult":true}}'
    ```

6. Insert some sample Counter type objects, say to the `test-page-loads` bucket:

  ```
  curl localhost:8098/types/counters/buckets/test-page-loads/datatypes/page123 -XPOST \
    -H "Content-Type: application/json" \
    -d '{"increment": 5}'

  curl localhost:8098/types/counters/buckets/test-page-loads/datatypes/page456 -XPOST \
    -H "Content-Type: application/json" \
    -d '{"increment": 1}'
  ```

6. Insert some sample Set type objects, say to the `test-cities-visited` bucket:

  ```
  curl localhost:8098/types/sets/buckets/test-cities-visited/datatypes/user123 -XPOST \
    -H "Content-Type: application/json" \
    -d '{"add_all":["Toronto", "Montreal", "Quebec", "New York City"]}'

  curl localhost:8098/types/sets/buckets/test-cities-visited/datatypes/user456 -XPOST \
    -H "Content-Type: application/json" \
    -d '{"add_all":["Washington D.C.", "Los Angeles", "Las Vegas"]}'
  ```

6. Insert some sample Map type objects, say to the `test-tweets` bucket:

  ```
  curl localhost:8098/types/maps/buckets/test-tweets/datatypes/user123 -XPOST \
    -H "Content-Type: application/json" \
    -d '{"update":{ "favorited_flag": "disable", "id_str_register": "240859602684612608", "favourites_count_counter": 24, "entities_map":{ "update": { "urls_set":{ "add_all": ["url1", "url2", "url3"]}} }  }}'

  curl localhost:8098/types/maps/buckets/test-tweets/datatypes/user456 -XPOST \
    -H "Content-Type: application/json" \
    -d '{"update":{ "favorited_flag": "enable", "id_str_register": "240859602699912715", "favourites_count_counter": 1, "entities_map":{ "update": { "urls_set":{ "add_all": ["url4", "url5", "url6"]}} }  }}'
  ```

7. Insert some objects with sample Custom headers, and Secondary Index headers:

  ```
  curl localhost:8098/types/default/buckets/user-accounts/keys/user123 -XPUT \
    -H 'X-Riak-Meta-date-created: 2015-01-01' \
    -H 'X-Riak-Meta-last-accessed: 2015-09-01' \
    -H 'X-Riak-Index-email_bin: user@gmail.com' \
    -H 'X-Riak-Index-country_bin: usa' \
    -H 'Content-Type: application/json' \
    -d '{"name":"User One", "id":"user123"}'
  ```

### Related Projects
- [riak-explorer-gui](https://github.com/basho-labs/riak-explorer-gui) - the
    front-end Ember.js GUI code to go along with the Explorer API.
- [riak_control](https://github.com/basho/riak_control) - legacy official Riak
    GUI
- [riak_cs_control](https://github.com/basho/riak_cs_control) - legacy official
    Riak S2 (Riak CS) GUI
- [rekon](https://github.com/basho/rekon) (old bucket / object explorer gui) -
    legacy unofficial Javascript Riak GUI.
