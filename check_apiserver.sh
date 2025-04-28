#!/bin/bash

APISERVER_VIP=192.168.31.100
APISERVER_DEST_PORT=8443

errorExit() {
        echo "* * * $*" 1>&2
        exit 1
}

# Проверяем только если VIP на этом хосте
if ip addr | grep -q ${APISERVER_VIP}; then
        curl --silent --max-time 2 --insecure https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/"
fi

exit 0
