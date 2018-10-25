#!/bin/bash

set -e

# all global envirment parameter
RECOV_HEIGHT=$1
SHOW_VERSION=$2
OP_VERSION=0.23.1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
EXEC_BIN=${ROOT_DIR}/tools/${OP_VERSION}/tm_tools

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function message_color() {
    echo -e "\033[40;31m[$1]\033[0m"
}

function do_recover_clean() {
    ps -ef |grep tm_tools |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function do_recover_height() {
    datadir=$1/tendermint
    height=$2
    version=$3
    
    params=""
    if [ "${version}" == "new" ]; then params='--v'; fi

    echo "${EXEC_BIN} recover --db ${datadir} --h ${height} ${params}"
    ${EXEC_BIN} recover --db ${datadir} --h ${height} ${params}
    
    rm -rf ${datadir}/data/evidence.db
    rm -rf ${datadir}/data/mempool.wal
    rm -rf ${datadir}/data/tx_index.db
  
    message_color "finished to recover ${datadir}"
}

function validateArgs () {
    if [ $1 != 2 ]; then
        echo "Usage: ./`basename $0` [height] [old|new]"
        exit 1
    fi
}

# main function
function main() {
    validateArgs $1
    if [ "${SHOW_VERSION}" == "new" ]; then
        if [ -d "${NEW_DATA}" ]; then existNodes=$(find ${NEW_DATA} -name "peer*"|sort); fi
    else
        SHOW_VERSION='old'
        if [ -d "${OLD_DATA}" ]; then existNodes=$(find ${OLD_DATA} -name "peer*"|sort); fi
    fi

    for node in ${existNodes}; do
        message_color "recover tendermint height for ${node}"
        do_recover_height ${node} ${RECOV_HEIGHT} ${SHOW_VERSION}
    done
    do_recover_clean
}

main $# 2>&1 |grep -v 'duplicate proto'
