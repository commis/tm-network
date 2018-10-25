#!/bin/bash

set -e

# all global envirment parameter
MAX_ROUND_TEST=$1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
SHELL_DIR=$(cd `dirname $(readlink -f "$0")` && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json

NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function message_color() {
    echo -e "\033[40;31m[$1]\033[0m"
}

function do_upgrade_clean() {
    ps -ef |grep tm_tools |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function kill_monitor() {
    docker ps -aq |xargs -ti docker rm -f {} > /dev/null 2>&1
    ps -ef |grep 'docker logs' |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function check_height() {
    logline=$(docker logs peer1 |grep 'Finalizing commit of block'|tail -1)
    if [ "${logline}" == "" ]; then
        echo "last round not new block"
        exit 1
    fi
    echo ${logline}
    lastHeight=$(echo "'"${logline}"'" |awk -F'=' '{print $3}'|awk '{print $1}')
    message_color "after run 30 second, the current height is ${lastHeight}"
}

function monitor_block() {
    sleep 30
    docker ps -aq |xargs -ti docker stop {} > /dev/null 2>&1
    check_height
    kill_monitor
}

function check_socket_port() {
    while [ "$(netstat -na |grep '46656')" != "" ]; do
        sleep 1
    done
}

function start_chain() {
    check_socket_port
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

    message_color "You want to test round ${MAX_ROUND_TEST}"

    declare -i i=1
    while ((i<=${MAX_ROUND_TEST}));do
        message_color "execute test round ${i}"
        round_test
        let ++i
    done
    do_upgrade_clean
}
main $# 2>&1 |grep -v 'duplicate proto'
