ARG SDK_ARCH=x86-64
ARG SDK_VERSION=25.12.4

FROM openwrt/rootfs:${SDK_ARCH}-${SDK_VERSION}

RUN apk update && \
    apk add \
        ucode-mod-bpf ucode-mod-debug ucode-mod-digest ucode-mod-io \
        ucode-mod-lua ucode-mod-nl80211 ucode-mod-pkgen ucode-mod-resolv \
        ucode-mod-rtnl ucode-mod-socket ucode-mod-struct ucode-mod-udebug \
        ucode-mod-uline ucode-mod-zlib

RUN wget -qO /etc/apk/keys/packages.ucode.dev.pem \
        https://m00qek.github.io/packages.ucode.dev/25.12/feed.pub.pem && \
    echo "https://m00qek.github.io/packages.ucode.dev/25.12" \
        >> /etc/apk/repositories.d/customfeeds.list && \
    apk update && \
    apk add ucode-utest ucode-docopt

WORKDIR /app
