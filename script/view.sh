#!/bin/bash

# set -e

# all global envirment parameter
OP_VERSION=0.23.1
ROOT_DIR=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
EXEC_BIN=${ROOT_DIR}/tools/${OP_VERSION}/tm_tools

OLD_DATA=/home/share/chaindata
NEW_DATA=/home/share/chaindata_23

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

function do_view() {
    dataPath=${NEW_DATA}/${1}/tendermint

    view_version_data ${dataPath} "new"

    echo "view finished at ${dataPath}"
}


# main function
function main() {
    do_view "peer1"
}
main 2>&1 |grep -v 'duplicate proto'
