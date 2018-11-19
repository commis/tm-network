#!/bin/bash

set -e

ROOT_FOLDER=$(cd `dirname $(readlink -f "$0")`/.. && pwd)

build_modules="
github.com/tendermint/tendermint
github.com/tendermint/ethermint
"

curr_dir=`pwd`
for dir in ${build_modules}; do
    cd ${GOPATH}/src/${dir}
    make install
done

cd ${GOPATH}/bin
cp -f ethermint tendermint ${ROOT_FOLDER}/tools/0.18.0
cd ${ROOT_FOLDER}/tools/0.18.0
chmod 777 ethermint tendermint

cd ${curr_dir}
