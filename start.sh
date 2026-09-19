#!/bin/bash

: "${REPO:?REPO env var required (format: owner/repo or owner for org runners)}"

cd /home/docker/actions-runner || exit

# Repo-level or org-level runner
if [[ "${REPO}" == */* ]]; then
    API_BASE="repos/${REPO}"
else
    API_BASE="orgs/${REPO}"
fi

gh_api() {
    curl -fsSL -X POST \
        -H "Authorization: Bearer ${GH_PAT}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/$1"
}

# Fetch a fresh registration token via PAT unless REG_TOKEN is provided directly
if [ -z "${REG_TOKEN}" ]; then
    : "${GH_PAT:?GH_PAT or REG_TOKEN env var required}"
    REG_TOKEN=$(gh_api "${API_BASE}/actions/runners/registration-token" | jq -r .token)
fi

# Unique runner name per container so replicas don't collide on GitHub
NAME="${NAME:-$(basename "${REPO}")}"
RUNNER_NAME="${NAME}-$(hostname)"

if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    sudo groupmod -g "$DOCKER_GID" docker 2>/dev/null || true
fi

CONFIG_ARGS="--url https://github.com/${REPO} --token ${REG_TOKEN} --name ${RUNNER_NAME} --unattended --replace"

[ -n "${LABELS}" ]       && CONFIG_ARGS="${CONFIG_ARGS} --labels ${LABELS}"
[ -n "${RUNNER_GROUP}" ] && CONFIG_ARGS="${CONFIG_ARGS} --runnergroup ${RUNNER_GROUP}"
[ -n "${WORK_DIR}" ]     && CONFIG_ARGS="${CONFIG_ARGS} --work ${WORK_DIR}"
[ "${EPHEMERAL}" = "true" ]           && CONFIG_ARGS="${CONFIG_ARGS} --ephemeral"
[ "${DISABLE_AUTO_UPDATE}" = "true" ] && CONFIG_ARGS="${CONFIG_ARGS} --disableupdate"

./config.sh ${CONFIG_ARGS}

cleanup() {
    echo "Removing runner..."
    local token="${REG_TOKEN}"
    if [ -n "${GH_PAT}" ]; then
        token=$(gh_api "${API_BASE}/actions/runners/remove-token" | jq -r .token)
    fi
    ./config.sh remove --unattended --token "${token}"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh & wait $!
