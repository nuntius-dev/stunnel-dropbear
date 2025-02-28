#!/bin/sh
set -e

# Iniciar stunnel
/opt/run-stunnel.sh &

# Configurar Dropbear
if [ ! -f "/etc/dropbear/dropbear_rsa_host_key" ]; then
  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
fi

# Iniciar cron
crond >/dev/null 2>&1

# Generar motd
/etc/periodic/15min/motd.sh >/dev/null 2>&1

# Generar contraseña aleatoria para root si no está definida
if [ -z "${SSH_ROOT_PASSWORD}" ]; then
    SSH_ROOT_PASSWORD=$(openssl rand -base64 33)
    echo "Generate random ssh root password:${SSH_ROOT_PASSWORD}"
fi

# Cambiar la contraseña de root
echo "root:$SSH_ROOT_PASSWORD" | chpasswd >/dev/null 2>&1

# Generar claves SSH si no existen
if [ ! -d "$HOME/.ssh" ]; then
  mkdir -p $HOME/.ssh
  dropbearkey -t ed25519 -C "user@example.com" -f $HOME/.ssh/id_ed25519 >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -C "user@example.com" -f $HOME/.ssh/id_rsa >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -C "user@example.com" -f $HOME/.ssh/id_ecdsa >/dev/null 2>&1
fi

# Iniciar Dropbear
/usr/sbin/dropbear

# Mantener el contenedor en ejecución
if [ "${KEEPALIVE}" -eq 1 ]; then
    trap : TERM INT
    tail -f /dev/null & wait
fi
