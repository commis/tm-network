#!/bin/bash

set -e

# all global envirment parameter
DO_VERSION_TEST=$1
MAX_ROUND_TEST=$2
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
SHEL_DIR=${ROOT_DIR}/script
ENV_FILE=${ROOT_DIR}/config/env.json

LAST_HEIGHT=1
OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function message_color() {
    echo -e "\033[40;31m[$1]\033[0m"
}

function kill_monitor() {
    docker ps -aq |xargs -ti docker rm -f {} > /dev/null 2>&1
    ps -ef |grep 'docker logs' |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function get_current_block_height() {
    logline=$(docker logs peer1 |grep 'Finalizing commit of block'|tail -1)
    if [ "${logline}" == "" ]; then
        echo "last round not new block"
        exit 1
    fi
    echo ${logline}
    LAST_HEIGHT=$(echo "'"${logline}"'" |awk -F'=' '{print $3}'|awk '{print $1}')
    message_color "after run 30 second, the current height is ${LAST_HEIGHT}"
    kill_monitor
}

function monitor_block() {
    sleep 30 
    docker ps -aq |xargs -ti docker stop {} > /dev/null 2>&1
}

function create_new_chain() {
    kill_monitor
    if [ "${DO_VERSION_TEST}" == "old" ]; then
        echo "${SHEL_DIR}/network_setup.sh -t up -v 0.18.0"
        ${SHEL_DIR}/network_setup.sh -t up -v 0.18.0
    else 
        echo "${SHEL_DIR}/network_setup.sh -t up -v 0.23.1"
        ${SHEL_DIR}/network_setup.sh -t up -v 0.23.1
    fi
    monitor_block
}

function check_socket_port() {
    while [ "$(netstat -na |grep '46656')" != "" ]; do
        sleep 1
    done
}

function restart_chain() {
    if [ "${DO_VERSION_TEST}" == "old" ]; then
        peers=$(find ${OLD_DATA} -name "peer*")
    else 
        peers=$(find ${NEW_DATA} -name "peer*")
    fi
    
    check_socket_port
    for p in ${peers}; do
        sh ${p}/start.sh
    done
}

function round_test() {
    get_current_block_height

    # do nothing
    restart_chain
    monitor_block
}

function validateArgs () {
    if [[ $1 != 1 && $1 != 2 ]]; then
        echo "Usage: ./`basename $0` [old|new] [round]"
        exit 1
    fi
}

# main function
function main() {
    validateArgs $1
    if [ "${DO_VERSION_TEST}" != "old" ]; then DO_VERSION_TEST='new'; fi
    if [ "${MAX_ROUND_TEST}" == "" ]; then MAX_ROUND_TEST=10; fi

    message_color "You want test round ${MAX_ROUND_TEST}, version ${DO_VERSION_TEST}"
    
    create_new_chain
    declare -i i=1
    while ((i<=${MAX_ROUND_TEST})); do
        message_color "execute test round ${i}"
        round_test
        let ++i
    done
    get_current_block_height
}
main $# 2>&1 |grep -v 'duplicate proto'
