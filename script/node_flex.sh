#!/bin/bash

set -e

function printHelp () {
    echo "Usage: ./`basename $0` -t [del|start]"
}

# parse script args
while getopts ":t:" OPTION; do
    case ${OPTION} in
    t)
        OP_METHOD=$OPTARG
        ;;
    ?)
        printHelp
        exit 1
    esac
done


ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
EXEC_DIR=${ROOT_DIR}/tools/${OP_VERSION}

LOGIN_USR=$(cat ${ENV_FILE} |jq '.user.name'|sed 's/"//g')
LOGIN_PWD=$(cat ${ENV_FILE} |jq '.user.passwd'|sed 's/"//g')
CHAIN_DIR=$(cat ${ENV_FILE} |jq '.datapath'|sed 's/"//g')
ADD_NODES=$(cat ${ENV_FILE} |jq '.setup.node.add.host[]'|sed 's/"//g')
NODE_FROM=$(cat ${ENV_FILE} |jq '.setup.add.from.node'|sed 's/"//g')
DATA_FROM=$(cat ${ENV_FILE} |jq '.setup.add.from.data'|sed 's/"//g')

function sshConn() {
    sshpass -p ${LOGIN_PWD} ssh -o StrictHostKeychecking=no ${LOGIN_USR}@${1} "$2"
}

function copyNodeFiles() {
    echo "copy files: '$2'"
    sshpass -p ${LOGIN_PWD} scp -o StrictHostKeychecking=no -C -r "$2" ${LOGIN_USR}@${1}:${CHAIN_DIR}
}

function nodeServerStart() {
    data_c=$(docker ps |grep ${DATA_FROM} |awk '{print $1}')
    docker stop ${data_c}
   
    # support restore bad node, remove bad node contain
    node_src=${CHAIN_DIR}/${NODE_FROM}
    node_src_his=${node_src}_$(date "+%Y%m%d%H%M%S")
    if [ "${NODE_FROM}" != "" ]; then
        node_c=$(docker ps |grep ${NODE_FROM} |awk '{print $1}')
        echo "remove old docker contain: ${node_c}"
        docker rm -f ${node_c}
    fi

    data_src=${CHAIN_DIR}/${DATA_FROM}
    for node in ${ADD_NODES}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}
        home=${CHAIN_DIR}/${name}
        if [ ! -d "${home}" ]; then
            continue
        fi

        # support restore bad node
        if [ "${NODE_FROM}" != "" ]; then
            rm -rf ${home}/*
            cp -rf ${node_src}/* ${home}/
        fi

        if [ "${DATA_FROM}" != "" ]; then
            rm -rf ${home}/ethermint/chaindata/* 
            cp -rf ${data_src}/ethermint/chaindata/* ${home}/ethermint/chaindata/

            rm -rf ${home}/tendermint/data/*
            cp -rf ${data_src}/tendermint/data/* ${home}/tendermint/data/

            rm -rf ${home}/tendermint/data/*.wal
        fi

        # support restore bad node
        if [ "${NODE_FROM}" != "" ]; then
            mv ${node_src} ${node_src_his}
            mv ${home} ${node_src}
            home=${node_src}
        fi

        echo "start network at ${home} ..."
        sh ${home}/start.sh
    done
    docker start ${data_c}
}

function nodeServerDel() {
    for node in ${ADD_NODES}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}
        home=${CHAIN_DIR}/${name}

        docker ps -a |grep ${name} |awk '{print $1}' |xargs -ti docker rm -f {}
        if [ -d "${home}" ]; then
            rm -rf ${home}
        fi
    done
}

function validateArgs () {
    if [ -z "${OP_METHOD}" ]; then
        echo "Option start/del not mentioned"
        printHelp
        exit 1
    fi
}

function executeCommand() {
    case ${OP_METHOD} in
        "start")
            nodeServerStart
            ;;
        "del")
            nodeServerDel
            ;;
        ?)
            printHelp
            exit 1
    esac
}

validateArgs
executeCommand

