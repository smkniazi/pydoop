#!/bin/bash
#
# Build pydoop inside the Hopsworks 5.0 base-image environment (Ubuntu 22.04, Miniconda
# python 3.12.13, setuptools 80.10.2, openjdk-8-jre, libhdfs-golang) and export the sdist,
# a cp312 linux_x86_64 wheel and BUILD-INFO.txt to ./dist.
#
# A build done directly on a developer machine is not portable to the clusters (different
# glibc / compiler / python); this one is, because it runs in the same environment as
# docker-images branch-5.0 base-image/python-feature-pipeline.
#
# Nothing is pushed: no image is tagged for a registry and no upload happens.
#
# Usage: docker/hopsworks-5.0/build.sh [options]
#   -e, --env-image IMG    build inside an existing hopsworks-base image instead of replicating
#                          the environment from ubuntu:22.04, e.g.
#                          docker.hops.works/hopsworks/hopsworks-base:python-feature-pipeline-5.0.6
#   -o, --out DIR          output directory (default: <repo>/dist)
#   -s, --suffix SUFFIX    artifact name suffix, pydoop-<VERSION>-<SUFFIX>.tar.gz (default: go-and-java,
#                          the name python_install.sh fetches from repo.hops.works)
#       --hadoop-version V libhdfs-golang version to smoke-test against (default: 3.4.3.1-EE-RC5,
#                          as in branch-5.0 core_install.sh)
#       --no-cache         pass --no-cache to docker build
#   -h, --help
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKERFILE="${REPO_ROOT}/docker/hopsworks-5.0/Dockerfile"

ENV_IMAGE=""
OUT_DIR="${REPO_ROOT}/dist"
SUFFIX="go-and-java"
HADOOP_VERSION_EE="3.4.3.1-EE-RC5"
NO_CACHE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -e|--env-image) ENV_IMAGE="$2"; shift 2 ;;
        -o|--out) OUT_DIR="$2"; shift 2 ;;
        -s|--suffix) SUFFIX="$2"; shift 2 ;;
        --hadoop-version) HADOOP_VERSION_EE="$2"; shift 2 ;;
        --no-cache) NO_CACHE="--no-cache"; shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

GIT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "WARNING: working tree has uncommitted changes; artifacts will be labelled ${GIT_SHA}-dirty" >&2
    GIT_SHA="${GIT_SHA}-dirty"
fi

# Keep the vendored env.yml honest if a docker-images checkout is around.
DOCKER_IMAGES_ENV_YML="${DOCKER_IMAGES_DIR:-${REPO_ROOT}/../../docker-images}/base-image/internal-base/env.yml"
if [ -f "${DOCKER_IMAGES_ENV_YML}" ] && ! cmp -s "${DOCKER_IMAGES_ENV_YML}" "${REPO_ROOT}/docker/hopsworks-5.0/env.yml"; then
    echo "WARNING: docker/hopsworks-5.0/env.yml differs from ${DOCKER_IMAGES_ENV_YML}" >&2
    echo "         (is docker-images on branch-5.0? if so, copy it over and rebuild)" >&2
fi

ARGS=(
    --build-arg "ARTIFACT_SUFFIX=${SUFFIX}"
    --build-arg "GIT_SHA=${GIT_SHA}"
    --build-arg "HADOOP_VERSION_EE=${HADOOP_VERSION_EE}"
)
if [ -n "${ENV_IMAGE}" ]; then
    ARGS+=(--build-arg "ENV_IMAGE=${ENV_IMAGE}")
    echo "Building pydoop ${GIT_SHA} inside ${ENV_IMAGE}"
else
    echo "Building pydoop ${GIT_SHA} inside a replica of docker-images branch-5.0 python-feature-pipeline"
fi

mkdir -p "${OUT_DIR}"
DOCKER_BUILDKIT=1 docker build \
    ${NO_CACHE} \
    --progress=plain \
    --file "${DOCKERFILE}" \
    --target artifacts \
    --output "type=local,dest=${OUT_DIR}" \
    "${ARGS[@]}" \
    "${REPO_ROOT}"

echo
echo "Artifacts in ${OUT_DIR}:"
ls -la "${OUT_DIR}"
echo
cat "${OUT_DIR}/BUILD-INFO.txt"
