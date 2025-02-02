# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring
import debugpy # type: ignore

DEBUG_INITIALIZED = False

def __init():
    print("__debugpy__")
    debugpy.listen(("0.0.0.0", 5678))
    print("__debugpy__ go")
    debugpy.wait_for_client()

def __breakpoint():
    # pylint: disable=global-statement
    global DEBUG_INITIALIZED

    if not DEBUG_INITIALIZED:
        __init()
        DEBUG_INITIALIZED = True

    debugpy.breakpoint()
