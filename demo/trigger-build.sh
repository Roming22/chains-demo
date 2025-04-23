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
    ${0##*/}
" >&2
}

parse_args() {
    PROJECT_DIR="$(
        cd "$(dirname "$SCRIPT_DIR")" >/dev/null
        pwd
    )"
    while [[ $# -gt 0 ]]; do
        case $1 in
        --chains)
            CHAINS=1
            export CHAINS
            ;;
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

trigger_build() {
    echo "# Repository update"
    date > "$PROJECT_DIR/touch.txt"
    git add "$PROJECT_DIR"
    git commit -m "$COMMIT_MSG"
    git push -f
}

update_pipeline() {
    echo "# Tekton Pipeline configuration"

    oc apply -f "$SCRIPT_DIR/pac/repository.yaml"

    QUAY_HOST="$(oc get route -n rhtap-quay rhtap-quay-quay -o jsonpath="{.spec.host}")"
    IMAGE_OUTPUT="$QUAY_HOST/rhtap/chains:{{revision}}"
    export IMAGE_OUTPUT
    yq -i '.spec.params[3].value=strenv(IMAGE_OUTPUT)' "$PROJECT_DIR/.tekton/docker-push.yaml"

    if [ -n "${CHAINS:-}" ]; then
        cp -rf "$SCRIPT_DIR/pac/with/"* "$PROJECT_DIR/.tekton/"
        COMMIT_MSG="Trigger build with attestation/signature"
    else
        cp -rf "$SCRIPT_DIR/pac/without/"* "$PROJECT_DIR/.tekton/"
        COMMIT_MSG="Trigger build without attestation/signature"
    fi

    echo
}

action() {
    update_pipeline
    trigger_build
}

main() {
    parse_args "$@"
    action
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
