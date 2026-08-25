# syntax=docker/dockerfile:1
#
# Build pydoop the way the Hopsworks 5.0 base images build it.
#
# Mirrors docker-images branch-5.0:
#   base-image/internal-base/Dockerfile + python_install.sh + core_install.sh
#   base-image/python-feature-pipeline/Dockerfile + python_install.sh
#
# Stages
#   hopsworks-env  Ubuntu 22.04 + the apt packages of internal-base, Miniconda3-py312_24.7.1-0,
#                  the conda env from env.yml (python 3.12.13, setuptools 80.10.2, pip 25.3),
#                  openjdk-8-jre as JAVA_HOME, libhdfs-golang. No Hadoop binaries, no JDK.
#   builder        Copies this source tree, makes the sdist, installs it with
#                  `pip install --no-build-isolation <sdist>` (as python_install.sh does),
#                  builds a wheel from the same sdist and smoke-tests the native modules.
#   artifacts      Just the files to export (use `docker build --output`).
#
# ENV_IMAGE can be pointed at a real base image instead of the replicated one, e.g.
#   --build-arg ENV_IMAGE=docker.hops.works/hopsworks/hopsworks-base:python-feature-pipeline-5.0.6
# in which case the hopsworks-env stage is skipped entirely.
#
# Nothing here pushes anything anywhere.

ARG ENV_IMAGE=hopsworks-env

# --------------------------------------------------------------------------------------------------
# hopsworks-env: replicate internal-base + python-feature-pipeline (branch-5.0)
# --------------------------------------------------------------------------------------------------
FROM ubuntu:22.04 AS hopsworks-env

# internal-base/Dockerfile apt list, verbatim (node/npm left out, irrelevant for pydoop).
# python-feature-pipeline/Dockerfile adds openjdk-8-jre. libtirpc-dev comes with libc6-dev.
RUN echo "debconf debconf/frontend select noninteractive" | debconf-set-selections && \
    echo 'APT::Get::Assume-Yes "true";' | tee /etc/apt/apt.conf.d/99assume_yes && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install wget && \
    apt-get install \
    net-tools curl \
    wget \
    build-essential \
    libcurl3-dev \
    sudo \
    git \
    libfreetype6-dev \
    libjpeg-dev \
    libpng-dev \
    libsndfile1 \
    libzmq3-dev \
    pkg-config \
    python3-dev \
    python3-numpy \
    python3-pip \
    software-properties-common \
    swig \
    zip \
    zlib1g-dev \
    libstdc++6 \
    libkrb5-dev \
    libsasl2-dev \
    libpq-dev \
    fuse3 \
    protobuf-c-compiler \
    unixodbc-dev \
    vim \
    openjdk-8-jre \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# internal-base/Dockerfile ENV block
ENV ANACONDA_HOME=/srv/hops/anaconda
ENV HOME=/srv/hops/anaconda
ENV BASE_ENV=${ANACONDA_HOME}/envs/hopsworks_environment
ENV C_INCLUDE_PATH=${BASE_ENV}/include
ENV CPLUS_INCLUDE_PATH=${BASE_ENV}/include
ENV PATH=${BASE_ENV}/bin:${ANACONDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${BASE_ENV}/lib:${LD_LIBRARY_PATH}
ENV LANG=C.UTF-8
ENV HADOOP_HOME=/srv/hops/hadoop
ENV PATH=${HADOOP_HOME}/bin:${PATH}

WORKDIR ${ANACONDA_HOME}

# internal-base/python_install.sh: Miniconda + conda env from env.yml
ARG MINICONDA_INSTALLER=Miniconda3-py312_24.7.1-0-Linux-x86_64.sh
COPY docker/hopsworks-5.0/env.yml ./
RUN mkdir -p /srv/hops && chmod -R 777 ${ANACONDA_HOME} && \
    curl -LO https://repo.anaconda.com/miniconda/${MINICONDA_INSTALLER} && \
    bash ${MINICONDA_INSTALLER} -p ${ANACONDA_HOME} -b -f && \
    conda config --set auto_update_conda False && \
    conda clean -afy && \
    rm ${MINICONDA_INSTALLER} && \
    CFLAGS='-I/usr/include/tirpc' CXXFLAGS='-I/usr/include/tirpc' conda env create -f ./env.yml && \
    rm ${BASE_ENV}/lib/libtinfo.so.6 && \
    ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 ${BASE_ENV}/lib/libtinfo.so.6 && \
    conda clean -afy && \
    rm ./env.yml

# internal-base/core_install.sh, INSTALL_HADOOP_BINARIES=false branch: libhdfs-golang only.
# Not needed to compile pydoop (hdfs* symbols stay undefined in native_core_hdfs.so); it is
# what resolves them at runtime, so the builder stage uses it to smoke-test the result.
ARG HADOOP_VERSION_EE=3.4.3.1-EE-RC5
RUN wget -q https://repo.hops.works/master/libhdfs/libhdfs-golang-${HADOOP_VERSION_EE}.tar.gz && \
    mkdir -p /usr/local/bin/libhdfs-golang && \
    tar -C /usr/local/bin/libhdfs-golang -zxf libhdfs-golang-${HADOOP_VERSION_EE}.tar.gz && \
    rm libhdfs-golang-${HADOOP_VERSION_EE}.tar.gz

# python-feature-pipeline/Dockerfile
ENV JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64
ENV LD_LIBRARY_PATH=${JAVA_HOME}/jre/lib/amd64/server:${LD_LIBRARY_PATH}

# --------------------------------------------------------------------------------------------------
# builder: sdist -> install like python_install.sh -> wheel -> smoke test
# --------------------------------------------------------------------------------------------------
FROM ${ENV_IMAGE} AS builder

ARG ARTIFACT_SUFFIX=go-and-java
ARG GIT_SHA=unknown

# python-feature-pipeline/python_install.sh
ENV CFLAGS='-I/usr/include/tirpc'
ENV CXXFLAGS='-I/usr/include/tirpc'

WORKDIR /build/pydoop
COPY . .

RUN set -eux; \
    rm -rf build dist pydoop.egg-info pydoop/config.py pydoop/version.py; \
    VERSION="$(cat VERSION)"; \
    SDIST="pydoop-${VERSION}-${ARTIFACT_SUFFIX}.tar.gz"; \
    "${BASE_ENV}/bin/python" setup.py -q sdist; \
    mv "dist/pydoop-${VERSION}.tar.gz" "dist/${SDIST}"; \
    # 1) exactly what python-feature-pipeline/python_install.sh runs against repo.hops.works
    "${BASE_ENV}/bin/pip" install --no-build-isolation "dist/${SDIST}"; \
    # 2) a plain `pip install <sdist>`: pip builds in an isolated env with the *latest*
    #    setuptools (>=81, no pkg_resources), which is how people install it by hand
    "${BASE_ENV}/bin/pip" install --force-reinstall --no-deps "dist/${SDIST}"; \
    # a binary wheel from the same sdist, for dropping straight into a running 5.0 pod
    "${BASE_ENV}/bin/pip" wheel --no-build-isolation --no-deps -w dist "dist/${SDIST}"; \
    "${BASE_ENV}/bin/pip" check

# Smoke test from outside the source tree (so `import pydoop` resolves to the installed package).
# libhdfs-golang provides the hdfs* symbols, as jupyter-launcher.sh arranges in the real image.
WORKDIR /
RUN set -eux; \
    "${BASE_ENV}/bin/python" -c 'import pydoop.sercore'; \
    LD_PRELOAD=/usr/local/bin/libhdfs-golang/libhdfs.so "${BASE_ENV}/bin/python" -c '\
import pydoop, pydoop.hdfs, pydoop.native_core_hdfs as n; \
print("pydoop", pydoop.__version__ if hasattr(pydoop, "__version__") else "", "from", pydoop.__file__); \
print("native_core_hdfs", n.__file__); \
assert hasattr(n, "CoreHdfsFs")'; \
    # as in the deployed build: hdfs* must be undefined (resolved by libhdfs-golang), not linked to libjvm
    SO="$(find "${BASE_ENV}/lib" -name 'native_core_hdfs*.so' | head -1)"; \
    nm -D --undefined-only "${SO}" | grep -q ' U hdfsGetPathInfo'; \
    ! ldd "${SO}" | grep -q libjvm; \
    { echo "git_sha=${GIT_SHA}"; \
      echo "python=$("${BASE_ENV}/bin/python" -V)"; \
      echo "setuptools=$("${BASE_ENV}/bin/python" -c 'import setuptools; print(setuptools.__version__)')"; \
      echo "gcc=$(gcc -dumpfullversion)"; \
      echo "glibc=$(ldd --version | head -1 | awk '{print $NF}')"; \
      . /etc/os-release && echo "os=${PRETTY_NAME}"; \
      echo "libhdfs_golang=$(ls /usr/local/bin/libhdfs-golang/ | grep -o 'libhdfs-golang-[^-]*-EE-[A-Za-z0-9]*' | head -1)"; \
      echo; cd /build/pydoop/dist && sha256sum ./*.tar.gz ./*.whl; \
    } > /build/pydoop/dist/BUILD-INFO.txt; \
    cat /build/pydoop/dist/BUILD-INFO.txt

# --------------------------------------------------------------------------------------------------
# artifacts: what `docker build --output type=local,dest=DIR` exports
# --------------------------------------------------------------------------------------------------
FROM scratch AS artifacts
COPY --from=builder /build/pydoop/dist/ /
