#!/bin/bash

MAX_TEST_NUMBER=30

function kill_monitor() {
    ps -ef |grep 'docker logs' |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
}

function monitor_block() {
    docker logs -f peer1 |grep 'Finalizing commit of block' &
    sleep 30
    kill_monitor
}

function round_test() {
    kill_monitor
    make down

    make upold
    monitor_block
    make down

    make upgrade

    # ./start.sh
    # monitor_block
}

function main() {
    # declare -i i=1
    # while ((i<=${MAX_TEST_NUMBER}));do
        # echo "execute test round ${i}"
        round_test
        # let ++i
    # done
}
main
