# The ucode-analyzer image: an OpenWrt rootfs of TARGET with the packages
# `make package` builds, run by bin/ucode-analyzer. `make image` builds it,
# with the packages as its context.
#
# OpenWrt's apk installs them into the target's published rootfs from an
# x86-64 stage, which runs no code of the target: an arm64 image (Apple
# Silicon, Arm Linux) builds without emulation. Package scripts, which would
# run it, are skipped: none matters to a command run in a container.
ARG OPENWRT_VERSION=25.12.4

FROM --platform=linux/amd64 openwrt/rootfs:x86-64-${OPENWRT_VERSION} AS rootfs
ARG OPENWRT_VERSION
# x86/64 or armsr/armv8
ARG TARGET=x86/64

RUN set -e; \
    base="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}"; \
    file="openwrt-${OPENWRT_VERSION}-$(echo "${TARGET}" | tr / -)-rootfs.tar.gz"; \
    cd /tmp; \
    wget -q "${base}/${file}" "${base}/sha256sums"; \
    grep " \*${file}\$" sha256sums | sed 's/ \*/  /' | sha256sum -c -; \
    mkdir /target; \
    tar -xzf "${file}" -C /target; \
    rm -f "${file}" sha256sums

# Every ucode module OpenWrt ships, and the libraries of the packages.ucode.dev
# feed (ucode-docopt, which the command needs, among them): imports of them
# resolve, and completion offers them, as on a device that has them.
RUN wget -qO /target/etc/apk/keys/packages.ucode.dev.pem \
        https://m00qek.github.io/packages.ucode.dev/25.12/feed.pub.pem && \
    echo "https://m00qek.github.io/packages.ucode.dev/25.12" \
        >> /target/etc/apk/repositories.d/customfeeds.list && \
    apk --root /target update && \
    apk --root /target add --no-scripts \
        ucode-mod-bpf ucode-mod-debug ucode-mod-digest ucode-mod-io \
        ucode-mod-lua ucode-mod-nl80211 ucode-mod-pkgen ucode-mod-resolv \
        ucode-mod-rtnl ucode-mod-socket ucode-mod-struct ucode-mod-udebug \
        ucode-mod-uline ucode-mod-zlib \
        ucode-utest ucode-docopt

COPY *.apk /packages/
RUN apk --root /target add --no-scripts --allow-untrusted /packages/*.apk && \
    rm -rf /target/var/cache/apk/* /target/tmp/*

FROM scratch
LABEL org.opencontainers.image.source="https://github.com/m00qek/ucode-analyzer" \
      org.opencontainers.image.description="Language server and linter for ucode" \
      org.opencontainers.image.licenses="MIT"
COPY --from=rootfs /target /
ENTRYPOINT ["/usr/bin/ucode-analyzer"]
