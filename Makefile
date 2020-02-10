.PHONY: help

help:
	@printf "Commands:\n"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

repmgr:			## run repmgr commands with the form of `make repmgr CMD=""`
	@NODES=$$(docker-compose ps -q); \
	for node in $${NODES}; do \
		name=$$(docker inspect $${node} | jq -crM '.[0] | .Id[0:12]'); \
		resp=$$(docker exec -iu postgres $${node} repmgr $(CMD) 2>&1); \
		if [[ "$$resp" != *"is not running"* ]]; then \
			echo "------> $${name} <-------" \
			&& echo "$$resp" \
			&& break; \
		fi; \
	done

status:			## display information about each registered node in the replication cluster
	@$(MAKE) repmgr CMD="cluster show"

daemon-status:		## display information about the status of repmgrd on each node in the cluster
	@$(MAKE) repmgr CMD="daemon status"

crosscheck:		## cross-checks connections between each combination of nodes
	@$(MAKE) repmgr CMD="cluster crosscheck"

cluster-cleanup:	## purge monitoring history
	@$(MAKE) repmgr CMD="cluster cleanup"

build:			## build postgresql node image
	@docker-compose build

up:			## create and start a single node (usually the first one)
	@docker-compose up -d

clean:			## stop and delete all the nodes and current deploy
	@docker-compose down -v -t 5 --remove-orphans
	@echo -n '' > cluster_members

logs:			## tail logs of all nodes
	@while true; do trap 'break' SIGINT; docker-compose logs -f; done

ssh:			## share ssh public keys between each node
	@./share-keys.sh

add-node:		## add another node to the cluster
	@n_nodes=$$(docker-compose ps \
		| grep -E "node_[0-9]+" \
		| sed -E 's/\s+/ /g' \
		| cut -f1 -d' ' \
		| sort -r \
		| head -n 1 \
		| sed -E 's/.*_//g'); \
	desired_nodes=$$(($${n_nodes} + 1)); \
	docker-compose up -d --scale pg-node=$${desired_nodes}

del-node:		## delete one node from the cluster
	@n_nodes=$$(docker-compose ps \
		| grep -E "node_[0-9]+" \
		| sed -E 's/\s+/ /g' \
		| cut -f1 -d' ' \
		| sort -r \
		| head -n 1 \
		| sed -E 's/.*_//g'); \
	desired_nodes=$$(($${n_nodes} - 1)); \
	docker-compose up -d --scale pg-node=$${desired_nodes}; \
	docker-compose exec -u postgres pg-node \
			repmgr standby unregister --node-id=$${n_nodes}

%:
	@:
