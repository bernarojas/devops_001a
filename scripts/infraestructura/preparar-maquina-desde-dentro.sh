#!/usr/bin/env bash
# =============================================================================
#  PREPARACIÓN DE LA MÁQUINA, EJECUTADA DENTRO DE ELLA
#
#  Instala Docker, ajusta los límites que SQL Server necesita y registra el
#  agente de GitHub Actions.
#
#  Este script se ejecuta DENTRO de la máquina virtual, por SSH. Es la parte
#  que no se puede hacer con clics en el portal: instalar software y registrar
#  un servicio requiere una terminal en la máquina, no un formulario.
#
#  Hay dos formas de llegar acá:
#    - A mano, entrando por SSH y clonando el repositorio (ver docs).
#    - Desde la máquina del administrador, con 40-preparar-maquina.sh, que
#      hace lo mismo pero se conecta solo.
#
#  El token de registro se obtiene en:
#      GitHub -> Settings -> Actions -> Runners -> New self-hosted runner
#  Caduca en una hora.
#
#  Uso, ya dentro de la máquina:
#      bash scripts/infraestructura/preparar-maquina-desde-dentro.sh \
#           --repo bernarojas/devops_001a \
#           --token AXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# =============================================================================

set -euo pipefail

REPOSITORIO=""
TOKEN=""
VERSION_AGENTE="${VERSION_AGENTE:-2.322.0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)  REPOSITORIO="$2"; shift 2 ;;
        --token) TOKEN="$2";       shift 2 ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$REPOSITORIO" || -z "$TOKEN" ]]; then
    echo "Faltan argumentos obligatorios." >&2
    echo "Uso: bash $0 --repo usuario/repositorio --token TOKEN_DE_REGISTRO" >&2
    exit 2
fi

echo ""
echo "=== 1. Paquetes base ==="
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl gnupg jq

echo ""
echo "=== 2. Docker Engine ==="
if command -v docker > /dev/null 2>&1; then
    echo "Docker ya está instalado: $(docker --version)"
else
    # Repositorio oficial de Docker. La alternativa, el paquete docker.io de
    # Ubuntu, suele ir varias versiones por detrás y no incluye el complemento
    # `compose` v2, que es el que usa la orquestación de este proyecto.
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Instalado: $(docker --version)"
fi

# El agente ejecuta como el usuario administrador, no como root. Para que
# pueda hablar con el demonio de Docker tiene que pertenecer al grupo docker.
sudo usermod -aG docker "$USER"

echo ""
echo "=== 3. Límites del sistema para SQL Server ==="
# SQL Server necesita más memoria compartida y más archivos abiertos que los
# valores por omisión de Ubuntu. Se aplican al anfitrión porque el contenedor
# hereda estos límites del núcleo.
if [[ ! -f /etc/sysctl.d/90-sqlserver.conf ]]; then
    sudo tee /etc/sysctl.d/90-sqlserver.conf > /dev/null <<'LIMITES'
# Requerido por SQL Server en contenedor.
fs.file-max = 2097152
vm.max_map_count = 262144
LIMITES
    sudo sysctl --system > /dev/null
    echo "Límites aplicados."
else
    echo "Los límites ya estaban configurados."
fi

echo ""
echo "=== 4. Agente de GitHub Actions ==="
CARPETA="$HOME/actions-runner"

if [[ -f "$CARPETA/.runner" ]]; then
    echo "Ya hay un agente registrado en $CARPETA."
    echo "Para rehacerlo:"
    echo "    cd $CARPETA && sudo ./svc.sh uninstall && ./config.sh remove --token TOKEN"
else
    mkdir -p "$CARPETA"
    cd "$CARPETA"

    if [[ ! -f "./config.sh" ]]; then
        ARCHIVO="actions-runner-linux-x64-${VERSION_AGENTE}.tar.gz"
        echo "Descargando el agente $VERSION_AGENTE..."
        curl -fsSL -o "$ARCHIVO" \
            "https://github.com/actions/runner/releases/download/v${VERSION_AGENTE}/${ARCHIVO}"
        tar xzf "$ARCHIVO"
        rm -f "$ARCHIVO"
    fi

    # Las tres etiquetas son las que el flujo de despliegue exige en
    # `runs-on: [self-hosted, linux, ventas]`. "ventas" identifica a ESTA
    # máquina: si mañana se registrara otro agente en el repositorio, el
    # despliegue no se le iría por error.
    #
    # --unattended y --replace permiten volver a ejecutar el script sin que se
    # quede esperando una respuesta ni falle porque el nombre ya existe.
    ./config.sh \
        --url "https://github.com/${REPOSITORIO}" \
        --token "${TOKEN}" \
        --name "vm-ventas" \
        --labels "self-hosted,linux,ventas" \
        --work "_trabajo" \
        --unattended \
        --replace

    # Como servicio: sobrevive a un reinicio de la máquina.
    sudo ./svc.sh install "$USER"
    sudo ./svc.sh start

    echo "Agente registrado y en ejecución."
fi

echo ""
echo "=== 5. Comprobación final ==="
systemctl list-units 'actions.runner.*' --no-pager --no-legend || true

echo ""
echo "Preparación completada."
echo ""
echo "El agente debería aparecer como 'Idle' en:"
echo "    https://github.com/${REPOSITORIO}/settings/actions/runners"
echo ""
echo "AVISO: la pertenencia al grupo docker se aplica al iniciar sesión de"
echo "nuevo. Cierra esta sesión SSH y vuelve a entrar antes del primer"
echo "despliegue, o reinicia la máquina desde el portal."
