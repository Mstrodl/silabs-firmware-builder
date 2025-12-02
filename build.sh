#!/bin/bash

set -eux
set -o pipefail

podman build . -t silabs
MOUNT=$(podman unshare podman image mount silabs)
rm -rf docker_outputs || true
mkdir docker_outputs
podman unshare cp -rv $MOUNT/build/outputs/ docker_outputs
chown bryx:bryx -R docker_outputs
podman unshare podman image unmount silabs
