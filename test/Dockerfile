FROM debian:buster

RUN apt-get update && \
    apt-get install -y --force-yes bats git gnupg openssl && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN useradd -m test

USER test

WORKDIR /home/test
