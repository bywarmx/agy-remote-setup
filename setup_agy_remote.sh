#!/bin/bash
# setup_agy_remote.sh - Automatiza la transferencia de Antigravity (agy) y credenciales
# a un servidor remoto headless, sin instalar paquetes adicionales (keyrings/dbus) en el servidor.

set -e

# Colores para salida
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}[+] Iniciando script de migración para Antigravity CLI...${NC}"

# Validar argumentos de entrada
if [ "$#" -lt 2 ]; then
    echo -e "${RED}[!] Error: Parámetros insuficientes.${NC}"
    echo "Uso: $0 <usuario@ip_servidor_remoto> <ruta_llave_pem> [puerto_ssh]"
    echo "Ejemplo: $0 ubuntu@144.22.209.220 /home/bywarrior/Descargas/news.pem"
    exit 1
fi

REMOTE_HOST="$1"
PEM_KEY="$2"
SSH_PORT="${3:-22}"

# 1. Validar requerimientos locales
if [ ! -f "$PEM_KEY" ]; then
    echo -e "${RED}[!] La llave privada especificada no existe: $PEM_KEY${NC}"
    exit 1
fi

LOCAL_BINARY="/home/bywarrior/.local/bin/agy"
if [ ! -f "$LOCAL_BINARY" ]; then
    echo -e "${RED}[!] No se encontró el binario local de agy en $LOCAL_BINARY${NC}"
    exit 1
fi

# 2. Extraer token local de GNOME Keyring vía Python & D-Bus
echo -e "${GREEN}[+] Extrayendo token de autenticación del llavero local...${NC}"
TOKEN_JSON=$(python3 -c '
import dbus
try:
    bus = dbus.SessionBus()
    service = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets")
    service_iface = dbus.Interface(service, "org.freedesktop.Secret.Service")
    input_val = dbus.String("", variant_level=1)
    output, session_path = service_iface.OpenSession("plain", input_val)
    props = dbus.Interface(service, "org.freedesktop.DBus.Properties")
    found = False
    for collection in props.Get("org.freedesktop.Secret.Service", "Collections"):
        cobj = bus.get_object("org.freedesktop.secrets", collection)
        cprops = dbus.Interface(cobj, "org.freedesktop.DBus.Properties")
        if cprops.Get("org.freedesktop.Secret.Collection", "Locked"):
            continue
        for item in cprops.Get("org.freedesktop.Secret.Collection", "Items"):
            iobj = bus.get_object("org.freedesktop.secrets", item)
            iprops = dbus.Interface(iobj, "org.freedesktop.DBus.Properties")
            label = str(iprops.Get("org.freedesktop.Secret.Item", "Label"))
            attrs = {str(k): str(v) for k, v in dict(iprops.Get("org.freedesktop.Secret.Item", "Attributes")).items()}
            is_antigravity = label == "Password for '\''antigravity'\'' on '\''gemini'\''" or (attrs.get("service") == "gemini" and attrs.get("username") == "antigravity")
            if is_antigravity:
                item_iface = dbus.Interface(iobj, "org.freedesktop.Secret.Item")
                secret_struct = item_iface.GetSecret(session_path)
                secret_bytes = secret_struct[2]
                secret_str = "".join(chr(b) for b in secret_bytes)
                print(secret_str)
                found = True
                break
        if found:
            break
    if not found:
        print("NOT_FOUND")
except Exception as e:
    print("ERROR:", e)
')

if [[ "$TOKEN_JSON" == "NOT_FOUND" || "$TOKEN_JSON" == ERROR* || -z "$TOKEN_JSON" ]]; then
    echo -e "${RED}[!] Error al extraer el token local: $TOKEN_JSON${NC}"
    exit 1
fi

# 3. Empaquetar y transferir el binario de agy
echo -e "${GREEN}[+] Comprimiendo binario local de agy...${NC}"
gzip -c "$LOCAL_BINARY" > /tmp/agy.gz

echo -e "${GREEN}[+] Transfiriendo binario comprimido al servidor remoto...${NC}"
scp -P "$SSH_PORT" -i "$PEM_KEY" /tmp/agy.gz "$REMOTE_HOST":/tmp/agy.gz
rm -f /tmp/agy.gz

# 4. Instalar binario en el servidor remoto
echo -e "${GREEN}[+] Instalando binario en /usr/local/bin/agy de forma remota...${NC}"
ssh -p "$SSH_PORT" -i "$PEM_KEY" "$REMOTE_HOST" "sudo gunzip -c /tmp/agy.gz > /tmp/agy_unzipped && sudo mv /tmp/agy_unzipped /usr/local/bin/agy && sudo chmod +x /usr/local/bin/agy && rm -f /tmp/agy.gz"

# 5. Configurar directorios y escribir el token OAuth en la ruta headless correcta
echo -e "${GREEN}[+] Creando directorio de datos y escribiendo el token en el servidor remoto...${NC}"
ssh -p "$SSH_PORT" -i "$PEM_KEY" "$REMOTE_HOST" "
mkdir -p ~/.gemini/antigravity-cli
echo -n '$TOKEN_JSON' > ~/.gemini/antigravity-cli/antigravity-oauth-token
chmod 600 ~/.gemini/antigravity-cli/antigravity-oauth-token
# Eliminar posibles credenciales obsoletas de intentos fallidos previos
rm -f ~/.gemini/oauth_creds.json
"

# 6. Limpiar paquetes de llavero innecesarios en el servidor remoto
echo -e "${GREEN}[+] Asegurando limpieza de paquetes de llavero gráficos (gnome-keyring, dbus) en remoto...${NC}"
ssh -p "$SSH_PORT" -i "$PEM_KEY" "$REMOTE_HOST" "
if dpkg -s gnome-keyring >/dev/null 2>&1 || dpkg -s dbus-x11 >/dev/null 2>&1; then
    sudo apt-get purge -y gnome-keyring dbus-x11 libsecret-tools && sudo apt-get autoremove -y
fi
"

echo -e "${GREEN}[+] ¡Instalación y transferencia exitosas!${NC}"
echo -e "${GREEN}[+] Ejecutando prueba de verificación en remoto...${NC}"
ssh -p "$SSH_PORT" -i "$PEM_KEY" "$REMOTE_HOST" "agy models"

echo -e "${GREEN}[+] Migración completada correctamente.${NC}"
