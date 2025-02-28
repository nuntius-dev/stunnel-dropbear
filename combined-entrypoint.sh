#!/bin/sh
set -e

# =============================================
# Configuración de Dropbear
# =============================================
# Generar claves SSH si no existen
if [ ! -f "/etc/dropbear/dropbear_rsa_host_key" ]; then
  echo "Generando claves SSH para el host..."
  dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1
fi

# Iniciar cron
echo "Iniciando cron..."
crond >/dev/null 2>&1 || echo "Error al iniciar cron, continuando..."

# Generar mensaje del día (motd)
if [ -f "/etc/periodic/15min/motd.sh" ]; then
  echo "Generando mensaje del día..."
  /etc/periodic/15min/motd.sh >/dev/null 2>&1 || echo "Error al generar motd, continuando..."
else
  echo "Script motd.sh no encontrado en la ruta esperada."
fi

# Generar contraseña aleatoria para root si no está definida
if [ -z "${SSH_ROOT_PASSWORD}" ]; then
  SSH_ROOT_PASSWORD=$(openssl rand -base64 33)
  echo "Contraseña SSH generada aleatoriamente: ${SSH_ROOT_PASSWORD}"
else
  echo "Usando contraseña SSH predefinida."
fi

# Configurar contraseña de root
echo "root:$SSH_ROOT_PASSWORD" | chpasswd >/dev/null 2>&1

# Generar claves SSH para el usuario actual
if [ ! -d "$HOME/.ssh" ]; then
  echo "Generando claves SSH para el usuario..."
  mkdir -p $HOME/.ssh
  dropbearkey -t ed25519 -C "user@example.com" -f $HOME/.ssh/id_ed25519 >/dev/null 2>&1
  dropbearkey -t rsa -s 4096 -C "user@example.com" -f $HOME/.ssh/id_rsa >/dev/null 2>&1
  dropbearkey -t ecdsa -s 521 -C "user@example.com" -f $HOME/.ssh/id_ecdsa >/dev/null 2>&1
fi

# =============================================
# Configuración de Stunnel
# =============================================
# Verificar variables requeridas
if [ -z "$CONNECT" ]; then
  echo "ADVERTENCIA: CONNECT no está definido, usando valor predeterminado: 127.0.0.1:22"
  CONNECT="127.0.0.1:5000"
fi

if [ -z "$TLS_PATH" ]; then
  echo "ADVERTENCIA: TLS_PATH no está definido, usando valor predeterminado: /etc/stunnel/certs"
  TLS_PATH="/etc/stunnel/certs"
fi

# Verificar existencia de archivos de certificados
if [ ! -f "${TLS_PATH}/cert.pem" ] || [ ! -f "${TLS_PATH}/key.pem" ] || [ ! -f "${TLS_PATH}/ca.pem" ]; then
  echo "ERROR: No se encontraron certificados en ${TLS_PATH}. Se requieren cert.pem, key.pem y ca.pem."
  echo "Generando certificados autofirmados para pruebas..."
  
  # Crear directorio si no existe
  mkdir -p ${TLS_PATH}
  
  # Generar certificados autofirmados
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
    -keyout ${TLS_PATH}/key.pem -out ${TLS_PATH}/cert.pem
  
  # Copiar certificado a CA
  cp ${TLS_PATH}/cert.pem ${TLS_PATH}/ca.pem
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

echo "Configurando túnel stunnel: ${ACCEPT} --> ${CONNECT}"

# =============================================
# Iniciar servicios
# =============================================
# Iniciar stunnel en segundo plano
echo "Iniciando stunnel..."
/usr/bin/stunnel /etc/stunnel.d/stunnel.conf &
STUNNEL_PID=$!

# Iniciar dropbear
echo "Iniciando dropbear..."
/usr/sbin/dropbear -p 5000 -F &
DROPBEAR_PID=$!

# Función para manejar señales de terminación
handle_term() {
  echo "Recibida señal de terminación, cerrando servicios..."
  kill $STUNNEL_PID $DROPBEAR_PID 2>/dev/null
  exit 0
}

# Establecer manejadores de señales
trap handle_term TERM INT

# Mantener el contenedor en ejecución
if [ "${KEEPALIVE}" -eq 1 ]; then
  echo "Modo KEEPALIVE activado, esperando..."
  wait $DROPBEAR_PID
  wait $STUNNEL_PID
else
  # Si KEEPALIVE no está activado, esperar a dropbear
  wait $DROPBEAR_PID
fi
