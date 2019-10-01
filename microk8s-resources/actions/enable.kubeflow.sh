#!/usr/bin/env python3

import argparse
import json
import os
import random
import string
import subprocess
import sys
import tempfile
import textwrap
import time


def run(*args, die=True):
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
        if die:
            if result.stderr:
                print(result.stderr.decode("utf-8"))
            print(err)
            sys.exit(1)
        else:
            raise

    return result.stdout.decode("utf-8")


def get_random_pass():
    return "".join(
        random.choice(string.ascii_uppercase + string.digits) for _ in range(30)
    )


def main():
    # Get rid of empty `''` argument if nothing was passed in by enable wrapper
    sys.argv = [a for a in sys.argv if a]

    parser = argparse.ArgumentParser(description="Enable kubeflow in microk8s.")
    parser.add_argument("--controller", default="uk8s", help="Juju controller name")
    parser.add_argument(
        "--model", default="kubeflow", help="Juju model name / Kubernetes namespace"
    )
    parser.add_argument("--channel", default="stable", help="Kubeflow channel")
    args = parser.parse_args()

    try:
        password = os.environ["KUBEFLOW_AUTH_PASSWORD"]
    except KeyError:
        password = get_random_pass()

    password_overlay = {
        "applications": {
            "ambassador-auth": {"options": {"password": password}},
            "katib-db": {"options": {"root-password": get_random_pass()}},
            "mariadb": {"options": {"root-password": get_random_pass()}},
            "pipelines-api": {"options": {"minio-secret-key": "minio123"}},
        }
    }

    for service in ["dns", "storage", "dashboard", "juju"]:
        print("Enabling %s..." % service)
        run("microk8s-enable.wrapper", service)

        for _ in range(12):
            try:
                run("microk8s-status.wrapper", "--wait-ready", die=False)
                break
            except subprocess.CalledProcessError:
                print("Waiting for %s to become ready..." % service)
                time.sleep(5)
        else:
            print("\033[91mWaited too long for %s to become ready!\033[0m" % service)
            sys.exit(1)

    controllers = json.loads(
        run("microk8s-juju.wrapper", "list-controllers", "--format=json")
    )

    if args.controller in (controllers["controllers"] or {}):
        print(
            "The controller %s already exists. Run `microk8s.disable kubeflow` to remove it."
            % args.controller
        )
        sys.exit(1)

    print("Deploying Kubeflow...")
    run("microk8s-juju.wrapper", "bootstrap", "microk8s", args.controller)
    run("microk8s-juju.wrapper", "add-model", args.model, "microk8s")
    cluster_roles = "https://raw.githubusercontent.com/juju-solutions/bundle-kubeflow/pod-spec-set-v2/resources/cluster-roles.yaml"
    run("microk8s-kubectl.wrapper", "apply", "-n", args.model, "-f", cluster_roles)

    with tempfile.NamedTemporaryFile("w+") as f:
        json.dump(password_overlay, f)
        f.flush()

        run(
            "microk8s-juju.wrapper",
            "deploy",
            "kubeflow",
            "--channel",
            args.channel,
            "--overlay",
            f.name,
        )

    run(
        "microk8s-juju.wrapper",
        "config",
        "ambassador",
        "juju-external-hostname=localhost",
    )

    status = run(
        "microk8s-juju.wrapper",
        "status",
        "-m",
        "%s:%s" % (args.controller, args.model),
        "--format=json",
    )
    status = json.loads(status)
    ambassador_ip = status["applications"]["ambassador"]["units"]["ambassador/0"][
        "address"
    ]

    print(
        textwrap.dedent(
            """
    Congratulations, Kubeflow is now available.
    The dashboard is available at http://%s/
    To tear down Kubeflow and associated infrastructure, run:

       microk8s.disable kubeflow
    """
            % ambassador_ip
        )
    )


if __name__ == "__main__":
    main()
