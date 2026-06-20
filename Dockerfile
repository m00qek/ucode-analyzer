ARG SDK_ARCH=x86-64
ARG SDK_VERSION=25.12

FROM openwrt/rootfs:${SDK_ARCH}-openwrt-${SDK_VERSION}

RUN mkdir -p /var/lock && \
    wget -q --no-check-certificate -O /tmp/utest.apk \
        https://github.com/m00qek/utest/releases/download/v1.3.0/ucode-utest-1.2.0.470f6999-r1.apk && \
    echo "ac1d6afe9cf62ef4fcaf68fa47c7b840a13efefac501192becbd9ffaf5ce2d68  /tmp/utest.apk" | sha256sum -c - && \
    apk add --allow-untrusted /tmp/utest.apk && \
    rm /tmp/utest.apk && \
    wget -q --no-check-certificate -O /tmp/docopt.apk \
        https://github.com/m00qek/docopt.uc/releases/download/v1.0.0/ucode-docopt-1.0.0.24989c2-r1.apk && \
    echo "0fc20835df480410efc820bb6106723c5258fae7f85c023c8f3c143a31683e4b  /tmp/docopt.apk" | sha256sum -c - && \
    apk add --allow-untrusted /tmp/docopt.apk && \
    rm /tmp/docopt.apk && \
    mkdir -p /usr/lib/ucode/ucode_language_server

WORKDIR /app
