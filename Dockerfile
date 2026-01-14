# Usamos una única etapa final ya que instalaremos paquetes directamente
FROM snowdreamtech/alpine:3.21.0

LABEL org.opencontainers.image.authors="Nuntius Dev" \
      org.opencontainers.image.title="Dropbear + Stunnel + SFTP" \
      org.opencontainers.image.description="Secure Tunnel with SFTP support" \
      org.opencontainers.image.source="https://github.com/nuntius-dev/stunnel-dropbear"

# Definir variables de entorno
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

# Instalación de paquetes (Incluyendo openssh-sftp-server nativo)
# Eliminamos la necesidad de la etapa 'builder'
RUN apk add --no-cache \
    fastfetch \
    xauth \
    dropbear=${DROPBEAR_VERSION} \
    dropbear-convert=${DROPBEAR_VERSION} \
    dropbear-dbclient=${DROPBEAR_VERSION} \
    dropbear-scp=${DROPBEAR_VERSION} \
    dropbear-ssh=${DROPBEAR_VERSION} \
    openssh-sftp-server \
    stunnel \
    openssl \
    nano \
    nftables \
    iptables \
    iproute2 \
    && mkdir -p /usr/libexec \
    && mkdir -p ${TLS_PATH} \
    && mkdir -p /etc/dropbear

# Configuración de usuario
RUN if [ "${USER}" != "root" ]; then \
    addgroup -g ${GID} ${USER}; \
    adduser -h /home/${USER} -u ${UID} -g ${USER} -G ${USER} -s /bin/sh -D ${USER}; \
fi

# Configuración SFTP (Enlace simbólico para compatibilidad)
RUN mkdir -p /usr/lib/ssh/ \
    && ln -s /usr/lib/ssh/sftp-server /usr/libexec/sftp-server

# Scripts: RECOMENDACIÓN -> Usa COPY en lugar de wget para estabilidad
# Si prefieres mantener wget, asegúrate de que el link sea siempre válido.
# Aquí uso tu método wget pero corregido para evitar capas extra innecesarias.
RUN wget -O /usr/local/bin/motd.sh https://raw.githubusercontent.com/snowdreamtech/dropbear/refs/heads/main/alpine/motd.sh \
    && chmod +x /usr/local/bin/motd.sh \
    && mkdir -p /etc/periodic/15min \
    && ln -s /usr/local/bin/motd.sh /etc/periodic/15min/motd.sh

# Descargar entrypoint (Mejor sería: COPY combined-entrypoint.sh /usr/local/bin/)
RUN wget -O /usr/local/bin/combined-entrypoint.sh https://raw.githubusercontent.com/nuntius-dev/stunnel-dropbear/refs/heads/main/combined-entrypoint.sh \
    && chmod +x /usr/local/bin/combined-entrypoint.sh

# Generar certificados SSL autofirmados
RUN openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
        -keyout ${TLS_PATH}/key.pem -out ${TLS_PATH}/cert.pem && \
    cp ${TLS_PATH}/cert.pem ${TLS_PATH}/ca.pem && \
    chmod 600 ${TLS_PATH}/*.pem

# CORRECCIÓN CRÍTICA DE PERMISOS
# Si usas un usuario no root, debemos darle propiedad de las carpetas clave
RUN if [ "${USER}" != "root" ]; then \
    chown -R ${USER}:${USER} ${TLS_PATH} \
    && chown -R ${USER}:${USER} /etc/dropbear \
    && chown -R ${USER}:${USER} /home/${USER}; \
fi

USER ${USER}
WORKDIR ${WORKDIR}

EXPOSE 5000 4442

ENTRYPOINT ["/usr/local/bin/combined-entrypoint.sh"]
