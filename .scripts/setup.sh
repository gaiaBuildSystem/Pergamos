#!/bin/bash

##
# This script will check for the dependencies
# This was designed for Debian based systems
# TODO: test with podman
# Even though we check for podman, this was not tested
##

PERGAMOS_USE_DOCKER="0"
PERGAMOS_USE_PODMAN="0"
PERGAMOS_RUN_CMD=""

# check if we are running on a debian based system
if [ -f /etc/debian_version ]; then
    echo "Debian based system detected"
else
    echo "This script was designed for Debian based systems"
    echo "Is possible to run on debian based Container"
    echo "Install Docker or Podman and use the .conf/docker-compose.yml"
    exit 404
fi

# ok, we are on a debian based system
# continue with the checks

# check if we have docker installed
if [ -x "$(command -v docker)" ]; then
    echo "Docker is installed"
    PERGAMOS_USE_DOCKER="1"
    PERGAMOS_RUN_CMD="docker compose -f .conf/docker-compose.yml"
else
    # check if we have podman installed
    if [ -x "$(command -v podman)" ]; then
        echo "Podman is installed"
        PERGAMOS_USE_PODMAN="1"
        PERGAMOS_RUN_CMD="podman compose -f .conf/docker-compose.yml"
    else
        echo "Please install Docker or Podman"
        echo "For install Docker: https://docs.docker.com/engine/install/debian/"
        echo "For install Podman: https://podman.io/docs/installation#debian"
        exit 404
    fi
fi

# check the compose
if [ "$PERGAMOS_USE_DOCKER" == "1" ]; then
    if dpkg -l | grep -q docker-compose-plugin; then
        echo "docker-compose-plugin is installed"
    else
        echo "docker-compose-plugin is not installed"
        echo "please install docker and docker-compose-plugin: https://docs.docker.com/engine/install/debian/"
        exit 404
    fi
fi

if [ "$PERGAMOS_USE_PODMAN" == "1" ]; then
    if dpkg -l | grep -q podman-compose; then
        echo "podman-compose is installed"
    else
        echo "podman-compose is not installed"
        echo "please install podman and podman-compose: https://packages.debian.org/bookworm/podman-compose"
        exit 404
    fi
fi

# run
echo "Running: $PERGAMOS_RUN_CMD"
$PERGAMOS_RUN_CMD build builder
$PERGAMOS_RUN_CMD run --rm builder-dev
