#!/bin/sh
set -e

# Configurar contraseña de root si se proporciona
if [ -n "$SSH_ROOT_PASSWORD" ]; then
    echo "root:$SSH_ROOT_PASSWORD" | chpasswd
    echo "✅ Contraseña de root configurada."
else
    echo "⚠️  No se definió SSH_ROOT_PASSWORD. El acceso por contraseña a root estará deshabilitado."
    # Opcional: bloquear root si no hay contraseña
    # passwd -l root
fi

# Crear un usuario adicional si se definen SSH_USER y SSH_PASSWORD
if [ -n "$SSH_USER" ] && [ -n "$SSH_PASSWORD" ]; then
    if ! id "$SSH_USER" >/dev/null 2>&1; then
        adduser -D -h "/home/$SSH_USER" -s /bin/sh "$SSH_USER"
        echo "$SSH_USER:$SSH_PASSWORD" | chpasswd
        echo "✅ Usuario $SSH_USER creado con contraseña."
        # Asegurar home y permisos
        mkdir -p "/home/$SSH_USER/.ssh"
        chown -R "$SSH_USER:$SSH_USER" "/home/$SSH_USER"
    else
        echo "⚠️  El usuario $SSH_USER ya existe. Actualizando contraseña."
        echo "$SSH_USER:$SSH_PASSWORD" | chpasswd
    fi
fi

# Configurar keepalive si es necesario (opcional)
if [ "$KEEPALIVE" = "1" ]; then
    echo "♻️ Keepalive activado (el contenedor no se detendrá al fallar un servicio)"
fi

# Preparar directorios
mkdir -p /var/run/dropbear /etc/dropbear

# Generar claves de dropbear si no existen
if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key -s 2048
fi
if [ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]; then
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key -s 256
fi

# Configurar stunnel (usando variables ACCEPT, CONNECT, CLIENT)
cat > /etc/stunnel/stunnel.conf << EOF
foreground = yes
setuid = ${USER:-root}
setgid = ${USER:-root}
pid = /tmp/stunnel.pid
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
debug = 7
[dropbear]
accept = ${ACCEPT:-0.0.0.0:4442}
connect = ${CONNECT:-127.0.0.1:5000}
client = ${CLIENT:-no}
cert = ${TLS_PATH:-/etc/stunnel/certs}/cert.pem
key = ${TLS_PATH:-/etc/stunnel/certs}/key.pem
EOF

# Iniciar dropbear (escuchando en localhost:5000)
echo "🚀 Iniciando Dropbear en 127.0.0.1:5000"
dropbear -F -E -p 127.0.0.1:5000 -R &

# Iniciar stunnel
echo "🔒 Iniciando Stunnel en ${ACCEPT}"
stunnel /etc/stunnel/stunnel.conf

# Mantener el contenedor vivo si KEEPALIVE=1
if [ "$KEEPALIVE" = "1" ]; then
    echo "🔄 Modo keepalive: monitorizando servicios..."
    while true; do
        sleep 30
        if ! pgrep dropbear > /dev/null; then
            echo "❌ Dropbear caído, reiniciando..."
            dropbear -F -E -p 127.0.0.1:5000 -R &
        fi
        if ! pgrep stunnel > /dev/null; then
            echo "❌ Stunnel caído, reiniciando..."
            stunnel /etc/stunnel/stunnel.conf
        fi
    done
else
    # Esperar a que ambos servicios terminen (normalmente uno se queda en foreground)
    wait
fi
