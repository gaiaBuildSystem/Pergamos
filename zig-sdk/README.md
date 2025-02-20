## zig-sdk Container

This container is used to build Zig projects using containerized Zig SDK. To share the source code with the container mount bind the workspace that contains the source code to `/source` in the container. Also the user id and group id of the user that runs the container should be passed as environment variables to the container. The user id and group id can be obtained by running `id -u` and `id -g` respectively. The following is an example of how to run the container.

```bash
services:
  zig-sdk-run:
    environment:
      # id -u
      - USID=${USID}
      # id -g
      - GUSID=${GUSID}
    volumes:
      - type: bind
        source: ${PWD}
        target: /source
    image: pergamos/zig-sdk:0.13.0
    command: zig build
```

To install debian packages in the container add a `debian_requirements.txt` in the root of the workspace. The `debian_requirements.txt` should contain the list of debian packages to be installed in the container. The following is an example of a `debian_requirements.txt`.

```txt
build-essential
libgpiod-dev
```
