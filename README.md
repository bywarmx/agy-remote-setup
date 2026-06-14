# Antigravity CLI Remote Headless Setup

Este script automatiza la transferencia del binario `agy` (Antigravity CLI) y sus credenciales de autenticación de Google OAuth a un servidor Ubuntu headless remoto, sin necesidad de instalar dependencias adicionales de entorno gráfico como `gnome-keyring` o `dbus`.

## Requisitos
- Python 3 y D-Bus instalados localmente (para extraer el token de autenticación del llavero).
- Acceso SSH al servidor remoto (por medio de contraseña, ssh-agent o llave privada PEM).

## Uso

```bash
chmod +x setup_agy_remote.sh
./setup_agy_remote.sh <usuario@ip_servidor_remoto> [ruta_llave_pem] [puerto_ssh]
```

Ejemplos:
- **Con llave PEM:** `./setup_agy_remote.sh ubuntu@144.22.209.220 /home/bywarrior/Descargas/news.pem`
- **Sin llave PEM (usa contraseña, ssh-agent o configuración SSH estándar):** `./setup_agy_remote.sh ubuntu@144.22.209.220`
