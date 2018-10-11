#!/bin/bash

set -e

function printHelp () {
    echo "Usage: ./`basename $0` -t [up|down] -v [0.18.0|0.23.1]"
}

# parse script args
while getopts ":t:v:" OPTION; do
    case ${OPTION} in
    t)
        OP_METHOD=$OPTARG
        ;;
    v)
        OP_VERSION=$OPTARG
        ;;
    ?)
        printHelp
        exit 1
    esac
done

# all global envirment parameter
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
KEYSTORE=${ROOT_DIR}/config/keystore
GNS_FILE=${ROOT_DIR}/config/genesis.json
ENV_FILE=${ROOT_DIR}/config/env.json
EXEC_DIR=${ROOT_DIR}/tools/${OP_VERSION}

DOCKER_OS=$(cat ${ENV_FILE} |jq '.system'|sed 's/"//g')
LOGIN_USR=$(cat ${ENV_FILE} |jq '.user.name'|sed 's/"//g')
LOGIN_PWD=$(cat ${ENV_FILE} |jq '.user.passwd'|sed 's/"//g')
CHAIN_DIR=$(cat ${ENV_FILE} |jq '.datapath'|sed 's/"//g')
LOCALHOST=$(cat ${ENV_FILE} |jq '.localhost'|sed 's/"//g')
NODE_LIST=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|sed 's/"//g')
IP_NUMBER=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|cut -d= -f2|cut -d, -f1|sort|uniq|wc -l)
ADD_NODES=$(cat ${ENV_FILE} |jq '.setup.node.add.host[]'|sed 's/"//g')
NODE_FROM=$(cat ${ENV_FILE} |jq '.setup.add.from.node'|sed 's/"//g')

PUB_KEYS=${CHAIN_DIR}/pub_keys
VER_PORT=$(cat ${ENV_FILE}    |jq '.setup.port' |jq -c "map(select([.version == "\"${OP_VERSION}\""] | all))[]")
INIT_PORTS=$(echo ${VER_PORT} |jq '.ports'|sed 's/"//g')
DEBUG_PORT=$(echo ${VER_PORT} |jq '.debug'|sed 's/"//g')
HAVE_TMP2P=$(echo ${VER_PORT} |jq '.p2ptm'|sed 's/"//g')

function sshConn() {
    sshpass -p ${LOGIN_PWD} ssh -o StrictHostKeychecking=no ${LOGIN_USR}@${1} "$2"
}

function copyNodeFiles() {
    echo "copy files: '$2'"
    sshpass -p ${LOGIN_PWD} scp -o StrictHostKeychecking=no -C -r "$2" ${LOGIN_USR}@${1}:${CHAIN_DIR}
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
    
    # echo "test node: ${IP_NUMBER}"
    # docker network mode, single use bridge
    if [ "${IP_NUMBER}" -gt 1 ]; then network_mode=host; else network_mode=bridge; fi

    # persistent peers, and support pprof debug port
    if [ "${index}" -gt 0 ]; then persistent_peers="--persistent_peers=${masterAddr}@${host}:46656"; fi
    if [ "${host}" == "${LOCALHOST}" ]; then
        if [ "${DEBUG_PORT}" -ne 0 ]; then
            DEBUG_PORT=$(expr ${DEBUG_PORT} + 1);
            argPorts="${argPorts} -p ${DEBUG_PORT}:${DEBUG_PORT}"
            pprof_debug="--pprof_port=${DEBUG_PORT}";
        fi
    fi

    # high version support parameter
    if [ "${HAVE_TMP2P}" -eq 1 ]; then
        tm_port=$(echo ${argPorts} |awk -F'-p ' '{print $3}'|cut -d: -f2)
        tm_p2paddr="--tendermint_p2paddr=tcp://0.0.0.0:${tm_port}"
    fi
    
cat << EOF > ${startScript}
docker run -tid --net=${network_mode} --name=${name} \\
    ${argPorts} \\
    -v ${CHAIN_DIR}/${name}:/chaindata \\
    -v ${EXEC_DIR}:/bin ${DOCKER_OS} /bin/ethermint \\
    --datadir /chaindata --with-tendermint --rpc --rpccorsdomain=0.0.0.0 --rpcaddr=0.0.0.0 --ws --wsaddr=0.0.0.0 --rpcapi eth,net,web3,personal,admin,shh \\
    --gcmode=full --lightpeers=15 --pex=true --fast_sync=true --routable_strict=false \\
    --priv_validator_file=config/priv_validator.json --addr_book_file=addr_book.json \\
    ${tm_p2paddr} ${persistent_peers} ${pprof_debug} --logLevel=info
EOF

    # init user keystore
    peer_keystore=${CHAIN_DIR}/${name}/keystore
    if [[ -d "${KEYSTORE}" && -d "${peer_keystore}" ]]; then
        cp -r ${KEYSTORE}/* ${peer_keystore}/
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

        json_file=${CHAIN_DIR}/${name}/tendermint/config/genesis.json
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
        if [ "${addr}" == "${LOCALHOST}" ]; then
            echo "sh ${CHAIN_DIR}/${name}/start.sh"
            sh ${CHAIN_DIR}/${name}/start.sh
        else
            sshConn ${addr} "mkdir -p ${CHAIN_DIR}"
            copyNodeFiles ${addr} "${CHAIN_DIR}/${name}"
            copyNodeFiles ${addr} "${ROOT_DIR}/config"
            copyNodeFiles ${addr} "${ROOT_DIR}/script"
            copyNodeFiles ${addr} "${ROOT_DIR}/tools"
            sshConn ${addr} "sh ${CHAIN_DIR}/${name}/start.sh"
        fi
    done
}

function adjustLocalPortOfStartCommand() {
    addValue=0
    if [ "${1}" == "${LOCALHOST}" ]; then
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
        home=${CHAIN_DIR}/${name}/tendermint
        chaindata=${CHAIN_DIR}/${name}/ethermint/chaindata

        ${EXEC_DIR}/ethermint --datadir ${CHAIN_DIR}/${name}/ init ${GNS_FILE}
        ${EXEC_DIR}/tendermint init --home ${home}
        cp ${GNS_FILE} ${chaindata}
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
        createStartScript ${master_address} ${CHAIN_DIR}/${name}/start.sh ${name} ${master_host} "${argPorts}" $index

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
        if [ "${addr}" != "${LOCALHOST}" ]; then
            sshConn ${addr} "docker ps -a |grep ethermint |awk '{print \$1}' |xargs -ti docker rm -f {}"
            sshConn ${addr} "rm -rf ${CHAIN_DIR}/*"
        else
            docker ps -a |grep ethermint |awk '{print $1}' |xargs -ti docker rm -f {}
            break
        fi
    done
    rm -rf ${CHAIN_DIR}/*
}

function replaceGenesisName() {
    oldValue="\"name\":\"\""
    newValue="\"name\":\"$1\""
    
    json_file=${CHAIN_DIR}/${1}/tendermint/config/genesis.json
    sed "s/${oldValue}/${newValue}/g" ${json_file} |jq . > ${json_file}.bak
    mv ${json_file}.bak ${json_file}
}

function networkNodeAdd() {
    first_node=$(cat ${ENV_FILE} |grep '^init:peer' |cut -d: -f2 |head -1)
    first_node_name=${first_node%=*}
    first_node_host=${first_node#*=}
    home=${CHAIN_DIR}/${first_node_name}/tendermint
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
        home=${CHAIN_DIR}/${name}/tendermint
        chaindata=${CHAIN_DIR}/${name}/ethermint/chaindata

        ethermint --datadir ${CHAIN_DIR}/${name}/ init ${GNS_FILE}
        tendermint init --home ${home}
        cp ${GNS_FILE} ${chaindata}
        rm -rf ${home}/config/accountmap.json
        
        replaceGenesisName ${name}
        createNodeKey ${home}/config/priv_validator.json ${home}/config/node_key.json
        createPubKeyFile ${home}/config/genesis.json ${name}
        createStartScript ${master_address} ${CHAIN_DIR}/${name}/start.sh ${name} ${first_node_host} "${argPorts}" 1 
       
        if [ "${NODE_FROM}" != "" ]; then
            echo "only support repair one consensus node"
            break
        fi
    done
    rm -rf ${CHAIN_DIR}/${PUB_KEYS}.peer*
}

function validateArgs () {
    if [ -z "${OP_METHOD}" ]; then
        echo "Option up/down not mentioned"
        printHelp
        exit 1
    fi
}

function executeCommand() {
    case ${OP_METHOD} in
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

validateArgs
executeCommand

