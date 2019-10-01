#!/usr/bin/env python3

import argparse
import os
import subprocess
import sys


def run(*args):
    # Add wrappers to $PATH
    env = os.environ.copy()
    env["PATH"] += ":%s" % os.environ["SNAP"]

    result = subprocess.run(
        args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )

    try:
        result.check_returncode()
    except subprocess.CalledProcessError as err:
        if result.stderr:
            print(result.stderr.decode("utf-8"))
        print(err)
        sys.exit(1)

    return result.stdout.decode("utf-8")


def main():
    # Get rid of empty `''` argument if nothing was passed in by enable wrapper
    sys.argv = [a for a in sys.argv if a]

    parser = argparse.ArgumentParser(description="Disable kubeflow in microk8s.")
    parser.add_argument("--controller", default="uk8s", help="Juju controller name")
    args = parser.parse_args()

    run(
        "microk8s-juju.wrapper",
        "destroy-controller",
        "-y",
        args.controller,
        "--destroy-all-models",
        "--destroy-storage",
    )


if __name__ == "__main__":
    main()
