#!/bin/bash

set -e

ROOT_FOLDER=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
CFG_FILE=${ROOT_FOLDER}/config/genesis.json
ENV_FILE=${ROOT_FOLDER}/script/.env
BIN_DIR=${ROOT_FOLDER}/tools/0.23.1

REMOTE_USER=$(cat ${ENV_FILE} |grep User |awk -F'=' '{print $2}')
REMOTE_PASSWD=$(cat ${ENV_FILE} |grep Passwd |awk -F'=' '{print $2}')
OP_SYSTEM=$(cat ${ENV_FILE}   |grep SYS_ubuntu |awk -F'=' '{print $2}')
CHAIN_DATA=$(cat ${ENV_FILE}  |grep DataDir |awk -F'=' '{print $2}')
LOCALHOST_IP=$(cat ${ENV_FILE}|grep Localhost |awk -F'=' '{print $2}')
NODE_LIST=$(cat ${ENV_FILE}   |grep '^init:peer' |cut -d: -f2)
HOST_NUMBER=$(cat ${ENV_FILE} |grep '^init:peer' |cut -d= -f2|cut -d, -f1|sort|uniq|wc -l)
ADD_NODES=$(cat ${ENV_FILE}   |grep '^add:peer' |cut -d: -f2)
NODE_FROM=$(cat ${ENV_FILE}   |grep '^add:from_node' |cut -d= -f2)

PUB_KEYS=${CHAIN_DATA}/pub_keys
INIT_PORTS=$(cat ${ENV_FILE} |grep '^InitPorts' |cut -d= -f2)
DEBUG_PORT=$(cat ${ENV_FILE} |grep '^DebugPort' |cut -d= -f2)

function printHelp () {
    echo "Usage: ./`basename $0` [-t up|down]"
}

function sshConn() {
    sshpass -p ${REMOTE_PASSWD} ssh -o StrictHostKeychecking=no ${REMOTE_USER}@${1} "$2"
}

function copyNodeFiles() {
    echo "copy files: '$2'"
    sshpass -p ${REMOTE_PASSWD} scp -o StrictHostKeychecking=no -C -r "$2" ${REMOTE_USER}@${1}:${CHAIN_DATA}
}

function validateArgs () {
    if [ -z "${OP_TYPE}" ]; then
        echo "Option up/down not mentioned"
        printHelp
        exit 1
    fi
}

function createNodeKey() {
    validator=$1
    tagfile=$2

    if [ -f "${tagfile}" ]; then
        rm -f ${tagfile}
    fi

    echo "{\"priv_key\":" >> ${tagfile}
    cat ${validator} |jq -r '.priv_key' >> ${tagfile}
    echo "}" >> ${tagfile}

    cat ${tagfile} |jq . > ${tagfile}.bak
    mv ${tagfile}.bak ${tagfile}
}

function createPubKeyFile() {
    validator=$1
    nodeName=$2

    tmp=${PUB_KEYS}.${nodeName}
    cat ${validator} |jq '.validators[0]' >> ${tmp}

    nodeIdx=$(echo ${nodeName}|awk -Fr '{print $2}')
    if [ ${nodeIdx} -gt 1 ]; then
        sed -i '1i,' ${tmp}
    fi
}

function createStartScript() {
    masterAddr=$1
    startScript=$2
    name=$3
    host=$4
    argPorts=$5
    index=$6
    
    echo "test node: ${HOST_NUMBER}"
    if [ "${HOST_NUMBER}" -gt 1 ]; then network_mode=host; else network_mode=bridge; fi

    pprof_debug=""
    persistent_peers=""
    tm_port=$(echo ${argPorts} |awk -F'-p ' '{print $3}'|cut -d: -f2)
    if [ "${index}" -gt 0 ]; then persistent_peers="--persistent_peers=${masterAddr}@${host}:46656"; fi
    if [ "${host}" == "${LOCALHOST_IP}" ]; then
        if [ "${DEBUG_PORT}" != "" ]; then
            DEBUG_PORT=$(expr ${DEBUG_PORT} + 1);
            argPorts="${argPorts} -p ${DEBUG_PORT}:${DEBUG_PORT}"
            pprof_debug="--pprof_port=${DEBUG_PORT}";
        fi
    fi

    
cat << EOF > ${startScript}
docker run -tid --net=${network_mode} --name=${name} \\
    ${argPorts} \\
    -v ${CHAIN_DATA}/${name}:/chaindata \\
    -v ${BIN_DIR}:/bin ${OP_SYSTEM} /bin/ethermint \\
    --datadir /chaindata --with-tendermint --rpc --rpccorsdomain=0.0.0.0 --rpcaddr=0.0.0.0 --ws --wsaddr=0.0.0.0 --rpcapi eth,net,web3,personal,admin,shh \\
    --gcmode=full --lightpeers=15 --pex=true --fast_sync=true --routable_strict=false \\
    --priv_validator_file=config/priv_validator.json --addr_book_file=addr_book.json \\
    --tendermint_p2paddr=tcp://0.0.0.0:${tm_port} ${persistent_peers} ${pprof_debug} --logLevel=info
EOF

    # init user keystore
    src_keystore=${ROOT_FOLDER}/config/keystore
    tag_keystore=${CHAIN_DATA}/${name}/keystore
    if [[ -d "${src_keystore}" && -d "${tag_keystore}" ]]; then
        cp -r ${src_keystore}/* ${tag_keystore}/
    fi
}

function mergeNodePubKeys() {
    echo "start merge node pubkeys ..."
    temp=${PUB_KEYS}.tmp
    echo "{\"validators\":[" >> ${temp}
    cat $(ls ${PUB_KEYS}.peer*) >> ${temp}
    echo "]}" >> ${temp}
    cat ${temp} |jq . > ${PUB_KEYS}

    rm -rf ${temp} ${PUB_KEYS}.peer*
}

function replacePubKey() {
    validator=$1
    replaceStr="$2,"
    chainid=$3

    cat ${validator} |jq . > ${validator}.bak
    value=$(sed -n '/app_hash/=' ${validator}.bak)
    start=$(sed -n '/validators/=' ${validator}.bak)
    end=$(expr "${value}" - 1)
    sed "${start},${end}c $(echo ${replaceStr})" ${validator}.bak |jq . > ${validator}

    oldValue=$(cat ${validator} |jq -r '.chain_id')
    sed -i "s/${oldValue}/${chainid}/g" ${validator}

    rm -f ${validator}.bak
}

function replaceGenesisPubKey() {
    echo "start replace genesis pubkeys ..."
    chainid=$1
    end_mark=$(expr $(sed -n '$=' ${PUB_KEYS}) - 1)
    context=$(sed -n "2,${end_mark}p" ${PUB_KEYS})

    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        name=$(echo ${nodeInfo%=*})

        json_file=${CHAIN_DATA}/${name}/tendermint/config/genesis.json
        replacePubKey ${json_file} "${context}" "${chainid}"
    done
    rm -f ${PUB_KEYS}
}

function startNodeService() {
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}
        addr=${nodeInfo#*=}

        echo "start script at ${addr}:${name} ..."
        if [ "${addr}" == "${LOCALHOST_IP}" ]; then
            # sh ${CHAIN_DATA}/${name}/start.sh
            echo "sh ${CHAIN_DATA}/${name}/start.sh"
        else
            sshConn ${addr} "mkdir -p ${CHAIN_DATA}"
            copyNodeFiles ${addr} "${CHAIN_DATA}/${name}"
            copyNodeFiles ${addr} "${ROOT_FOLDER}/config"
            copyNodeFiles ${addr} "${ROOT_FOLDER}/script"
            copyNodeFiles ${addr} "${ROOT_FOLDER}/tools"
            sshConn ${addr} "sh ${CHAIN_DATA}/${name}/start.sh"
        fi
    done
}

function adjustLocalPortOfStartCommand() {
    addValue=0
    if [ "${1}" == "${LOCALHOST_IP}" ]; then
        addValue=${2}
    fi

    adjusted=""
    for p in ${INIT_PORTS}; do
        value=$(echo ${p} |awk -F':' -v vl="${addValue}" '{print "-p "$1+vl":"$2}')
        adjusted="${adjusted} ${value}"
    done
    
    echo ${adjusted}
}

function networkUp() {
    master_address=""
    master_hostip=""
    master_chainid=""
   
    index=0
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        typeInfo=${node#*,}
        
        name=${nodeInfo%=*}
        addr=${nodeInfo#*=}
        nodeType=${typeInfo#*=}
        argPorts=$(adjustLocalPortOfStartCommand ${addr} $(expr ${name#*r} - 1))
        home=${CHAIN_DATA}/${name}/tendermint
        chaindata=${CHAIN_DATA}/${name}/ethermint/chaindata

        ${BIN_DIR}/ethermint --datadir ${CHAIN_DATA}/${name}/ init ${CFG_FILE}
        ${BIN_DIR}/tendermint init --home ${home}
        cp ${CFG_FILE} ${chaindata}
        rm -rf ${home}/config/accountmap.json

        createNodeKey ${home}/config/priv_validator.json ${home}/config/node_key.json
        if [ "${nodeType}" == "1" ]; then
            createPubKeyFile ${home}/config/genesis.json ${name}
        fi
        if [ "${index}" -eq 0 ]; then
            master_host=$addr
            master_address=$(cat ${home}/config/priv_validator.json |jq -r '.address' |sed 's/"//g' |tr 'A-Z' 'a-z')
            master_chainid=$(cat ${home}/config/genesis.json |jq -r '.chain_id')
        fi
        createStartScript ${master_address} ${CHAIN_DATA}/${name}/start.sh ${name} ${master_host} "${argPorts}" $index

        index=$(expr $index + 1)
    done

    mergeNodePubKeys
    replaceGenesisPubKey "${master_chainid}"
    startNodeService

    # install smart contract
    # sh ./start.sh
}

function networkDown() {
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        addr=${nodeInfo#*=}

        echo "stop network at ${addr} ..."
        if [ "${addr}" != "${LOCALHOST_IP}" ]; then
            sshConn ${addr} "docker ps -a |grep ethermint |awk '{print \$1}' |xargs -ti docker rm -f {}"
            sshConn ${addr} "rm -rf ${CHAIN_DATA}/*"
        else
            docker ps -a |grep ethermint |awk '{print $1}' |xargs -ti docker rm -f {}
            break
        fi
    done
    rm -rf ${CHAIN_DATA}/*
}

function replaceGenesisName() {
    oldValue="\"name\":\"\""
    newValue="\"name\":\"$1\""
    
    json_file=${CHAIN_DATA}/${1}/tendermint/config/genesis.json
    sed "s/${oldValue}/${newValue}/g" ${json_file} |jq . > ${json_file}.bak
    mv ${json_file}.bak ${json_file}
}

function networkNodeAdd() {
    first_node=$(cat ${ENV_FILE} |grep '^init:peer' |cut -d: -f2 |head -1)
    first_node_name=${first_node%=*}
    first_node_host=${first_node#*=}
    home=${CHAIN_DATA}/${first_node_name}/tendermint
    if [ ! -d "${home}" ]; then
        echo "${first_node_name} is not exists"
        exit 1
    fi
    master_address=$(cat ${home}/config/priv_validator.json |jq -r '.address' |sed 's/"//g' |tr 'A-Z' 'a-z')

    for node in ${ADD_NODES}; do
        nodeInfo=${node%,*}
        typeInfo=${node#*,}
        
        name=${nodeInfo%=*}
        addr=${nodeInfo#*=}
        nodeType=${typeInfo#*=}
        argPorts=$(adjustLocalPortOfStartCommand ${addr} $(expr ${name#*r} - 1))
        home=${CHAIN_DATA}/${name}/tendermint
        chaindata=${CHAIN_DATA}/${name}/ethermint/chaindata

        ethermint --datadir ${CHAIN_DATA}/${name}/ init ${CFG_FILE}
        tendermint init --home ${home}
        cp ${CFG_FILE} ${chaindata}
        
        replaceGenesisName ${name}
        createNodeKey ${home}/config/priv_validator.json ${home}/config/node_key.json
        createPubKeyFile ${home}/config/genesis.json ${name}
        createStartScript ${master_address} ${CHAIN_DATA}/${name}/start.sh ${name} ${first_node_host} "${argPorts}" 1 
       
        if [ "${NODE_FROM}" != "" ]; then
            echo "only support repair one consensus node"
            break
        fi
    done
    rm -rf ${CHAIN_DATA}/${PUB_KEYS}.peer*
}

function execute() {
    case ${OP_TYPE} in
        "up")
            networkUp
            ;;
        "down")
            networkDown
            ;;
        "add")
            networkNodeAdd
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
        OP_TYPE=$OPTARG
        ;;
    ?)
        printHelp
        exit 1
    esac
done

# dos2unix .env >& /dev/null
validateArgs
execute
