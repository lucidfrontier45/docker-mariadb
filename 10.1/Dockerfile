FROM		mariadb:10.1
MAINTAINER	Shiqiao Du <lucidfrontier.45@gmail.com>

# add configuration
COPY		conf.d/utf8.cnf /etc/mysql/conf.d/utf8.cnf
COPY		conf.d/galera.cnf /etc/mysql/conf.d/galera.cnf

# 3306 - MySQL client connections
# 4567 - Galera Cluster replication traffic, multicast replication uses both udp & tcp
# 4568 - For Incremental State Transfers
# 4444 - For all other State Snapshot Transfers

EXPOSE		3306 4444 4567 4568

VOLUME		["/var/lib/mysql"]
COPY		docker-entrypoint.sh /entrypoint.sh

# Set TERM env to avoid mysql client error message "TERM environment variable not set" when running from inside the container
ENV TERM xterm

# default values for configuration options
ENV	MAX_CONNECTIONS=100 \
	PORT=3306 \
	MAX_ALLOWED_PACKET=16M \
	QUERY_CACHE_SIZE=16M \
	QUERY_CACHE_TYPE=1 \
	INNODB_BUFFER_POOL_SIZE=128M \
	INNODB_LOG_FILE_SIZE=48M \
	INNODB_FLUSH_METHOD= \
	INNODB_OLD_BLOCKS_TIME=1000 \
	INNODB_FLUSH_LOG_AT_TRX_COMMIT=1 \
	SYNC_BINLOG=0

ENTRYPOINT	["/entrypoint.sh"]

CMD ["mysqld"]
