#!/bin/bash

set -e

ROOT_FOLDER=$(cd `dirname $(readlink -f "$0")`/..; pwd)
EXEC_FOLDER=$(eth=$(which ethermint); echo ${eth%/*}; unset eth)
ENV_FILE=${ROOT_FOLDER}/script/.env

REMOTE_USER=$(cat ${ENV_FILE} |grep User |awk -F'=' '{print $2}')
REMOTE_PASSWD=$(cat ${ENV_FILE} |grep Passwd |awk -F'=' '{print $2}')
CHAIN_DATA=$(cat ${ENV_FILE} |grep DataDir |awk -F'=' '{print $2}')
HOSTS_LIST=$(cat ${ENV_FILE} |grep 'add:peer' |cut -d: -f2)
NODE_FROM=$(cat ${ENV_FILE} |grep '^add:from_node' |cut -d= -f2)
DATA_FROM=$(cat ${ENV_FILE} |grep '^add:from_data' |cut -d= -f2)

function printHelp () {
    echo "Usage: ./`basename $0` [-t start|del]"
}

function sshConn() {
    sshpass -p ${REMOTE_PASSWD} ssh -o StrictHostKeychecking=no ${REMOTE_USER}@${1} "$2"
}

function copyNodeFiles() {
    echo "copy files: '$2'"
    sshpass -p ${REMOTE_PASSWD} scp -o StrictHostKeychecking=no -C -r "$2" ${REMOTE_USER}@${1}:${CHAIN_DATA}
}

function validateArgs () {
    if [ -z "${UP_DOWN}" ]; then
        echo "Option start/del not mentioned"
        printHelp
        exit 1
    fi
}

function nodeServerStart() {
    data_c=$(docker ps |grep ${DATA_FROM} |awk '{print $1}')
    docker stop ${data_c}
   
    # support restore bad node, remove bad node contain
    node_src=${CHAIN_DATA}/${NODE_FROM}
    node_src_his=${node_src}_$(date "+%Y%m%d%H%M%S")
    if [ "${NODE_FROM}" != "" ]; then
        node_c=$(docker ps |grep ${NODE_FROM} |awk '{print $1}')
        echo "remove old docker contain: ${node_c}"
        docker rm -f ${node_c}
    fi

    data_src=${CHAIN_DATA}/${DATA_FROM}
    for node in ${HOSTS_LIST}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}
        home=${CHAIN_DATA}/${name}
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
    for node in ${HOSTS_LIST}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}
        home=${CHAIN_DATA}/${name}

        docker ps -a |grep ${name} |awk '{print $1}' |xargs -ti docker rm -f {}
        if [ -d "${home}" ]; then
            rm -rf ${home}
        fi
    done
}

function execute() {
    case ${UP_DOWN} in
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

# parse script args
while getopts ":t:" OPTION; do
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
