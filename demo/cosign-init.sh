#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(
    cd "$(dirname "$0")" >/dev/null
    pwd
)"

usage() {
    echo "
Usage:
    ${0##*/} [options]

Optional arguments:
    -d, --debug
        Activate tracing/debug mode.
    -h, --help
        Display this message.

Example:
    ${0##*/} -e private.env -i acs -i quay
" >&2
}

parse_args() {
    PROJECT_DIR="$(
        cd "$(dirname "$SCRIPT_DIR")" >/dev/null
        pwd
    )"
    while [[ $# -gt 0 ]]; do
        case $1 in
        -d | --debug)
            set -x
            DEBUG="--debug"
            export DEBUG
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            usage
            exit 1
            ;;
        esac
        shift
    done
}

init() {
    cd "$PROJECT_DIR"
}

chains() {
    oc get secret -n openshift-pipelines signing-secrets -o jsonpath='{.data.cosign\.pub}' | base64 -d > $SCRIPT_DIR/pac/cosign.pub
    echo "COSIGN_PUB='$SCRIPT_DIR/pac/cosign.pub'"
}

quay() {
    QUAY_HOST="$(oc get route -n rhtap-quay rhtap-quay-quay -o jsonpath="{.spec.host}")"
    QUAY_USER="admin"
    QUAY_PASSWORD="$(oc get secret -n rhtap-quay rhtap-quay-super-user -o jsonpath="{.data.password}" | base64 -d)"
    podman login "$QUAY_HOST" -u "$QUAY_USER" -p "$QUAY_PASSWORD"
    echo "REGISTRY='$QUAY_HOST'"
}

tas() {
    echo "REKOR_SERVER='https://$(oc get route -n rhtap-tas --selector="app.kubernetes.io/name=rekor-server" -o jsonpath="{.items[0].spec.host}")'"
    echo "TUF_MIRROR='https://$(oc get route -n rhtap-tas --selector="app.kubernetes.io/name=tuf" -o jsonpath="{.items[0].spec.host}")'"
}

action() {
    quay
    chains
    tas
}

main() {
    parse_args "$@"
    init
    action
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
