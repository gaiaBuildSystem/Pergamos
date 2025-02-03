# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring
import os
import json
import base64
import subprocess

def binfmt():
    _ret = subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "--privileged",
            "pergamos/binfmt:9.0.2"
        ],
        check=True,
        env=os.environ
    )

    if _ret.returncode != 0:
        raise RuntimeError("Docker binfmt failed")


def buildx_multi_arch_setup():
    # check if the buildx is already created
    _ret = subprocess.run(
        [
            "docker",
            "buildx",
            "inspect",
            "multiarch"
        ],
        check=False,
        capture_output=True,
        env=os.environ
    )

    if "multiarch" in _ret.stdout.decode():
        print("Buildx already created")
        return

    _ret = subprocess.run(
        [
            "docker",
            "buildx",
            "create",
            "--name",
            "multiarch",
            "--driver",
            "docker-container",
            "--use"
        ],
        check=True,
        env=os.environ
    )

    if _ret.returncode != 0:
        raise RuntimeError("Docker buildx create failed")


def buildx_build_native(
        docker_image,
        docker_compose,
        push=False,
        no_cache=False
    ):
    archs = f"linux/{os.uname().machine}"

    # check if the repository already exists
    _ret = subprocess.run(
        [
            "docker",
            "manifest",
            "inspect",
            f"{docker_image}"
        ],
        check=False,
        capture_output=True,
        env=os.environ
    )

    if "no such manifest" in _ret.stderr.decode():
        print("Repository not found, creating ...")

        buildx_build(
            docker_compose=docker_compose,
            archs=archs,
            push=push,
            no_cache=no_cache
        )
    else:
        print(f"Repository found, appending for {archs}")

        buildx_build(
            docker_compose=docker_compose,
            archs=archs,
            native=True,
            push=False,
            no_cache=no_cache
        )

        # re-tag
        _cmd_list = [
            "docker",
            "tag",
            f"{docker_image}",
            f"{docker_image}-{os.uname().machine}"
        ]

        print(f"Running command: {' '.join(_cmd_list)}")

        _ret = subprocess.run(
            _cmd_list,
            check=False,
            env=os.environ
        )

        if _ret.returncode != 0:
            raise RuntimeError("Docker tag for append failed")

        if push:
            _cmd_push_list = [
                "docker",
                "push",
                f"{docker_image}-{os.uname().machine}"
            ]

            print(f"Running command: {' '.join(_cmd_push_list)}")

            _ret = subprocess.run(
                _cmd_push_list,
                check=True,
                env=os.environ
            )

            if _ret.returncode != 0:
                raise RuntimeError("Docker push for append failed")

            _cmd_append_list = [
                "docker",
                "buildx",
                "imagetools",
                "create",
                "--append",
                "-t", f"{docker_image}", f"{docker_image}-{os.uname().machine}"
            ]

            print(f"Running command: {' '.join(_cmd_append_list)}")

            _ret = subprocess.run(
                _cmd_append_list,
                check=True,
                env=os.environ
            )

            if _ret.returncode != 0:
                raise RuntimeError("Docker buildx create append failed")


def buildx_build(
        docker_compose,
        archs,
        native=False,
        push=False,
        no_cache=False
    ):
    if native:
        archs = f"linux/{os.uname().machine}"
        print(f"Building for native architecture {archs}")

    _cmd_list = [
        "docker",
        "buildx",
        "bake",
        "-f", f"{docker_compose}",
        "--set", f"*.platform={archs}",
        "--load",
        "--push" if push else None,
        "--no-cache" if no_cache else None
    ]

    # Remove all None entries from the command list
    _cmd_list = list(filter(None, _cmd_list))

    print(f"Running command: {' '.join(_cmd_list)}")

    _ret = subprocess.run(
        _cmd_list,
        check=True,
        env=os.environ
    )

    if _ret.returncode != 0:
        raise RuntimeError("Docker buildx bake failed")


def __get_sec(name):
    # check if the name is already set in the environment vars
    if os.getenv(name):
        return os.getenv(name)

    script_path = os.path.dirname(os.path.abspath(__file__))
    sec_path = os.path.join(script_path, "../.sec", name)

    if os.path.exists(sec_path):
        with open(sec_path, 'r', encoding="utf-8") as file:
            return file.read().strip()

    # I will not create an exception type only for this, so
    # pylint: disable=broad-exception-raised
    raise Exception(f"Secret {name} not found")


def docker_registry_login():
    registry_username = os.getenv("REGISTRY_USERNAME", "gaiaproject")
    registry_password = __get_sec("DOCKERHUB_TOKEN")

    # token to base64
    registry_password_b64 = base64.b64encode(
        (f"{registry_username}:{registry_password}").encode("utf-8")
    ).decode("utf-8")

    # create the ~/.docker/config.json file
    config = {
        "auths": {
            "https://index.docker.io/v1/": {
                "auth": registry_password_b64
            }
        }
    }

    # create the ~/.docker/config.json file
    with open(
        file=os.path.expanduser("~/.docker/config.json"),
        encoding="utf-8",
        mode="w"
    ) as file:
        json.dump(config, file)

    _ret = subprocess.run(
        [
            "docker",
            "login"
        ],
        text=True,
        check=True,
        env=os.environ
    )

    if _ret.returncode != 0:
        raise PermissionError("Docker login failed")
