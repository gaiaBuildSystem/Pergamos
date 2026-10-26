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

# echo arguments
args = parser.parse_args()
container_file_folder = args.container_file_folder
push_to_dockerhub = args.push
no_cache = args.no_cache

write_log(f"\nContainer file folder: {container_file_folder}")
write_log(f"Push to DockerHub: {push_to_dockerhub}")
write_log(f"No cache: {no_cache}")

# debug.__breakpoint()

if container_file_folder is None:
    write_error("\n❌ Container file folder is required\n")
    exit(500)

# register the foreign architectures
dockerutils.binfmt()
dockerutils.docker_registry_login()

container_file_folder_path = Path(container_file_folder)

# store the current working directory
_tmp_cwd = os.getcwd()


def _check_env_var(var_name):
    if var_name not in os.environ:
        write_error(f" ❌ {var_name} MUST BE SET")
        sys.exit(69)


if container_file_folder_path.exists():
    $CONTAINER_IMAGE_NAME = container_file_folder_path.parent.name

    # Read metadata
    with open(container_file_folder_path / 'args.json') as f:
        metadata = json.load(f)

    if metadata.get("multiarch", True) == True:
        write_error("This is not buildable with this script, please use ./scripts/build-multiarch.xsh")
        sys.exit(69)

    try:
        os.chdir(container_file_folder_path)

        # common properties
        os.environ["IMAGE_VERSION"] = metadata['version']
        __xonsh__.env["IMAGE_VERSION"] = metadata['version']
        os.environ["IMAGE_REGISTRY"] = metadata['registry']
        __xonsh__.env["IMAGE_REGISTRY"] = metadata['registry']
        os.environ["REGISTRY"] = metadata['registry']
        __xonsh__.env["REGISTRY"] = metadata['registry']
        os.environ["IMAGE_PREFIX"] = metadata['image_prefix']
        __xonsh__.env["IMAGE_PREFIX"] = metadata['image_prefix']

        for args in metadata['machines']:

            for key, value in args.items():
                __xonsh__.env[key.upper()] = str(value)
                os.environ[key.upper()] = __xonsh__.env[key.upper()]

            # set IMAGE_NAME and build it
            os.environ["IMAGE_NAME"] = f"{os.environ['IMAGE_PREFIX']}-{os.environ['NAME']}"
            __xonsh__.env["IMAGE_NAME"] = os.environ["IMAGE_NAME"]

            if no_cache == True:
                write_info("⚠️ Building without cache")

            write_info(f"Building:")
            print(f"\n\tImage: {os.environ['REGISTRY']}{os.environ['IMAGE_NAME']}{os.environ['GPU']}:{os.environ['IMAGE_VERSION']}")
            print(f"\tGPU: {args['GPU']}")

            # Set environment variables
            print("\n\t", end="")
            write_info("Environment variables:")
            print("")

            for key, value in args.items():
                print(f"\t\t{key.upper()}: {os.environ[key.upper()]}")

            # aesthetically separate
            print("")

            # sanity check
            _check_env_var("IMAGE_REGISTRY")
            _check_env_var("IMAGE_PREFIX")
            _check_env_var("NAME")
            _check_env_var("IMAGE_VERSION")

            if no_cache == True:
                docker compose build --no-cache
            else:
                docker compose build

            if push_to_dockerhub == True:
                dockerutils.docker_registry_login()
                docker compose push

            # also push with latest tag if configured
            _ret = subprocess.run(
                [
                    "docker", "tag",
                    f"{os.environ['IMAGE_NAME']}:{os.environ['IMAGE_VERSION']}",
                    f"{os.environ['IMAGE_NAME']}:latest"
                ],
                check=True,
                env=os.environ
            )

            _ret = subprocess.run(
                [
                    "docker", "push",
                    f"{os.environ['IMAGE_NAME']}:latest"
                ],
                check=True,
                env=os.environ
            )

    except Exception as e:
        os.chdir(_tmp_cwd)
        write_error(f"❌ Error: {e}")
        sys.exit(69)
else:
    write_error(f"❌ Container file folder {container_file_folder} does not exist")
    sys.exit(69)
