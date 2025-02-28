#!/bin/sh
set -e

# Lógica de dropbear
if [ ! -f "/etc/dropbear/dropbear_rsa_host_key" ]; then
  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
fi

crond >/dev/null 2>&1
/etc/periodic/15min/motd.sh >/dev/null 2>&1

if [ -z "${SSH_ROOT_PASSWORD}" ]; then
  SSH_ROOT_PASSWORD=$(openssl rand -base64 33)
  echo "Generate random ssh root password:${SSH_ROOT_PASSWORD}"
fi

echo "root:$SSH_ROOT_PASSWORD" | chpasswd >/dev/null 2>&1

if [ ! -d "$HOME/.ssh" ]; then
  mkdir -p $HOME/.ssh
  dropbearkey -t ed25519 -C "user@example.com" -f $HOME/.ssh/id_ed25519 >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -C "user@example.com" -f $HOME/.ssh/id_rsa >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -C "user@example.com" -f $HOME/.ssh/id_ecdsa >/dev/null 2>&1
fi

# Lógica de stunnel
if [ -n "$STUNNEL_ENABLED" ]; then
  mkdir -p /etc/stunnel.d

  cat << EOF > /etc/stunnel.d/stunnel.conf
cert = ${TLS_PATH}/cert.pem
key = ${TLS_PATH}/key.pem
cafile = ${TLS_PATH}/ca.pem
verify = 2
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
syslog = no
delay = yes
foreground=yes

[backend]
client = ${CLIENT:-yes}
accept = ${ACCEPT:-0.0.0.0:4442}
connect = ${CONNECT}
EOF

  printf 'Stunneling: %s --> %s\n' ${ACCEPT} ${CONNECT}
  /usr/bin/stunnel /etc/stunnel.d/stunnel.conf &
fi

# Iniciar dropbear
/usr/sbin/dropbear

# Mantener el contenedor en ejecución
if [ "${KEEPALIVE}" -eq 1 ]; then
  trap : TERM INT
  tail -f /dev/null & wait
fi
