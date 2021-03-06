#!/bin/bash

export VHOST_SOCK_DIR=/tmp/vpp

sudo docker run -it --name=vpp-docker-local -v /dev/hugepages:/dev/hugepages -v ${VHOST_SOCK_DIR}:/tmp/vpp --privileged "vpp-base"
