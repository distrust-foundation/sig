FROM debian:buster

RUN apt-get update && \
    apt-get install -y --force-yes sudo bats git gnupg openssl shellcheck psmisc

RUN useradd -m test -G sudo -s /bin/bash
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER test

WORKDIR /home/test
