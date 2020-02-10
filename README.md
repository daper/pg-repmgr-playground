# Postgresql repmgr playground

This is a docker-compose based repository to test and play with the replication manager of postgresql. It consists in a `pg-node` service defined inside the `docker-compose.yml` file. Using the image generated from `postgres.Dockerfile`, which includes the file `entrypoint.sh` as its entrypoint. And where it is defined the main bootstrap configuration.

A local file named `cluster_members` is used to let the containers know their names eachother and bootstrap the replication cluster. The first container that brings up will take the role of replication master and the rest replicas.

There is a `Makefile` with the main tasks used in this playground; like: `up`, `add-node`, `del-node`, `status` and `clean`. There is another make target named `ssh` that will run the script `share-keys.sh` which will exchange all the public keys between all the different nodes. And a `help` target to show a small description of all the targets available.

### Commands

Use `make help` to see this message.

```
repmgr:                  run repmgr commands with the form of `make repmgr CMD=""`
status:                  display information about each registered node in the replication cluster
daemon-status:           display information about the status of repmgrd on each node in the cluster
crosscheck:              cross-checks connections between each combination of nodes
cluster-cleanup:         purge monitoring history
build:                   build postgresql node image
up:                      create and start a single node (usually the first one)
clean:                   stop and delete all the nodes and current deploy
logs:                    tail logs of all nodes
ssh:                     share ssh public keys between each node
add-node:                add another node to the cluster
del-node:                delete one node from the cluster
```