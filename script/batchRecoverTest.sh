#!/bin/bash

set -e

# all global envirment parameter
DO_VERSION_TEST=$1
MAX_ROUND_TEST=$2
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
SHELL_DIR=$(cd `dirname $(readlink -f "$0")` && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
LOG_FILE=${ROOT_DIR}/logs/log.txt

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function kill_monitor() {
    docker ps -aq |xargs -ti docker rm -f {} > /dev/null 2>&1
    ps -ef |grep 'docker logs' |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function monitor_block() {
    docker logs -f peer1 |grep 'Finalizing commit of block' &
    sleep 30
    docker ps -aq |xargs -ti docker stop {} > /dev/null 2>&1
}

function create_new_chain() {
    kill_monitor

    if [ "${DO_VERSION_TEST}" == "old" ]; then
        ${SHELL_DIR}/network_setup.sh -t up -v 0.18.0
    else 
        ${SHELL_DIR}/network_setup.sh -t up -v 0.23.1
    fi

    monitor_block
}

function restart_chain() {
    kill_monitor
    if [ "${DO_VERSION_TEST}" == "old" ]; then
        peers=$(find ${OLD_DATA} -name "peer*")
    else 
        peers=$(find ${NEW_DATA} -name "peer*")
    fi
    for p in ${peers}; do
        sh ${p}/start.sh
    done
}

function round_test() {
    lastHeight=$(docker logs peer1 |grep 'Finalizing commit of block'|tail -1|awk -F'=' '{print $3}'|awk '{print $1}')
    recovHeight=1
    if [ $lastHeight -gt 6 ]; then
        recovHeight=$(expr $lastHeight - 5)
    fi

    echo "recov to height ${recovHeight}"
    ${SHELL_DIR}/recover_height.sh ${recovHeight} ${DO_VERSION_TEST}
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
   
    echo "need do test round ${MAX_ROUND_TEST}, version ${DO_VERSION_TEST}"
    
    create_new_chain
    declare -i i=1
    while ((i<=${MAX_ROUND_TEST}));do
        echo "execute test round ${i}"
        round_test
        let ++i
    done
    kill_monitor
}
main $#
