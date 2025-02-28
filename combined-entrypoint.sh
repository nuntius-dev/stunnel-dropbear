#!/bin/sh
set -e

# =============================================
# Configuración de Dropbear (original de docker-entrypoint.sh)
# =============================================

# Generar claves SSH si no existen
if [ ! -f "/etc/dropbear/dropbear_rsa_host_key" ]; then
  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
fi

# Iniciar cron
crond >/dev/null 2>&1

# Generar mensaje del día (motd)
/etc/periodic/15min/motd.sh >/dev/null 2>&1

# Generar contraseña aleatoria para root
if [ -z "${SSH_ROOT_PASSWORD}" ]; then
  SSH_ROOT_PASSWORD=$(openssl rand -base64 33)
  echo "Contraseña SSH generada: ${SSH_ROOT_PASSWORD}"
fi
echo "root:$SSH_ROOT_PASSWORD" | chpasswd >/dev/null 2>&1

# Generar claves SSH para el usuario
if [ ! -d "$HOME/.ssh" ]; then
  mkdir -p $HOME/.ssh
  dropbearkey -t ed25519 -C "user@example.com" -f $HOME/.ssh/id_ed25519 >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -C "user@example.com" -f $HOME/.ssh/id_rsa >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -C "user@example.com" -f $HOME/.ssh/id_ecdsa >/dev/null 2>&1
fi

# =============================================
# Configuración de Stunnel (original de run-stunnel.sh)
# =============================================

# Variables requeridas
if [ -z "$CONNECT" ] || [ -z "$TLS_PATH" ]; then
  echo "Error: Se requieren las opciones -c (CONNECT) y -t (TLS_PATH)."
  exit 1
fi

# Crear configuración de stunnel
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
foreground = yes

[backend]
client = ${CLIENT:-yes}
accept = ${ACCEPT:-0.0.0.0:4442}
connect = ${CONNECT}
EOF

echo "Configurando túnel: ${ACCEPT} --> ${CONNECT}"

# =============================================
# Iniciar servicios
# =============================================

# Iniciar stunnel en segundo plano
/usr/bin/stunnel /etc/stunnel.d/stunnel.conf &

# Iniciar dropbear en primer plano
/usr/sbin/dropbear -F

# Mantener el contenedor en ejecución si es necesario
if [ "${KEEPALIVE}" -eq 1 ]; then
  trap : TERM INT
  tail -f /dev/null & wait
fi
