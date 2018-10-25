#!/bin/bash

set -e

# all global envirment parameter
OP_VERSION=0.23.1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
GNS_FILE=${ROOT_DIR}/config/genesis.json
EXEC_DIR=${ROOT_DIR}/tools/${OP_VERSION}
EXEC_BIN=${ROOT_DIR}/tools/${OP_VERSION}/tm_tools

DOCKER_OS=$(cat ${ENV_FILE} |jq '.system'|sed 's/"//g')
LOCALHOST=$(cat ${ENV_FILE} |jq '.localhost'|sed 's/"//g')
NODE_LIST=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|sed 's/"//g')
IP_NUMBER=$(cat ${ENV_FILE} |jq '.setup.node.init[]'|cut -d= -f2|cut -d, -f1|sort|uniq|wc -l)

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')
PUB_KEYS=${NEW_DATA}/pub_keys
VER_PORT=$(cat ${ENV_FILE}    |jq '.setup.port' |jq -c "map(select([.version == "\"${OP_VERSION}\""] | all))[]")
INIT_PORTS=$(echo ${VER_PORT} |jq '.ports'|sed 's/"//g')
HAVE_TMP2P=$(echo ${VER_PORT} |jq '.p2ptm'|sed 's/"//g')
DEBUG_PORT=$(echo ${VER_PORT} |jq '.debug'|sed 's/"//g')

function message_color() {
    echo -e "\033[40;31m[$1]\033[0m"
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
    pprof_debug=""
    persistent_peers=""
    if [ "${index}" -gt 0 ]; then persistent_peers="--persistent_peers=${masterAddr}@${host}:46656"; fi
    if [ "${host}" == "${LOCALHOST}" ]; then
        if [ "${DEBUG_PORT}" -ne 0 ]; then
            DEBUG_PORT=$(expr ${DEBUG_PORT} + 1);
            argPorts="${argPorts} -p ${DEBUG_PORT}:${DEBUG_PORT}"
            pprof_debug="--pprof_port=${DEBUG_PORT}";
        fi
    fi

    # high version support parameter
    tm_p2paddr=""
    if [ "${HAVE_TMP2P}" -eq 1 ]; then
        tm_port=$(echo ${argPorts} |awk -F'-p' '{print $3}'|cut -d: -f2|sed 's/ //g')
        tm_p2paddr="--tendermint_p2paddr=tcp://0.0.0.0:${tm_port}"
    fi
    
cat << EOF > ${startScript}
docker run -tid --net=${network_mode} --name=${name} \\
    ${argPorts} \\
    -v ${NEW_DATA}/${name}:/chaindata \\
    -v ${EXEC_DIR}:/bin ${DOCKER_OS} /bin/ethermint \\
    --datadir /chaindata --with-tendermint --rpc --rpccorsdomain=0.0.0.0 --rpcaddr=0.0.0.0 --ws --wsaddr=0.0.0.0 --rpcapi eth,net,web3,personal,admin,shh \\
    --gcmode=full --lightpeers=15 --pex=true --fast_sync=true --routable_strict=false \\
    --priv_validator_file=config/priv_validator.json --addr_book_file=addr_book.json \\
    ${persistent_peers} ${pprof_debug} --logLevel=info
EOF
# ${tm_p2paddr} 
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

function init_upgrade_nodes() {
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        name=${nodeInfo%=*}

        newPath=${NEW_DATA}/${name}/tendermint
        mkdir -p ${newPath}

        ${EXEC_DIR}/tendermint init --home ${newPath}
        rm -rf ${newPath}/config/accountmap.json

        ethData=${name}/ethermint
        keystore=${name}/keystore
        cp -R ${OLD_DATA}/${ethData} ${NEW_DATA}/${ethData}
        cp -R ${OLD_DATA}/${keystore} ${NEW_DATA}/${keystore}
    done
}

function migrate_node() {
    tmData=${1}/tendermint
    oldPath=${OLD_DATA}/${tmData}
    newPath=${NEW_DATA}/${tmData}
    
    echo "${EXEC_BIN} migrate --old ${oldPath} --new ${newPath}"
    ${EXEC_BIN} migrate --old ${oldPath} --new ${newPath}
    
    rm -rf ${newPath}/data/evidence.db
    rm -rf ${newPath}/data/mempool.wal
    rm -rf ${newPath}/data/tx_index.db
  
    message_color "finished to migrate ${oldPath}"
}

function do_upgrade_nodes() {
    rm -rf ${NEW_DATA}/*
    init_upgrade_nodes

    index=0
    master_address=""
    master_hostip=""
    master_chainid=""
    upgradeNodeFile=${OLD_DATA}/topNode.txt
    touch ${upgradeNodeFile}
    datadir=/tendermint/data
   
    for node in ${NODE_LIST}; do
        nodeInfo=${node%,*}
        typeInfo=${node#*,}

        name=${nodeInfo%=*}
        addr=${nodeInfo#*=}
        home=${NEW_DATA}/${name}/tendermint

        topNode=`cat ${upgradeNodeFile} |head -1|awk '{print $1}'`
        if [[ "${topNode}" == "" || "${topNode}" == "${name}" ]]; then
            message_color "need upgrade data for node ${name}"
            migrate_node ${name}
        else
            message_color "need copy data for node ${name}"
            rm -rf ${NEW_DATA}/${name}/${datadir}/*
            cp -R ${NEW_DATA}/${topNode}/${datadir}/* ${NEW_DATA}/${name}/${datadir}/
        fi
        createNodeKey ${home}/config/priv_validator.json ${home}/config/node_key.json
        
        if [ "${index}" -eq 0 ]; then
            master_host=$addr
            master_address=$(cat ${home}/config/priv_validator.json |jq -r '.address' |sed 's/"//g' |tr 'A-Z' 'a-z')
            master_chainid=$(cat ${home}/config/genesis.json |jq -r '.chain_id')
        fi
        
        argPorts=$(adjustLocalPortOfStartCommand ${addr} $(expr ${name#*r} - 1))
        createStartScript ${master_address} ${NEW_DATA}/${name}/start.sh ${name} ${master_host} "${argPorts}" $index
        index=$(expr $index + 1)
    done
    message_color "finished tendermint all data upgrade"
}

# main function
function main() {
    do_upgrade_nodes
}
main $# 2>&1 |grep -v 'duplicate proto'
