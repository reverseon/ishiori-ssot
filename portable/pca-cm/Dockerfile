FROM debian:latest

RUN apt-get update && apt-get install -y gnupg sudo wget && rm -rf /var/lib/apt/lists/*

RUN wget https://go.dev/dl/go1.22.1.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.22.1.linux-amd64.tar.gz && \
    rm go1.22.1.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin

RUN useradd -m -s /bin/bash shinonome-chloe && \
    echo "shinonome-chloe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY utils/ishiori-ca /usr/local/lib/ishiori-ca
RUN chmod +x /usr/local/lib/ishiori-ca/main.sh && \
    ln -s /usr/local/lib/ishiori-ca/main.sh /usr/local/bin/ishiori-ca

WORKDIR /home/shinonome-chloe
USER shinonome-chloe
