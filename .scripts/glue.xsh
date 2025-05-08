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

# echo arguments
args = parser.parse_args()
container_file_folder = args.container_file_folder

write_log(f"\nContainer file folder: {container_file_folder}")

# debug.__breakpoint()

if container_file_folder is None:
    write_error("\n❌ Container file folder is required\n")
    exit(500)

# register the foreign architectures
dockerutils.binfmt()
dockerutils.buildx_multi_arch_setup()
dockerutils.docker_registry_login()

container_file_folder_path = Path(container_file_folder)


def __fixup_arch(arch):
    if arch == 'amd64':
        return 'x86_64'
    elif arch == 'arm64':
        return 'aarch64'
    elif arch == 'armhf':
        return 'armv7l'
    elif arch == 'i386':
        return 'i686'
    elif arch == 'ppc64le':
        return 'ppc64le'
    else:
        return arch


if container_file_folder_path.exists():
    $CONTAINER_IMAGE_NAME = container_file_folder_path.parent.name

    # Read metadata
    with open(container_file_folder_path / 'args.json') as f:
        metadata = json.load(f)

    # Check if this is the right script to build it
    if not metadata.get('multiarch', False):
        write_error("This project is not gluable with this script", file=sys.stderr)
        sys.exit(69)

    $IMAGE_VERSION = metadata['version']
    $REGISTRY = metadata['registry']
    $IMAGE_REGISTRY = metadata['registry']
    $IMAGE_NAME = f"/{metadata['image']}"
    IMAGES_TO_GLUE = []

    for args in metadata['machines']:
        # Get all archs
        for arch in args['arch']:
            _arch = __fixup_arch(arch)
            IMAGES_TO_GLUE.append(f"{os.environ['REGISTRY']}{os.environ['IMAGE_NAME']}:{os.environ['IMAGE_VERSION']}-{_arch}")
            print(f"\tImage: {IMAGES_TO_GLUE[-1]}")

    print("")

    for img in IMAGES_TO_GLUE:
        write_info(f"Pulling -> {img}")
        docker pull @(img)

    # Glue the images
    write_info(f"Glues -> {IMAGES_TO_GLUE}")
    dockerutils.docker_manifest_glue(
        images=IMAGES_TO_GLUE,
        to_image=f"{os.environ['REGISTRY']}{os.environ['IMAGE_NAME']}:{os.environ['IMAGE_VERSION']}"
    )

else:
    write_error(f"{container_file_folder} does not exist")
    exit(404)
