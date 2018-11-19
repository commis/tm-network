#!/bin/bash

set -e

# all global envirment parameter
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function get_docker_ip() {
    ip=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $1)
    echo $ip
}

function get_node_address() {
    chain_root=""
    if [ "${OLD_DATA}" != "" ]; then chain_root=${OLD_DATA}; else chain_root=${NEW_DATA}; fi
    nodeFile=${chain_root}/$1/tendermint/config/priv_validator.json
    address=$(sudo jq '.address' $nodeFile |sed 's/"//g' |tr 'A-Z' 'a-z')
    echo $address
}

## function main
function main() {
    contains=$(docker ps --format '{{.Names}}' |sort)
    for i in ${contains}; do
        ipAddress=$(get_docker_ip $i)
        nodeAddress=$(get_node_address $i)
        echo "$i $ipAddress $nodeAddress"
    done
}
main
