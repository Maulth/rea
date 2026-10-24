# REA in a container: the CLI/MCP server built from this checkout plus every
# Linux-capable optional provider, pinned to the versions REA documents as
# verified. Not included: IDA and JEB (bring-your-own commercial), Cutter (GUI),
# and macOS-only Swift/LLDB tooling.
#
#   docker build -t rea:local .
#   docker run -i --rm -v rea-state:/home/node/.rea -v /path/to/targets:/targets:ro rea:local mcp
#
# Live instrumentation of host (Windows) processes goes through a frida-server
# running on the host; see docker/README.md.

ARG NODE_VERSION=24.18.0

# --- Build REA from source -------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS build
WORKDIR /src
ENV HUSKY=0
COPY package.json package-lock.json .npmrc .nvmrc ./
COPY scripts/prepare.mjs scripts/
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build:cached \
 && npm prune --omit=dev --no-audit --no-fund

# --- Binwalk 3.1.0 (no prebuilt Linux release) -----------------------------
FROM rust:1-bookworm AS binwalk
RUN apt-get update \
 && apt-get install -y --no-install-recommends libfontconfig1-dev liblzma-dev libbz2-dev \
 && rm -rf /var/lib/apt/lists/*
RUN cargo install --locked binwalk --version 3.1.0 --root /opt/binwalk

# --- Digest-verified downloads ---------------------------------------------
FROM debian:bookworm-slim AS fetch
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip xz-utils git \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /dl
# fetch URL SHA256 FILE: download and verify; an empty digest skips the check
# (Rizin publishes none).
RUN printf '#!/bin/sh\nset -e\ncurl -fsSL "$1" -o "$3"\n[ -z "$2" ] || echo "$2  $3" | sha256sum -c -\n' > /usr/local/bin/fetch \
 && chmod +x /usr/local/bin/fetch

RUN fetch https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip \
      ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db ghidra.zip \
 && unzip -q ghidra.zip -d /opt && mv /opt/ghidra_* /opt/ghidra && rm ghidra.zip

RUN fetch https://github.com/Noelo-Lab/kuna/releases/download/v1.833/kuna-v1.833-linux-x86_64.tar.gz \
      e9f047fb5a93925ede6d869df22c26c1c0ced90764ace7467ae90f880625d530 kuna.tgz \
 && mkdir -p /opt/kuna && tar -xzf kuna.tgz -C /opt/kuna --strip-components=1 && rm kuna.tgz

RUN fetch https://github.com/rizinorg/rizin/releases/download/v0.7.4/rizin-v0.7.4-static-x86_64.tar.xz "" rizin.txz \
 && mkdir -p /opt/rizin && tar -xJf rizin.txz -C /opt/rizin && rm rizin.txz

RUN fetch https://github.com/WebAssembly/wabt/releases/download/1.0.42/wabt-1.0.42-linux-x64.tar.gz \
      84895407a6bbb80e918f33b16b2fb2206021c150b6bc9ff6f761263a745ab131 wabt.tgz \
 && tar -xzf wabt.tgz -C /opt && mv /opt/wabt-1.0.42 /opt/wabt && rm wabt.tgz

RUN mkdir -p /opt/jadx \
 && fetch https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar \
      6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75 /opt/jadx/jadx-headless-mcp-0.7.1-all.jar

RUN mkdir -p /opt/apktool \
 && fetch https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar \
      dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423 /opt/apktool/apktool.jar \
 && printf '#!/bin/sh\nexec java -jar /opt/apktool/apktool.jar "$@"\n' > /opt/apktool/apktool \
 && chmod +x /opt/apktool/apktool

RUN fetch https://dl.google.com/android/repository/platform-tools-latest-linux.zip "" pt.zip \
 && unzip -q pt.zip -d /opt && rm pt.zip

RUN fetch https://github.com/pionxzh/wakaru/releases/download/v1.14.0/wakaru-linux-x64.tar.gz "" wakaru.tgz \
 && mkdir -p /opt/wakaru && tar -xzf wakaru.tgz -C /opt/wakaru && rm wakaru.tgz

RUN fetch https://downloads.mitmproxy.org/12.2.3/mitmproxy-12.2.3-linux-x86_64.tar.gz "" mitm.tgz \
 && mkdir -p /opt/mitmproxy && tar -xzf mitm.tgz -C /opt/mitmproxy && rm mitm.tgz

RUN git clone --depth 1 --branch 2026.09.15 https://github.com/pwndbg/pwndbg.git /opt/pwndbg

FROM node:${NODE_VERSION}-bookworm-slim AS node

# --- Runtime ---------------------------------------------------------------
# Ubuntu 24.04 rather than Debian: REA's automated Hopper installer supports
# Ubuntu 24.04+ but not Debian.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && userdel -r ubuntu \
 && useradd -m -u 1000 -s /bin/bash node
# procps: REA's process supervisor needs a procps-compatible `ps` on Linux.
# The rest are extractors Unblob and Binwalk call from PATH.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      procps util-linux ca-certificates python3 python3-venv python3-dev \
      build-essential git binutils gdb tshark sigrok-cli cc65 strace file \
      e2fsprogs p7zip-full unar lz4 lzop zstd xz-utils squashfs-tools \
      cpio cabextract mtd-utils libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=eclipse-temurin:21-jdk /opt/java/openjdk /opt/java/openjdk
COPY --from=fetch /opt/ /opt/
COPY --from=binwalk /opt/binwalk/bin/binwalk /usr/local/bin/binwalk
ENV JAVA_HOME=/opt/java/openjdk \
    PATH=/opt/java/openjdk/bin:/opt/platform-tools:/opt/wabt/bin:/opt/rizin/bin:/opt/apktool:$PATH

# Python tool environments, each isolated as REA expects.
RUN python3 -m venv /opt/pwntools \
 && /opt/pwntools/bin/pip install --no-cache-dir pwntools==4.15.0 pyelftools==0.33 unicorn==2.1.2 \
 && python3 -m venv /opt/unblob \
 && /opt/unblob/bin/pip install --no-cache-dir unblob==26.6.4 \
 && python3 -m venv /opt/pwndbg/.venv \
 && /opt/pwndbg/.venv/bin/pip install --no-cache-dir /opt/pwndbg

# Chromium matching REA's playwright-core 1.58.2, with its system libraries.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npx -y playwright@1.58.2 install --with-deps chromium \
 && ln -s "$(find /opt/ms-playwright -path '*chrome-linux*/chrome' -type f | head -1)" /usr/local/bin/chromium \
 && rm -rf /var/lib/apt/lists/* /root/.npm

WORKDIR /opt/rea
COPY --from=build /src/package.json /src/package-lock.json ./
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/dist ./dist
COPY --from=build /src/scripts ./scripts
COPY --from=build /src/bridge ./bridge
COPY --from=build /src/skills ./skills
COPY --from=build /src/third_party ./third_party
COPY --from=build /src/licenses ./licenses
COPY --from=build /src/LICENSE /src/README.md /src/DISCLAIMER.md /src/THIRD_PARTY_NOTICES.md ./
RUN ln -s /opt/rea/scripts/rea.mjs /usr/local/bin/rea

# Hopper's Linux demo through REA's own verified installer (package signature
# and launcher digest checks, Xvfb and X11 dependencies).
RUN apt-get update \
 && rea setup --yes --install-hopper --json \
 && rm -rf /var/lib/apt/lists/*

ENV TERM=xterm \
    GHIDRA_INSTALL_DIR=/opt/ghidra \
    REA_KUNA_COMMAND=/opt/kuna/kuna \
    REA_RIZIN_COMMAND=/opt/rizin/bin/rizin \
    REA_WABT_BIN_DIRECTORY=/opt/wabt/bin \
    REA_JADX_MCP_JAR=/opt/jadx/jadx-headless-mcp-0.7.1-all.jar \
    REA_APKTOOL_COMMAND=/opt/apktool/apktool \
    REA_ADB_PATH=/opt/platform-tools/adb \
    REA_WAKARU_COMMAND=/opt/wakaru/wakaru \
    REA_MITMDUMP_COMMAND=/opt/mitmproxy/mitmdump \
    REA_PWNTOOLS_PYTHON=/opt/pwntools/bin/python \
    REA_PWNDBG_GDB=/usr/bin/gdb \
    REA_PWNDBG_GDBINIT=/opt/pwndbg/gdbinit.py \
    REA_PWNDBG_VENV_PATH=/opt/pwndbg/.venv \
    REA_UNBLOB_COMMAND=/opt/unblob/bin/unblob \
    REA_BINWALK_COMMAND=/usr/local/bin/binwalk \
    REA_TSHARK_COMMAND=/usr/bin/tshark \
    REA_SIGROK_COMMAND=/usr/bin/sigrok-cli \
    REA_BROWSER_EXECUTABLE=/usr/local/bin/chromium \
    GHIDRA_HEADLESS_MAXMEM=12G \
    REA_GHIDRA_STARTUP_TIMEOUT_MS=3600000 \
    REA_HOPPER_STARTUP_TIMEOUT_MS=3600000

RUN mkdir -p /home/node/.rea /targets /work \
 && chown node:node /home/node/.rea /targets /work

USER node
WORKDIR /work
VOLUME ["/home/node/.rea"]
ENTRYPOINT ["rea"]
CMD ["mcp"]
