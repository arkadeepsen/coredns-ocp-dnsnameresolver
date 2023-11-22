#!/bin/bash

set -euxo pipefail

# Create a temporary directory for cloning openshift/coredns repo.
# The directory will be deleted after the execution of script.
BASE_PATH=$(mktemp -d)
trap "chmod -R u+w $BASE_PATH; rm -rf $BASE_PATH" EXIT

CURRENT_DIR=$(pwd)

cd $BASE_PATH
# Clone openshift/coredns repo if not already cloned.
if [ ! -d coredns ]
then
    git clone https://github.com/openshift/coredns
fi

cd $CURRENT_DIR
# Add the "ocp_dnsnameresolver" plugin to the cloned openshift/coredns repo.
GO111MODULE=on GOFLAGS=-mod=mod $CURRENT_DIR/hack/add-plugin.sh $BASE_PATH/coredns

cd $BASE_PATH/coredns

# Build the coredns executable.
GO111MODULE=on GOFLAGS=-mod=vendor go build -o coredns .

# Copy it to the local directory.
cp coredns $CURRENT_DIR