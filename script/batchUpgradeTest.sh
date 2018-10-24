#!/bin/bash

set -e

# all global envirment parameter
MAX_ROUND_TEST=$1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
SHELL_DIR=$(cd `dirname $(readlink -f "$0")` && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json

NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function kill_monitor() {
    ps -ef |grep 'docker logs' |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function monitor_block() {
    docker logs -f peer1 |grep 'Finalizing commit of block' &
    sleep 30
    kill_monitor
}

function start_chain() {
    peers=$(find ${NEW_DATA} -name "peer*")
    for p in ${peers}; do
        sh ${p}/start.sh
    done
}

function round_test() {
    kill_monitor
    ${SHELL_DIR}/network_setup.sh -t down

	${SHELL_DIR}/network_setup.sh -t up -v 0.18.0
    monitor_block
    ${SHELL_DIR}/network_setup.sh -t down

	${SHELL_DIR}/upgrade_all.sh
    start_chain
    monitor_block
}

# main function
function main() {
    if [ "${MAX_ROUND_TEST}" == "" ]; then MAX_ROUND_TEST=10; fi
   
    echo "need do test round ${MAX_ROUND_TEST}"

    declare -i i=1
    while ((i<=${MAX_ROUND_TEST}));do
        echo "execute test round ${i}"
        round_test
        let ++i
    done
}
main $#
