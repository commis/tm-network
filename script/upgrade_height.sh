#!/bin/bash

set -e

# all global envirment parameter
OP_VERSION=0.23.1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
GNS_FILE=${ROOT_DIR}/config/genesis.json
EXEC_DIR=${ROOT_DIR}/tools/${OP_VERSION}
EXEC_BIN=${ROOT_DIR}/tools/${OP_VERSION}/tm_tools

DOCKER_OS=$(cat ${ENV_FILE} |jq '.system'|sed 's/"//g')
LOCALHOST=$(cat ${ENV_FILE} |jq '.localhost'|sed 's/"//g')
NODE_LIST=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|sed 's/"//g')
IP_NUMBER=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|cut -d= -f2|cut -d, -f1|sort|uniq|wc -l)

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')
PUB_KEYS=${NEW_DATA}/pub_keys
VER_PORT=$(cat ${ENV_FILE}    |jq '.setup.port' |jq -c "map(select([.version == "\"${OP_VERSION}\""] | all))[]")
INIT_PORTS=$(echo ${VER_PORT} |jq '.ports'|sed 's/"//g')
HAVE_TMP2P=$(echo ${VER_PORT} |jq '.p2ptm'|sed 's/"//g')
DEBUG_PORT=$(echo ${VER_PORT} |jq '.debug'|sed 's/"//g')

function migrate_node() {
    tmData=${1}/tendermint
    oldPath=${OLD_DATA}/${tmData}
    newPath=${NEW_DATA}/${tmData}
    
    echo "${EXEC_BIN} migrate --old ${oldPath} --new ${newPath}"
    ${EXEC_BIN} migrate --old ${oldPath} --new ${newPath} --h 17
    
    rm -rf ${newPath}/data/evidence.db
    rm -rf ${newPath}/data/mempool.wal
    rm -rf ${newPath}/data/tx_index.db
   
    echo "finished to migrate ${oldPath}"
}

function do_upgrade() {
    index=0
    master_address=""
    master_hostip=""
    master_chainid=""
    upgradeNodeFile=${OLD_DATA}/topNode.txt
    touch ${upgradeNodeFile}
    datadir=/tendermint/data
   
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}

        topNode=`cat ${upgradeNodeFile} |head -1|awk '{print $1}'`
        if [[ "${topNode}" == "" || "${topNode}" == "${name}" ]]; then
            migrate_node ${name}
        else
            rm -rf ${NEW_DATA}/${name}/${datadir}/*
            cp -R ${NEW_DATA}/${topNode}/${datadir}/* ${NEW_DATA}/${name}/${datadir}/
        fi
    done
}

# main function
function main() {
    do_upgrade
}
main $# 2>&1 |grep -v 'duplicate proto'
