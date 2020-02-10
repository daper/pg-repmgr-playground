#!/bin/bash

CONTAINERS=$(docker-compose ps -q)
PGHOME=$(docker exec -it $(echo "$CONTAINERS" | head -n1) su postgres -c 'echo -n $HOME')

get_master_node () {
  cat cluster_members | grep '^*' | sed -E 's/^\* //'
}

get_node_id () {
  grep -ne "${1:0:12}" cluster_members | cut -f1 -d:
}

until docker exec -iu postgres $(get_master_node) sh -c "[ -f /etc/postgresql/10/main/bootstraped ]"; do
  echo "Waiting for master to bootstrap"
  sleep 1
done

for container in $CONTAINERS; do
  docker exec -it $container rm -f $PGHOME/.ssh/authorized_keys
done

for container_from in $CONTAINERS; do
  service_from=$(docker inspect $container_from | jq -crM '.[0].Config.Labels["com.docker.compose.service"]')
  pub_key=$(docker exec -it ${container_from} cat $PGHOME/.ssh/id_rsa.pub)

  for container_to in $CONTAINERS; do
    if [ "$container_from" != "$container_to" ]; then
      echo "$(get_node_id $container_from) -> $(get_node_id $container_to)"

      docker exec -it -u postgres $container_to sh -c "echo '$pub_key' >> $PGHOME/.ssh/authorized_keys"
    fi
  done

  echo "$pub_key"
done

