#!/bin/bash
set -eo pipefail

IP=$(hostname --ip-address | cut -d" " -f1)

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

# skip setup if they want an option that stops mysqld
wantHelp=
for arg; do
	case "$arg" in
		-'?'|--help|--print-defaults|-V|--version)
			wantHelp=1
			break
			;;
	esac
done

_datadir() {
	"$@" --verbose --help --log-bin-index=`mktemp -u` 2>/dev/null | awk '$1 == "datadir" { print $2; exit }'
}

# allow the container to be started with `--user`
if [ "$1" = 'mysqld' -a -z "$wantHelp" -a "$(id -u)" = '0' ]; then
	DATADIR="$(_datadir "$@")"
	mkdir -p "$DATADIR"
	chown -R mysql:mysql "$DATADIR"
	chown -R mysql:mysql /etc/mysql/
	exec gosu mysql "$BASH_SOURCE" "$@"
fi

# set timezone if it was specified
if [ -n "$TIMEZONE" ]; then
	echo ${TIMEZONE} > /etc/timezone && \
	dpkg-reconfigure -f noninteractive tzdata
fi

# apply environment configuration
sed -i -e "s/^port.*=.*/port=${PORT}/" /etc/mysql/my.cnf
sed -i -e "s/^#max_connections.*=.*/max_connections=${MAX_CONNECTIONS}/" /etc/mysql/my.cnf
sed -i -e "s/^max_allowed_packet.*=.*/max_allowed_packet=${MAX_ALLOWED_PACKET}/" /etc/mysql/my.cnf
sed -i -e "s/^query_cache_size.*=.*/query_cache_size=${QUERY_CACHE_SIZE}/" /etc/mysql/my.cnf
sed -i -e "s/^\[mysqld\]/\[mysqld\]\ninnodb_log_file_size=${INNODB_LOG_FILE_SIZE}/" /etc/mysql/my.cnf
sed -i -e "s/^\[mysqld\]/\[mysqld\]\nquery_cache_type=${QUERY_CACHE_TYPE}/" /etc/mysql/my.cnf
sed -i -e "s/^\[mysqld\]/\[mysqld\]\nsync_binlog=${SYNC_BINLOG}/" /etc/mysql/my.cnf
sed -i -e "s/^\[mysqld\]/\[mysqld\]\ninnodb_buffer_pool_size=${INNODB_BUFFER_POOL_SIZE}/" /etc/mysql/my.cnf
sed -i -e "s/^\[mysqld\]/\[mysqld\]\ninnodb_old_blocks_time=${INNODB_OLD_BLOCKS_TIME}/" /etc/mysql/my.cnf
sed -i -e "s/^\[mysqld\]/\[mysqld\]\ninnodb_flush_log_at_trx_commit=${INNODB_FLUSH_LOG_AT_TRX_COMMIT}/" /etc/mysql/my.cnf

if [ -n "$INNODB_FLUSH_METHOD" ]; then
	sed -i -e "s/^\[mysqld\]/\[mysqld\]\ninnodb_flush_method=${INNODB_FLUSH_METHOD}/" /etc/mysql/my.cnf
fi


if [ "$1" = 'mysqld' -a -z "$wantHelp" ]; then

	if [ -n "$GALERA" ]; then
		if [ -z "$CLUSTER_NAME" ]; then
			echo >&2 'error:  missing CLUSTER_NAME'
			echo >&2 '  Did you forget to add -e CLUSTER_NAME=... ?'
			exit 1
		fi

		if [ -z "$NODE_NAME" ]; then
			echo >&2 'error:  missing NODE_NAME'
			echo >&2 '  Did you forget to add -e NODE_NAME=... ?'
			exit 1
		fi

		if [ -z "$CLUSTER_ADDRESS" ]; then
			echo >&2 'error:  missing CLUSTER_ADDRESS'
			echo >&2 '  Did you forget to add -e CLUSTER_ADDRESS=... ?'
			exit 1
		fi
	else
		rm /etc/mysql/conf.d/galera.cnf
	fi

	# Get config
	DATADIR="$(_datadir "$@")"

	if [ ! -d "$DATADIR/mysql" ]; then
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			echo >&2 'error: database is uninitialized and password option is not specified '
			echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
			exit 1
		fi

		if [ -n "$GALERA" -a -z "$REPLICATION_PASSWORD" ]; then
			echo >&2 'error:  missing REPLICATION_PASSWORD'
			echo >&2 '  Did you forget to add -e REPLICATION_PASSWORD=... ?'
			exit 1
		fi

		mkdir -p "$DATADIR"

		echo 'Initializing database'
		mysql_install_db --datadir="$DATADIR" --rpm
		echo 'Database initialized'

		"$@" --skip-networking &
		pid="$!"

		mysql=( mysql --protocol=socket -uroot )

		for i in {30..0}; do
			if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
				break
			fi
			echo 'MySQL init process in progress...'
			sleep 1
		done
		if [ "$i" = 0 ]; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
			# sed is for https://bugs.mysql.com/bug.php?id=20545
			mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
		fi

		if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			MYSQL_ROOT_PASSWORD="$(pwgen -1 32)"
			echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
		fi
		"${mysql[@]}" <<-EOSQL
			-- What's done in this file shouldn't be replicated
			--  or products like mysql-fabric won't work
			SET @@SESSION.SQL_LOG_BIN=0;
			DELETE FROM mysql.user ;
			CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL

		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
		fi

		if [ "$MYSQL_DATABASE" ]; then
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"

			if [ "$MYSQL_DATABASE" ]; then
				echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
			fi

			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		fi

		if [ -n "$GALERA" ]; then
			"${mysql[@]}" <<-EOSQL
			CREATE USER 'replication'@'%' IDENTIFIED BY '${REPLICATION_PASSWORD}';
			GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'replication'@'%';
			FLUSH PRIVILEGES ;
			EOSQL
		fi

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		if ! kill -s TERM "$pid" || ! wait "$pid"; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		echo
		echo 'MySQL init process done. Ready for start up.'
		echo
	fi

	if [ -n "$GALERA" ]; then
		# append galera specific run options

		set -- "$@" \
		--wsrep_cluster_name="$CLUSTER_NAME" \
		--wsrep_cluster_address="$CLUSTER_ADDRESS" \
		--wsrep_node_name="$NODE_NAME" \
		--wsrep_sst_auth="replication:$REPLICATION_PASSWORD" \
		--wsrep_sst_receive_address=$IP
	fi

	if [ -n "$LOG_BIN" ]; then
                set -- "$@" --log-bin="$LOG_BIN"
		chown mysql:mysql $(dirname $LOG_BIN)
	fi

    if [ -n "$LOG_BIN_INDEX" ]; then
            set -- "$@" --log-bin-index="$LOG_BIN_INDEX"
	chown mysql:mysql $(dirname $LOG_BIN)
    fi
fi

exec "$@"
