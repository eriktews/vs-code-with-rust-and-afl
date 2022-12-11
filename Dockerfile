# Based on AFL++ 9d9d2cada99b339a25d987de83ca13187a0ab3c2 (stable)
#
# This Dockerfile for AFLplusplus uses Ubuntu 22.04 jammy and
# installs LLVM 14 for afl-clang-lto support.
#
# GCC 11 is used instead of 12 because genhtml for afl-cov doesn't like it.
#

FROM ubuntu:22.04 AS aflplusplus
LABEL "maintainer"="Erik Tews <e.tews@utwente.nl>"
LABEL "about"="VS Code Server with Rust and AFL"

### Comment out to enable these features
# Only available on specific ARM64 boards
ENV NO_CORESIGHT=1
# Possible but unlikely in a docker container
ENV NO_NYX=1

### Only change these if you know what you are doing:
# LLVM 15 does not look good so we stay at 14 to still have LTO
ENV LLVM_VERSION=14
# GCC 12 is producing compile errors for some targets so we stay at GCC 11
ENV GCC_VERSION=11

### No changes beyond the point unless you know what you are doing :)

ARG DEBIAN_FRONTEND=noninteractive

ENV NO_ARCH_OPT=1
ENV IS_DOCKER=1

RUN apt-get update && apt-get full-upgrade -y && \
    apt-get install -y --no-install-recommends wget ca-certificates apt-utils && \
    rm -rf /var/lib/apt/lists/*

RUN echo "deb [signed-by=/etc/apt/keyrings/llvm-snapshot.gpg.key] http://apt.llvm.org/jammy/ llvm-toolchain-jammy-${LLVM_VERSION} main" > /etc/apt/sources.list.d/llvm.list && \
    wget -qO /etc/apt/keyrings/llvm-snapshot.gpg.key https://apt.llvm.org/llvm-snapshot.gpg.key

RUN apt-get update && \
    apt-get -y install --no-install-recommends \
    curl libatomic1 sudo \
    make cmake automake meson ninja-build bison flex \
    git xz-utils bzip2 wget jupp nano bash-completion less vim joe ssh psmisc \
    python3 python3-dev python3-setuptools python-is-python3 \
    libtool libtool-bin libglib2.0-dev \
    apt-transport-https gnupg dialog \
    gnuplot-nox libpixman-1-dev \
    gcc-${GCC_VERSION} g++-${GCC_VERSION} gcc-${GCC_VERSION}-plugin-dev gdb lcov \
    clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} libc++1-${LLVM_VERSION} \
    libc++-${LLVM_VERSION}-dev libc++abi1-${LLVM_VERSION} libc++abi-${LLVM_VERSION}-dev \
    libclang1-${LLVM_VERSION} libclang-${LLVM_VERSION}-dev \
    libclang-common-${LLVM_VERSION}-dev libclang-cpp${LLVM_VERSION} \
    libclang-cpp${LLVM_VERSION}-dev liblld-${LLVM_VERSION} \
    liblld-${LLVM_VERSION}-dev liblldb-${LLVM_VERSION} liblldb-${LLVM_VERSION}-dev \
    libllvm${LLVM_VERSION} libomp-${LLVM_VERSION}-dev libomp5-${LLVM_VERSION} \
    lld-${LLVM_VERSION} lldb-${LLVM_VERSION} llvm-${LLVM_VERSION} \
    llvm-${LLVM_VERSION}-dev llvm-${LLVM_VERSION}-runtime llvm-${LLVM_VERSION}-tools \
    $([ "$(dpkg --print-architecture)" = "amd64" ] && echo gcc-${GCC_VERSION}-multilib gcc-multilib) \
    $([ "$(dpkg --print-architecture)" = "arm64" ] && echo libcapstone-dev) && \
    rm -rf /var/lib/apt/lists/*
    # gcc-multilib is only used for -m32 support on x86
    # libcapstone-dev is used for coresight_mode on arm64

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 0 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} 0 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 0 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 0

#ENV CARGO_HOME=/etc/cargo
#RUN wget -qO- https://sh.rustup.rs | sh -s -- -y -q --no-modify-path
#ENV PATH=$PATH:/etc/cargo/bin

#RUN rustup default stable

RUN cd /tmp; curl -O https://static.rust-lang.org/dist/rust-1.65.0-x86_64-unknown-linux-gnu.tar.gz && tar zxvf rust-1.65.0-x86_64-unknown-linux-gnu.tar.gz && cd rust-1.65.0-x86_64-unknown-linux-gnu && ./install.sh && cd /tmp && rm -rf rust-1.65.0-x86_64-unknown-linux-gnu

ENV LLVM_CONFIG=llvm-config-${LLVM_VERSION}
ENV AFL_SKIP_CPUFREQ=1
# Disable affinity since multiple Docker containers might be running on the same host
# ENV AFL_TRY_AFFINITY=1
ENV AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1

RUN git clone --depth=1 https://github.com/vanhauser-thc/afl-cov && \
    (cd afl-cov && make install) && rm -rf afl-cov

WORKDIR /AFLplusplus
# COPY . .
RUN git clone --depth=1 https://github.com/AFLplusplus/AFLplusplus.git .


ARG CC=gcc-$GCC_VERSION
ARG CXX=g++-$GCC_VERSION

# Used in CI to prevent a 'make clean' which would remove the binaries to be tested
ARG TEST_BUILD

RUN sed -i.bak 's/^	-/	/g' GNUmakefile && \
    make clean && make distrib && \
    ([ "${TEST_BUILD}" ] || (make install && make clean)) && \
    mv GNUmakefile.bak GNUmakefile

# VS Code
ARG RELEASE_TAG="openvscode-server-v1.74.0"
ARG RELEASE_ORG="gitpod-io"
ARG OPENVSCODE_SERVER_ROOT="/home/.openvscode-server"

# Downloading the latest VSC Server release and extracting the release archive
# Rename `openvscode-server` cli tool to `code` for convenience
RUN if [ -z "${RELEASE_TAG}" ]; then \
        echo "The RELEASE_TAG build arg must be set." >&2 && \
        exit 1; \
    fi && \
    arch=$(uname -m) && \
    if [ "${arch}" = "x86_64" ]; then \
        arch="x64"; \
    elif [ "${arch}" = "aarch64" ]; then \
        arch="arm64"; \
    elif [ "${arch}" = "armv7l" ]; then \
        arch="armhf"; \
    fi && \
    wget https://github.com/${RELEASE_ORG}/openvscode-server/releases/download/${RELEASE_TAG}/${RELEASE_TAG}-linux-${arch}.tar.gz && \
    tar -xzf ${RELEASE_TAG}-linux-${arch}.tar.gz && \
    mv -f ${RELEASE_TAG}-linux-${arch} ${OPENVSCODE_SERVER_ROOT} && \
    cp ${OPENVSCODE_SERVER_ROOT}/bin/remote-cli/openvscode-server ${OPENVSCODE_SERVER_ROOT}/bin/remote-cli/code && \
    rm -f ${RELEASE_TAG}-linux-${arch}.tar.gz

ARG USERNAME=openvscode-server
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Creating the user and usergroup
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USERNAME -m -s /bin/bash $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

RUN chmod g+rw /home && \
    mkdir -p /home/workspace && \
    chown -R $USERNAME:$USERNAME /home/workspace && \
    chown -R $USERNAME:$USERNAME ${OPENVSCODE_SERVER_ROOT}

# Rust Analyzer
RUN curl -L https://github.com/rust-lang/rust-analyzer/releases/latest/download/rust-analyzer-x86_64-unknown-linux-gnu.gz | gunzip -c - > /usr/local/bin/rust-analyzer && chmod +x /usr/local/bin/rust-analyzer

# Rust source code (needed for analyzer)
RUN cd /tmp; curl -O https://static.rust-lang.org/dist/rustc-1.65.0-src.tar.gz && tar zxf rustc-1.65.0-src.tar.gz && cd rustc-1.65.0-src && mkdir -p /usr/local/lib/rustlib/src/rust/library/ && mkdir -p /usr/local/lib/rustlib/src/rust/src/llvm-project/ && cp -r src/llvm-project /usr/local/lib/rustlib/src/rust/src/ && cp -r library /usr/local/lib/rustlib/src/rust/ && cp Cargo.lock /usr/local/lib/rustlib/src/rust/ && cd .. && rm -rf rustc-1.65.0-src rustc-1.65.0-src.tar.gz

USER $USERNAME

WORKDIR /home/workspace/

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/workspace \
    EDITOR=code \
    VISUAL=code \
    GIT_EDITOR="code --wait" \
    OPENVSCODE_SERVER_ROOT=${OPENVSCODE_SERVER_ROOT}

# VS Code Plugin
RUN cd /tmp/; curl -L https://github.com/rust-lang/rust-analyzer/releases/download/2022-12-05/rust-analyzer-linux-x64.vsix > /tmp/rust-analyzer-linux-x64.vsix && ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --install-extension /tmp/rust-analyzer-linux-x64.vsix && rm /tmp/rust-analyzer-linux-x64.vsix
RUN cd /tmp; curl -L -o cmake-tools.vsix  https://github.com/microsoft/vscode-cmake-tools/releases/download/v1.12.27/cmake-tools.vsix; ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --install-extension cmake-tools.vsix; rm cmake-tools.vsix
RUN cd /tmp/; curl -L -o cpptools-linux.vsix https://github.com/microsoft/vscode-cpptools/releases/download/v1.13.7/cpptools-linux.vsix; ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --install-extension cpptools-linux.vsix; rm cpptools-linux.vsix
RUN cd /tmp/; curl -L -o codelldb-x86_64-linux.vsix https://github.com/vadimcn/vscode-lldb/releases/download/v1.8.1/codelldb-x86_64-linux.vsix; ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --install-extension codelldb-x86_64-linux.vsix; rm codelldb-x86_64-linux.vsix
RUN mkdir -p .openvscode-server/data/Machine/; echo ' {"rust-analyzer.server.path": "/usr/local/bin/rust-analyzer" }' > .openvscode-server/data/Machine/settings.json


RUN echo "set encoding=utf-8" > /home/workspace/.vimrc && \
    echo ". /etc/bash_completion" >> /home/workspace/.bashrc && \
    echo 'alias joe="joe --wordwrap --joe_state -nobackup"' >> /home/workspace/.bashrc && \
    echo "export PS1='"'[afl++  and rust\h] \w$(__git_ps1) \$ '"'" >> /home/workspace/.bashrc

ENTRYPOINT [ "/bin/sh", "-c", "exec ${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server --host 0.0.0.0 \"${@}\"", "--" ]