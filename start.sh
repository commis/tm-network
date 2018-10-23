#/bin/bash

peers=$(find /home/share/chaindata_23 -name "peer*")
for p in ${peers}; do
    sh ${p}/start.sh
done
# docker logs -f peer2
