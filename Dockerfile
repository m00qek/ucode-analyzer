ARG SDK_ARCH=x86-64
ARG SDK_VERSION=25.12

FROM openwrt/rootfs:${SDK_ARCH}-openwrt-${SDK_VERSION}

RUN mkdir -p /var/lock && \
    wget -q --no-check-certificate -O /tmp/utest.apk \
        https://github.com/m00qek/utest/releases/download/v1.2.1/ucode-utest-1.2.0.7ff5709b-r1.apk && \
    echo "2983cfa2128f35aec80ea6822881f934a8f9694e2c2ffbc75759074a91465774  /tmp/utest.apk" | sha256sum -c - && \
    apk add --allow-untrusted /tmp/utest.apk && \
    rm /tmp/utest.apk && \
    mkdir -p /usr/lib/ucode/ucode_language_server

WORKDIR /app
