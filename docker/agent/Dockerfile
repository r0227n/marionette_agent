FROM ubuntu:24.04

ARG FLUTTER_VERSION=3.47.2
ARG FLUTTER_REVISION=d3b14c876900e553bc736ca19295fc09e3853e8e
ARG GTR_VERSION=2.11.0
ARG CODEX_VERSION=0.154.0

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl file git jq nodejs npm openssh-client \
    patch procps ripgrep rsync unzip xz-utils zip libglu1-mesa \
    clang cmake ninja-build pkg-config libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "v${GTR_VERSION}" \
      https://github.com/coderabbitai/git-worktree-runner.git /opt/git-gtr \
    && ln -s /opt/git-gtr/bin/git-gtr /usr/local/bin/git-gtr \
    && npm install -g "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force

RUN useradd --create-home --uid 10001 --shell /bin/bash agent \
    && git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter \
    && test "$(git -C /opt/flutter rev-parse HEAD)" = "${FLUTTER_REVISION}" \
    && chown -R agent:agent /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}" \
    PUB_CACHE=/home/agent/.pub-cache \
    CI=true
USER agent
WORKDIR /home/agent
RUN flutter config --no-analytics \
    && dart --disable-analytics \
    && flutter precache --linux \
    && flutter --version \
    && git gtr --version \
    && codex --version

CMD ["bash"]
