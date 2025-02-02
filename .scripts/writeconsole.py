# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring
from colorama import init, Fore, Back # type: ignore

# init colorama
init(autoreset=True)

def write (
    fore_color = Fore.WHITE,
    back_color = Back.BLACK,
    message = "Hello, World!"
):
    print(fore_color + back_color + message)

def write_log (
    message
):
    write(Fore.WHITE, Back.WHITE, message)

def write_info (
    message
):
    write(Fore.BLACK, Back.BLUE, message)

def write_warning (
    message
):
    write(Fore.BLACK, Back.YELLOW, message)

def write_error (
    message
):
    write(Fore.RED, Back.RESET, message)

def write_success (
    message
):
    write(Fore.BLACK, Back.GREEN, message)
