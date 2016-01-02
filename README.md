# docker-mariadb

This is a port of hauptmedia/docker-mariadb combined with the official mariadb docker image.
Since mariadb 10.1 includes Galera modules, they are no longer needed to install separately as hauptmedia/docker-mariadb.



## Available environment configuration

| Variable | Default value | Description |
| -------- | ------------- | ----------- |
| PORT | 3306 | Specify the MySQL Service Port |
| MAX_CONNECTIONS | 100 | Specified the maximum of parallel connections allowed to use the service |
| MYSQL_ROOT_PASSWORD | | If set, the root password will be set to this password (only if data-dir was non existent on startup) |
| MYSQL_DATABASE | | If set, this database will be created (only if data-dir was non existent on startup) |
| MYSQL_USER | | If set, this user will be created (only if data-dir was no existent on startup) |
| MYSQL_PASSWORD | | If set, this $MYSQL_USER will be created with this password |
| LOG_BIN | | Base filename for binary logs (will enable binary logs) |
| LOG_BIN_INDEX | | Location of the log-bin index file |
| MAX_ALLOWED_PACKET | 16M | The maximum size of one packet |
| QUERY_CACHE_SIZE | 16M | The amount of memory allocated for caching query results |
| INNODB_LOG_FILE_SIZE | 48M | Size in bytes of each log file in the log group |
| QUERY_CACHE_TYPE | 1 | Set the query cache type 0=OFF, 1=ON, 2=DEMAND |
| SYNC_BINLOG | 0 | Controls the number of binary log commit groups to collect before synchronizing the binary log to disk. When sync_binlog=0, the binary log is never synchronized to disk, and when sync_binlog is set to a value greater than 0 this number of binary log commit groups is periodically synchronized to disk. When sync_binlog=1, all transactions are synchronized to the binary log before they are committed |
| INNODB_BUFFER_POOL_SIZE | 128M | The size in bytes of the buffer pool, the memory area where InnoDB caches table and index data |
| INNODB_FLUSH_METHOD | | Defines the method used to flush data to the InnoDB data files and log files, which can affect I/O throughput |
| INNODB_OLD_BLOCKS_TIME | 1000 | Non-zero values protect against the buffer pool being filled up by data that is referenced only for a brief period, such as during a full table scan. Increasing this value offers more protection against full table scans interfering with data cached in the buffer pool. |
| INNODB_FLUSH_LOG_AT_TRX_COMMIT | 1 | Controls the balance between strict ACID compliance for commit operations, and higher performance that is possible when commit-related I/O operations are rearranged and done in batches. You can achieve better performance by changing the default value, but then you can lose up to a second of transactions in a crash. |

### Galera specific settings

| Variable | Default value | Description |
| -------- | ------------- | ----------- |
| GALERA | | If set the galera extension will be enabled |
| CLUSTER_NAME | | Unique Name that identified the Galera Cluster |
| NODE_NAME | | Unique Node name that identified this node instance |
| CLUSTER_ADDRESS | | gcomm:// style resource identifier that provides topology information about the Galera Cluster |
| REPLICATION_PASSWORD | | Password for the replication user which will be needed to allow state transfers using xtrabackupv2 method |

## Running MariaDB in Standalone Mode

```bash
docker run -i -t --rm \
-e TIMEZONE=Europe/Berlin \
-e MYSQL_ROOT_PASSWORD=securepassword \
lucidfrontier45/mariadb:10.1
```
## Running MariaDB in Galera Cluster Mode

For known limitations have a look at https://mariadb.com/kb/en/mariadb/mariadb-galera-cluster-known-limitations


### Initializing a new cluster

```bash
docker run -i -t --rm \
-e TIMEZONE=Europe/Berlin \
-e MYSQL_ROOT_PASSWORD=test \
-e REPLICATION_PASSWORD=test \
-e GALERA=On \
-e NODE_NAME=node1 \
-e CLUSTER_NAME=test \
-e CLUSTER_ADDRESS=gcomm:// \
lucidfrontier45/mariadb:10.1 --wsrep-new-cluster
```

### Joining a node to the cluster

```bash
docker run -i -t --rm \
-e TIMEZONE=Europe/Berlin \
-e MYSQL_ROOT_PASSWORD=test \
-e REPLICATION_PASSWORD=test \
-e GALERA=On \
-e NODE_NAME=node2 \
-e CLUSTER_NAME=test \
-e CLUSTER_ADDRESS=gcomm://ipOrHost1,ipOrHost2,ipOrHost3 \
lucidfrontier45/mariadb:10.1
```

Please note: if you don't specify the timezone the server will run with UTC time

## Recover strategies

To fix a split brain in a failed cluster make sure that only one node remains in the cluster and run

`SET GLOBAL wsrep_provider_options='pc.bootstrap=true';`

For more information about recovering a galera cluster have a look at https://www.percona.com/blog/2014/09/01/galera-replication-how-to-recover-a-pxc-cluster/
