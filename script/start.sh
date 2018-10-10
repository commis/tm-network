#!/bin/bash

ROOT_FOLDER=$(cd `dirname $(readlink -f "$0")`/..; pwd)

host=192.168.56.3

curr_dir=`pwd`
cd ${ROOT_FOLDER}/chaincode

echo "start replace server host address ..."
sed -i "s@http.*@http://${host}:8545\"));@g" 1.compileDeploy_tree.js 1.compileDeploy_greenToken.js
echo

echo "start deploy tree ..."
node 1.compileDeploy_tree.js
echo

echo "start deploy green token chaincode ..."
node 1.compileDeploy_greenToken.js
echo

cd ${curr_dir}

