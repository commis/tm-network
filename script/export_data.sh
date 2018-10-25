#!/bin/bash

set -e

# all global envirment parameter
SHOW_VERSION=$1
OP_VERSION=0.23.1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
ENV_FILE=${ROOT_DIR}/config/env.json
EXEC_BIN=${ROOT_DIR}/tools/${OP_VERSION}/tm_tools

OLD_DATA=$(cat ${ENV_FILE} |jq '.upgrade.old_data'|sed 's/"//g')
NEW_DATA=$(cat ${ENV_FILE} |jq '.upgrade.new_data'|sed 's/"//g')

function message_color() {
    echo -e "\033[40;31m[$1]\033[0m"
}

function do_view_clean() {
    ps -ef |grep tm_tools |grep -v grep |awk '{print $2}' |xargs -ti kill -9 {}
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
    srcfile=${rstdir}/${database}_all.txt
    while read line; do
        if [ "${line}" == "C:0" ]; then
            continue
        fi
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
    walParams=""
    if [ "$2" == "new" ]; then
        params="${params} --v";
        walParams="--v";
    fi
    mkdir -p ${rstdir}
    rm -rf ${rstdir}/*

    view_all ${rstdir} ${dbdir} "blockstore"
    view_detail_info ${rstdir} ${dbdir} "blockstore" "${params}"
    
    view_all ${rstdir} ${dbdir} "state"
    view_detail_info ${rstdir} ${dbdir} "state" "${params}"
    
    echo "${EXEC_BIN} cswal --p ${dbdir} ${walParams}"
    ${EXEC_BIN} cswal --p ${dbdir} "${walParams}" > ${rstdir}/cswal.txt
}

function do_view_tendermint_data() {
    dataPath=${1}/tendermint

    view_version_data ${dataPath} ${2}

    message_color "view finished at ${dataPath}"
}

function validateArgs () {
    if [ $1 != 1 ]; then
        echo "Usage: ./`basename $0` [old|new]"
        exit 1
    fi
}

# main function
function main() {
    validateArgs $1
    if [ "${SHOW_VERSION}" == "new" ]; then
        if [ -d "${NEW_DATA}" ]; then existNodes=$(find ${NEW_DATA} -name "peer*"|sort); fi
    else
        SHOW_VERSION='old'
        if [ -d "${OLD_DATA}" ]; then existNodes=$(find ${OLD_DATA} -name "peer*"|sort); fi
    fi
    
    for node in ${existNodes}; do
        message_color "view tendermint data for ${node}"
        do_view_tendermint_data ${node} ${SHOW_VERSION}
    done
    do_view_clean
}
main $# 2>&1 |grep -v 'duplicate proto'
