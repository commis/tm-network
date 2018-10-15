#!/bin/bash

# set -e

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

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.src_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.tag_data'|sed 's/"//g')
PUB_KEYS=${NEW_DATA}/pub_keys
VER_PORT=$(cat ${ENV_FILE}    |jq '.setup.port' |jq -c "map(select([.version == "\"${OP_VERSION}\""] | all))[]")
INIT_PORTS=$(echo ${VER_PORT} |jq '.ports'|sed 's/"//g')
DEBUG_PORT=$(echo ${VER_PORT} |jq '.debug'|sed 's/"//g')
HAVE_TMP2P=$(echo ${VER_PORT} |jq '.p2ptm'|sed 's/"//g')

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
    ${tm_p2paddr} ${persistent_peers} ${pprof_debug} --logLevel=info
EOF
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

        json_file=${NEW_DATA}/${name}/tendermint/config/genesis.json
        replacePubKey ${json_file} "${context}" "${chainid}"
    done
    rm -f ${PUB_KEYS}
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

function replaceGenesisName() {
    oldValue="\"name\":\"\""
    newValue="\"name\":\"$1\""
    
    json_file=${NEW_DATA}/${1}/tendermint/config/genesis.json
    sed "s/${oldValue}/${newValue}/g" ${json_file} |jq . > ${json_file}.bak
    mv ${json_file}.bak ${json_file}
}

function view_all() {
    rstdir=$1
    dbdir=$2
    database=$3
    output=${rstdir}/${database}_all.txt

    db=${dbdir}/data/${database}
    ${EXEC_BIN} view --db ${db} --a getall |sort -n -k2 -t: > ${output} 
    
    echo "view all ${database} for ${db} finished."
}

function view_detail_info() {
    rstdir=$1
    dbdir=$2
    database=$3
    params=$4
    output=${rstdir}/${database}
    mkdir -p ${output}
    
    db=${dbdir}/data/${database}
    srcfile=${TM_VIEW}/${rstdir}/${database}_all.txt
    while read line; do
        outfile=${output}/$(echo $line |sed 's/:/_/g').txt
        # echo "${EXEC_BIN} view --db ${db} --q $line ${params} |jq ."
        ${EXEC_BIN} view --db ${db} --q $line ${params} |jq . > ${outfile} 
    done < ${srcfile}
    
    echo "view all of ${database} for ${db} finished."
}

function view_version_data() {
    dbdir=$1
    rstdir=$1/result
    params="--d"
    if [ "$2" == "new" ]; then params="${params} --v"; fi
    mkdir -p ${rstdir}

    view_all ${rstdir} ${dbdir} "blockstore"
    view_detail_info ${rstdir} ${dbdir} "blockstore" "${params}"
    
    view_all ${rstdir} ${dbdir} "state"
    view_detail_info ${rstdir} ${dbdir} "state" "${params}"
    
    # view_all ${rstdir} ${verdir} "evidence"
    # view_all ${rstdir} ${verdir} "trusthistory"
}

function migrate_node() {
    tmData=${1}/tendermint
    ethData=${1}/ethermint
    cp -R ${OLD_DATA}/${ethData} ${NEW_DATA}/${ethData}
    cp -R ${OLD_DATA}/${1}/keystore ${NEW_DATA}/${1}/keystore

    oldPath=${OLD_DATA}/${tmData}
    newPath=${NEW_DATA}/${tmData}
    ${EXEC_DIR}/tendermint init --home ${newPath}
    rm -rf ${home}/config/accountmap.json
    cp -R ${oldPath}/data/cs.wal ${newPath}/data/cs.wal

    echo "${EXEC_BIN} migrate --old ${oldPath} --new ${newPath}"
    view_version_data ${oldPath} "old"
    ${EXEC_BIN} migrate --old ${oldPath} --new ${newPath}
    view_version_data ${newPath} "new"
   
    echo "migrate finished at ${1}"
}

function do_upgrade() {
    rm -rf ${NEW_DATA}/*
    
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
        home=${NEW_DATA}/${name}/tendermint
        mkdir -p ${home}

        migrate_node ${name}
        createNodeKey ${home}/config/priv_validator.json ${home}/config/node_key.json
        if [ "${nodeType}" == "1" ]; then
            createPubKeyFile ${home}/config/genesis.json ${name}
        fi
        if [ "${index}" -eq 0 ]; then
            master_host=$addr
            master_address=$(cat ${home}/config/priv_validator.json |jq -r '.address' |sed 's/"//g' |tr 'A-Z' 'a-z')
            master_chainid=$(cat ${home}/config/genesis.json |jq -r '.chain_id')
        fi
        createStartScript ${master_address} ${NEW_DATA}/${name}/start.sh ${name} ${master_host} "${argPorts}" $index

        index=$(expr $index + 1)
    done

    mergeNodePubKeys
    replaceGenesisPubKey "${master_chainid}"
}

# main function
function main() {
    do_upgrade
}
main 2>&1 |grep -v 'duplicate proto'
