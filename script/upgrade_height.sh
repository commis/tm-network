#!/bin/bash

set -e

# all global envirment parameter
OP_VERSION=0.23.1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
EXEC_BIN=${ROOT_DIR}/tools/${OP_VERSION}/tm_tools

NODE_LIST=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|sed 's/"//g')
OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function message_color() {
    echo -e "\033[40;31m[$1]\033[0m"
}

function do_upgrade_clean() {
    ps -ef |grep tm_tools |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function migrate_node() {
    tmData=${1}/tendermint
    oldPath=${OLD_DATA}/${tmData}
    newPath=${NEW_DATA}/${tmData}
    
    echo "${EXEC_BIN} migrate --old ${oldPath} --new ${newPath}"
    ${EXEC_BIN} migrate --old ${oldPath} --new ${newPath} --h 17
    
    rm -rf ${newPath}/data/evidence.db
    rm -rf ${newPath}/data/mempool.wal
    rm -rf ${newPath}/data/tx_index.db

    message_color "finished to migrate ${oldPath}"
}

function do_upgrade_height() {
    upgradeNodeFile=${OLD_DATA}/topNode.txt
    touch ${upgradeNodeFile}
    
    datadir=/tendermint/data
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}

        topNode=`cat ${upgradeNodeFile} |head -1|awk '{print $1}'`
        if [[ "${topNode}" == "" || "${topNode}" == "${name}" ]]; then
            message_color "need upgrade data for node ${name}"
            migrate_node ${name}
        else
            message_color "need copy data for node ${name}"
            rm -rf ${NEW_DATA}/${name}/${datadir}/*
            cp -R ${NEW_DATA}/${topNode}/${datadir}/* ${NEW_DATA}/${name}/${datadir}/
        fi
    done
    message_color "finished upgrade tendermint height"
}

# main function
function main() {
    do_upgrade_height
    do_upgrade_clean
}
main $# 2>&1 |grep -v 'duplicate proto'
