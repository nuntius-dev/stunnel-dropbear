# Primera etapa: Construcción de sftp
FROM snowdreamtech/alpine:3.21.0 AS builder
ENV OPENSSH_VERSION=9.9_p2-r0
RUN mkdir /workspace
WORKDIR /workspace
RUN apk add --no-cache openssh@main=$OPENSSH_VERSION \
    && cp $(which sftp-server) $(which sftp) /workspace/

# Segunda etapa: Configuración base
FROM alpine:3.21.0 AS base
MAINTAINER Phillip Clark <phillip@flitbit.com>
RUN set -ex && \
    echo "http://dl-3.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories && \
    apk update && apk add --update stunnel && \
    rm -rf /tmp/* /var/cache/apk/*
EXPOSE 4442

# Tercera etapa: Imagen final
FROM snowdreamtech/alpine:3.21.0
LABEL org.opencontainers.image.authors="Snowdream Tech" \
    org.opencontainers.image.title="Dropbear Image Based On Alpine" \
    org.opencontainers.image.description="Docker Images for Dropbear on Alpine." \
    org.opencontainers.image.documentation="https://hub.docker.com/r/snowdreamtech/dropbear" \
    org.opencontainers.image.base.name="snowdreamtech/dropbear:alpine" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.source="https://github.com/snowdreamtech/dropbear" \
    org.opencontainers.image.vendor="Snowdream Tech" \
    org.opencontainers.image.version="2024.86" \
    org.opencontainers.image.url="https://github.com/snowdreamtech/dropbear"

# Definir variables de entorno predeterminadas
ENV KEEPALIVE=1 \
    DROPBEAR_VERSION=2024.86-r0 \
    SSH_ROOT_PASSWORD="QPrCYbyWR6x5TYQV9fFYd7zl6aNnHhf/n9xbJ1OU3Qr1" \
    TLS_PATH="/etc/stunnel/certs" \
    ACCEPT="0.0.0.0:4442" \
    CLIENT="no" \
    CONNECT="127.0.0.1:5000"

ARG GID=1000 \
    UID=1000 \
    USER=root \
    WORKDIR=/root

# Crear usuario si no es root
RUN if [ "${USER}" != "root" ]; then \
    addgroup -g ${GID} ${USER}; \
    adduser -h /home/${USER} -u ${UID} -g ${USER} -G ${USER} -s /bin/sh -D ${USER}; \
fi

# Instalar paquetes necesarios
RUN apk add --no-cache \
    fastfetch \
    xauth \
    dropbear=${DROPBEAR_VERSION} \
    dropbear-convert=${DROPBEAR_VERSION} \
    dropbear-dbclient=${DROPBEAR_VERSION} \
    dropbear-scp=${DROPBEAR_VERSION} \
    dropbear-ssh=${DROPBEAR_VERSION} \
    stunnel \
    openssl \
    nano \
    nftables \
    iptables \
    iproute2 \
    && mkdir -p /usr/libexec \
    && mkdir -p ${TLS_PATH}

# Copiar binarios sftp
COPY --from=builder /workspace/sftp* /usr/libexec/

# Configurar sftp
RUN mkdir -p /usr/lib/ssh/ \
    && ln -s /usr/libexec/sftp-server /usr/lib/ssh/sftp-server \
    && echo -e '#!/bin/sh\n/usr/libexec/sftp -S /usr/bin/dbclient -s /usr/libexec/sftp-server "$@"' > /usr/local/bin/sftp \
    && chmod +x /usr/local/bin/sftp

# Configurar cron y motd
RUN wget -O /usr/local/bin/motd.sh https://raw.githubusercontent.com/snowdreamtech/dropbear/refs/heads/main/alpine/motd.sh \
    && chmod +x /usr/local/bin/motd.sh \
    && mkdir -p /etc/periodic/15min \
    && ln -s /usr/local/bin/motd.sh /etc/periodic/15min/motd.sh

# Descargar y configurar el script de entrada
RUN wget -O /usr/local/bin/combined-entrypoint.sh https://raw.githubusercontent.com/nuntius-dev/stunnel-dropbear/refs/heads/main/combined-entrypoint.sh \
    && chmod +x /usr/local/bin/combined-entrypoint.sh

# Generar certificados SSL autofirmados para pruebas
RUN mkdir -p ${TLS_PATH} && \
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
        -keyout ${TLS_PATH}/key.pem -out ${TLS_PATH}/cert.pem && \
    cp ${TLS_PATH}/cert.pem ${TLS_PATH}/ca.pem

USER ${USER}
WORKDIR ${WORKDIR}

# Exponer puertos
EXPOSE 5000 4442

# Punto de entrada
ENTRYPOINT ["/usr/local/bin/combined-entrypoint.sh"]
