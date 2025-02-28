#!/bin/sh
set -e

# =============================================
# Configuración de Dropbear y Stunnel
# =============================================

# Variables predeterminadas
CONNECT="${CONNECT:-127.0.0.1:5000}"
TLS_PATH="${TLS_PATH:-/etc/stunnel/certs}"
ACCEPT="${ACCEPT:-0.0.0.0:4442}"

echo "Configurando entorno..."
mkdir -p "$TLS_PATH" /etc/stunnel.d /etc/dropbear

# =============================================
# Generar claves y certificados SSL para Stunnel
# =============================================
if [ ! -f "${TLS_PATH}/cert.pem" ] || [ ! -f "${TLS_PATH}/key.pem" ] || [ ! -f "${TLS_PATH}/ca.pem" ]; then
  echo "Generando certificados SSL para Stunnel..."
  
  # Generar clave y certificado de la CA
  openssl genrsa -out "${TLS_PATH}/ca.key" 2048
  openssl req -new -x509 -days 365 -key "${TLS_PATH}/ca.key" -out "${TLS_PATH}/ca.crt" -subj "/CN=My CA"

  # Generar clave y CSR para el servidor
  openssl genrsa -out "${TLS_PATH}/key.pem" 2048
  openssl req -new -key "${TLS_PATH}/key.pem" -out "${TLS_PATH}/server.csr" -subj "/CN=localhost"

  # Firmar el certificado del servidor con la CA
  openssl x509 -req -days 365 -in "${TLS_PATH}/server.csr" -CA "${TLS_PATH}/ca.crt" -CAkey "${TLS_PATH}/ca.key" -CAcreateserial -out "${TLS_PATH}/cert.pem"

  # Copiar el certificado de la CA para validaciones
  cp "${TLS_PATH}/ca.crt" "${TLS_PATH}/ca.pem"
fi

# =============================================
# Generar claves SSH para Dropbear
# =============================================
if [ ! -f "/etc/dropbear/dropbear_rsa_host_key" ]; then
  echo "Generando claves SSH para Dropbear..."
  dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
fi

# =============================================
# Configurar Stunnel
# =============================================
cat << EOF > /etc/stunnel.d/stunnel.conf
cert = ${TLS_PATH}/cert.pem
key = ${TLS_PATH}/key.pem
cafile = ${TLS_PATH}/ca.pem
verify = 0
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
syslog = no
delay = yes
foreground = yes
[backend]
client = no
accept = ${ACCEPT}
connect = ${CONNECT}
EOF

echo "Stunnel configurado: ${ACCEPT} --> ${CONNECT}"

# =============================================
# Iniciar servicios
# =============================================
echo "Iniciando Stunnel..."
stunnel /etc/stunnel.d/stunnel.conf &
STUNNEL_PID=$!

echo "Iniciando Dropbear..."
dropbear -p 5000 -F &
DROPBEAR_PID=$!

# =============================================
# Manejo de señales para apagado seguro
# =============================================
handle_term() {
  echo "Recibida señal de terminación, cerrando servicios..."
  kill $STUNNEL_PID $DROPBEAR_PID 2>/dev/null
  exit 0
}

trap handle_term TERM INT

# =============================================
# Mantener en ejecución (opcional)
# =============================================
if [ "${KEEPALIVE}" = "1" ]; then
  echo "Modo KEEPALIVE activado, esperando..."
  wait $STUNNEL_PID
  wait $DROPBEAR_PID
else
  wait $DROPBEAR_PID
fi
