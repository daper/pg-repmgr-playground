#!/bin/bash

PGHOME=$(su postgres -c 'echo $HOME')
PGCONFDIR=/etc/postgresql/10/main
CLUSTERCONF=${CLUSTERCONF:-/var/run/cluster_members}

get_cluster_nodes () {
	cat $CLUSTERCONF | sed -E 's/^\* //'
}

count_cluster_nodes () {
	get_cluster_nodes | wc -l
}

get_master_node () {
	cat $CLUSTERCONF | grep '^*' | sed -E 's/^\* //'
}

is_master_node () {
	[ "$(get_master_node)" == "$HOSTNAME" ]
}

get_node_id () {
	grep -ne "$HOSTNAME" $CLUSTERCONF | cut -f1 -d:
}

cluster_exit () {
	echo "---> EXIT <---"
	echo "$(grep -ve "$HOSTNAME" $CLUSTERCONF)" \
		> $CLUSTERCONF
	exit
}
export -f cluster_exit
trap cluster_exit SIGSTOP SIGTERM

if [ $(count_cluster_nodes) -eq 0 ]; then
	echo "---> NEW MASTER <---"
	echo "* $HOSTNAME" >> $CLUSTERCONF
elif ! grep -qe "$HOSTNAME" $CLUSTERCONF; then
	echo "---> NEW NODE <---"
	echo "$HOSTNAME" >> $CLUSTERCONF
else
	echo "---> KNOWN NODE <---"
fi


if [ ! -d "$PGHOME/.ssh" ]; then
	mkdir $PGHOME/.ssh
	ssh-keygen -t rsa -b 2048 -N '' -f $PGHOME/.ssh/id_rsa
	echo "StrictHostKeyChecking no" > $PGHOME/.ssh/config
	chown postgres:postgres -R $PGHOME/.ssh
fi

# Start the first process
service ssh start
status=$?
if [ $status -ne 0 ]; then
	echo "Failed to start sshd: $status"
	exit $status
else
	ssh-keyscan $(get_cluster_nodes) \
		> $PGHOME/.ssh/known_hosts
	chown postgres:postgres $PGHOME/.ssh/known_hosts

	if ! is_master_node; then
		until su postgres -c "ssh $(get_master_node) exit"; do
			echo "[ssh] Waiting to connect to master..."
			echo "[ssh] Maybe you didn't copy the public keys."
			sleep 1
		done
	fi
fi

if [ ! -f $PGCONFDIR/bootstraped ]; then
	pg_createcluster --datadir=$PGDATA 10 main

	sed -Ei "s/#?listen_addresses.*/listen_addresses = '\*'/" $PGCONFDIR/postgresql.conf
	sed -Ei "s/#?shared_preload_libraries.*/shared_preload_libraries = 'repmgr'/" $PGCONFDIR/postgresql.conf
	echo "include '$PGCONFDIR/postgresql.replication.conf'" >> $PGCONFDIR/postgresql.conf

	cat <<-EOF > $PGCONFDIR/postgresql.replication.conf
		max_wal_senders = 15
		max_replication_slots = 15
		wal_level = 'replica'
		hot_standby = on
		archive_mode = on
		archive_command = '/bin/true'
		wal_keep_segments = 500
		wal_log_hints = on
		EOF

	cat <<-EOF >> $PGCONFDIR/pg_hba.conf
		local   replication   repmgr                              trust
		host    replication   repmgr      127.0.0.1/32            trust
		host    replication   repmgr      $PRIVNET                trust

		local   repmgr        repmgr                              trust
		host    repmgr        repmgr      127.0.0.1/32            trust
		host    repmgr        repmgr      $PRIVNET                trust
		EOF

	cat <<-EOF > /etc/repmgr.conf
		node_id=$(get_node_id)
		node_name='$HOSTNAME'
		conninfo='host=$HOSTNAME port=5432 user=repmgr dbname=repmgr connect_timeout=2'
		data_directory='$PGDATA'

		use_replication_slots=yes
		monitoring_history=yes

		service_start_command   = 'sudo /usr/bin/pg_ctlcluster 10 main start'
		service_stop_command    = 'sudo /usr/bin/pg_ctlcluster 10 main stop'
		service_restart_command = 'sudo /usr/bin/pg_ctlcluster 10 main restart'
		service_reload_command  = 'sudo /usr/bin/pg_ctlcluster 10 main reload'
		service_promote_command = 'sudo /usr/bin/pg_ctlcluster 10 main promote'

		promote_check_timeout = 15

		failover=automatic
		promote_command='/usr/bin/repmgr standby promote -f /etc/repmgr.conf --log-to-file'
		follow_command='/usr/bin/repmgr standby follow -f /etc/repmgr.conf --log-to-file --upstream-node-id=%n'

		log_file='/var/log/postgresql/repmgrd.log'

		repmgrd_service_start_command = 'sudo /etc/init.d/repmgrd start'
		repmgrd_service_stop_command = 'sudo /etc/init.d/repmgrd stop'
		EOF

	cat <<-EOF > /etc/default/repmgrd
		REPMGRD_ENABLED=yes
		REPMGRD_CONF="/etc/repmgr.conf"
		REPMGRD_OPTS="--daemonize=false"
		REPMGRD_USER=postgres
		REPMGRD_BIN=/usr/bin/repmgrd
		REPMGRD_PIDFILE=/var/run/repmgrd.pid
		EOF

	if is_master_node; then
		service postgresql start
		until su postgres -c 'psql -tc "select current_timestamp;"'; do
			echo "[psql] Waiting to connect to postgres..."
			sleep 1
		done

		su postgres -c 'createuser -s repmgr'
		su postgres -c 'createdb repmgr -O repmgr'

		su postgres -c 'repmgr -f /etc/repmgr.conf primary register'

		service postgresql stop
	else
		until psql -h $(get_master_node) -U repmgr -tc "select current_timestamp;"; do
			echo "[psql] Waiting to connect to master..."
			sleep 2
		done

		rm -rf $PGDATA/*
		su postgres -c "repmgr -h $(get_master_node) -U repmgr -d repmgr -f /etc/repmgr.conf standby clone"

		service postgresql start

		su postgres -c 'repmgr standby register --force'

		service postgresql stop
	fi
fi

service postgresql start
status=$?
if [ $status -ne 0 ]; then
	echo "Failed to start postgresql: $status"
	exit $status
else
	until su postgres -c 'psql -tc "select current_timestamp;"'; do
		echo "[psql] Waiting to connect to postgres..."
		sleep 1
	done

	su postgres -c 'repmgr daemon start'
fi

if [ ! -f $PGCONFDIR/bootstraped ]; then
	echo "---> BOOTSTRAPED <---"
	touch $PGCONFDIR/bootstraped
else
	echo "---> START <---"
fi

while /bin/true; do
	ps aux | grep -q [s]shd
	PROCESS_1_STATUS=$?
	ps aux | grep -q [p]ostgresql
	PROCESS_2_STATUS=$?
	ps aux | grep -q [r]epmgrd
	PROCESS_3_STATUS=$?

	if [ $PROCESS_1_STATUS -ne 0 -a $PROCESS_2_STATUS -ne 0 -a $PROCESS_3_STATUS -ne 0 ]; then
		echo "No main processes running"
		exit -1
	fi
	sleep 1
done