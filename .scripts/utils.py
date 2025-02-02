# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring
import os

def env(name, default):
    return os.getenv(name, default)
