FROM debian:latest

RUN apt-get update && apt-get install -y age sudo openssl && rm -rf /var/lib/apt/lists/*


RUN useradd -m -s /bin/bash shinonome-chloe && \
    echo "shinonome-chloe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY utils/ishiori-ca /usr/local/lib/ishiori-ca
RUN chmod +x /usr/local/lib/ishiori-ca/main.sh && \
    ln -s /usr/local/lib/ishiori-ca/main.sh /usr/local/bin/ishiori-ca

WORKDIR /home/shinonome-chloe
USER shinonome-chloe
