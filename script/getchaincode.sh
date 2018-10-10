#!/bin/bash

ROOT_FOLDER=$(cd `dirname $(readlink -f "$0")`/..; pwd)

curr_dir=`pwd`
ccdir=${ROOT_FOLDER}/chaincode
mkdir -p ${ccdir} && cd ${ccdir}

echo "start get chaincode ..."
scp -r root@192.168.1.231:/home/WorkSpace/Product-CI-Jobs/deploy_chaincode/*.* . >& /dev/null
echo

# echo "start install ..." 
npm install web3@0.20.0 --save
npm install solc@0.4.21 --save
npm install
echo 

cd ${curr_dir}

