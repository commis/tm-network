#!/bin/bash

# set -ex

function printHelp () {
    echo "Usage: ./`basename $0` [-t up|down]"
}

function validateArgs () {
    if [ -z "${UP_DOWN}" ]; then
        echo "Option up/down not mentioned"
        printHelp
        exit 1
    fi
}

function monitorUp() {
    target="/home/OpenSource/energy.com/JavaMonitor/target/greenTokenSCService-1.2.0.jar"
    if [ -f "${target}" ]; then
        cp -f ${target} ./lib/
    fi
    docker build -t "ethermint/monitor:x86_64-1.2.0" .
    docker run --net=bridge --name=monitor -p 8080:8080 -itd ethermint/monitor:x86_64-1.2.0 /bin/bash
}

function monitorDown() {
    docker ps -a |grep monitor |awk '{print $1}' |xargs -ti docker rm -f {}
    docker images -a |grep monitor |awk '{print $3}' |xargs -ti docker rmi -f {}
}

function execute() {
    case ${UP_DOWN} in
        "up")
            monitorUp
            ;;
        "down")
            monitorDown
            ;;
        ?)
            printHelp
            exit 1
    esac
}

# parse script args
while getopts "t:c" OPTION; do
    case ${OPTION} in
        t)
            UP_DOWN=$OPTARG
            ;;
        ?)
            printHelp
            exit 1
    esac
done

validateArgs
execute
