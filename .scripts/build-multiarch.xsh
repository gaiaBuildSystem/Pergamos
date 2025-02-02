#!/usr/bin/env xonsh

# Copyright (c) 2023 Matheus Castello
# SPDX-License-Identifier: MIT

# use the xonsh environment to update the OS environment
$UPDATE_OS_ENVIRON = True
# always return if a cmd fails
$RAISE_SUBPROC_ERROR = True


import os
import sys
import json
import subprocess
import argparse
from pathlib import Path
from colorama import Fore, Back

script_path = Path(__file__).resolve().parent
sys.path.append(str(script_path))

import debug
import dockerutils
from writeconsole import write, write_log, write_info, write_error

# initialize parser
parser = argparse.ArgumentParser()

# add arguments
parser.add_argument("--container-file-folder", help="Container file folder")
parser.add_argument("--push", help="Push to DockerHub", action="store_true")
parser.add_argument("--no-cache", help="No cache", action="store_true")
parser.add_argument("--native", help="If set only build the navite machine architecture image", action="store_true")

# echo arguments
args = parser.parse_args()
container_file_folder = args.container_file_folder
push_to_dockerhub = args.push
no_cache = args.no_cache
native = args.native

write_log(f"\nContainer file folder: {container_file_folder}")
write_log(f"Push to DockerHub: {push_to_dockerhub}")
write_log(f"No cache: {no_cache}")

# debug.__breakpoint()

if container_file_folder is None:
    write_error("\n❌ Container file folder is required\n")
    exit(500)

# register the foreign architectures
dockerutils.binfmt()
dockerutils.buildx_multi_arch_setup()
dockerutils.docker_registry_login()

container_file_folder_path = Path(container_file_folder)
if container_file_folder_path.exists():
    $CONTAINER_IMAGE_NAME = container_file_folder_path.parent.name

    # Read metadata
    with open(container_file_folder_path / 'args.json') as f:
        metadata = json.load(f)

    # Check if this is the right script to build it
    if not metadata.get('multiarch', False):
        write_error("This is not buildable with this script, please use ./scripts/build.xsh", file=sys.stderr)
        sys.exit(69)

    $IMAGE_VERSION = metadata['version']
    $REGISTRY = metadata['registry']
    $IMAGE_REGISTRY = metadata['registry']
    $IMAGE_NAME = f"/{metadata['image']}"

    for args in metadata['machines']:
        $BASE_REGISTRY = args['BASE_REGISTRY']
        $BASE_IMAGE = args['BASE_IMAGE']
        $BASE_VERSION = args['BASE_VERSION']
        $GPU = args['GPU']
        $NAME = args['name']

        write_info(f"Building:")
        print(f"\n\tImage: {os.environ['REGISTRY']}{os.environ['IMAGE_NAME']}{os.environ['GPU']}:{os.environ['IMAGE_VERSION']}")
        print(f"\tImage Base: {os.environ['BASE_REGISTRY']}{os.environ['BASE_IMAGE']}{os.environ['GPU']}:{os.environ['BASE_VERSION']}")
        print(f"\tGPU: {args['GPU']}")

        # Get all archs
        archs = ",".join([f"linux/{arch}" for arch in args['arch']])
        for arch in args['arch']:
            print(f"\tArch: {arch}")

        # Set environment variables
        print("\n\t", end="")
        write_info("Environment variables:")
        print("")

        for key, value in args.items():
            __xonsh__.env[key.upper()] = str(value)
            os.environ[key.upper()] = __xonsh__.env[key.upper()]
            print(f"\t\t{key.upper()}: {os.environ[key.upper()]}")

        # aesthetically separate
        print("")

        if not native:
            # Build command
            dockerutils.buildx_build(
                docker_compose=f"{container_file_folder}/docker-compose.yml",
                archs=archs,
                no_cache=no_cache,
                push=push_to_dockerhub
            )
        else:
            dockerutils.buildx_build_native(
                docker_image=f"{os.environ['REGISTRY']}{os.environ['IMAGE_NAME']}{os.environ['GPU']}:{os.environ['IMAGE_VERSION']}",
                docker_compose=f"{container_file_folder}/docker-compose.yml",
                no_cache=no_cache,
                push=push_to_dockerhub
            )

else:
    write_error(f"{container_file_folder} does not exist")
    exit(404)
