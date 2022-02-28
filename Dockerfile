# Tools for building packages and repos
FROM ubuntu:20.04
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --yes \
        apt-utils \
        dpkg \
        dpkg-dev \
        reprepro \
        tree \
        vim \
    && apt-get autoremove --yes && apt-get clean && rm -rf /var/lib/apt/lists/*
