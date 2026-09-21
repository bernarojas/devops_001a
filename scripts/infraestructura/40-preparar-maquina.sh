#!/usr/bin/env bash
# =============================================================================
#  PREPARACIÓN DE LA MÁQUINA VIRTUAL
#
#  Instala Docker y registra el agente autoalojado de GitHub Actions dentro de
#  la máquina. Se ejecuta DESDE la máquina del administrador: se conecta por
#  SSH y hace todo del otro lado.
#
#  POR QUÉ UN AGENTE AUTOALOJADO Y NO UN DESPLIEGUE POR SSH
#  Porque el agente se conecta DE SALIDA hacia GitHub y mantiene esa conexión
#  abierta. No hace falta abrir ningún puerto de administración hacia Internet.
#  La alternativa —que un agente alojado por GitHub entre por SSH— obligaría a
#  autorizar en el grupo de seguridad de red los rangos de direcciones de
#  GitHub, que son amplios y cambian con el tiempo. Eso desharía buena parte
#  del trabajo de la Experiencia 1.
#
#  El token de registro se obtiene en:
#      GitHub -> Settings -> Actions -> Runners -> New self-hosted runner
#  Caduca en una hora, así que conviene copiarlo justo antes de ejecutar esto.
#
#  Uso:
#      bash scripts/infraestructura/40-preparar-maquina.sh \
#           --repo bernarojas/devops_001a \
#           --token AXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# =============================================================================

set -euo pipefail

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/infraestructura/00-variables.sh
source "$DIRECTORIO/00-variables.sh"

REPOSITORIO=""
TOKEN=""
VERSION_AGENTE="${VERSION_AGENTE:-2.322.0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)  REPOSITORIO="$2"; shift 2 ;;
        --token) TOKEN="$2";       shift 2 ;;
        *) error "Opción desconocida: $1"; exit 2 ;;
    esac
done

if [[ -z "$REPOSITORIO" || -z "$TOKEN" ]]; then
    error "Faltan argumentos obligatorios."
    error "Uso: bash $0 --repo usuario/repositorio --token TOKEN_DE_REGISTRO"
    exit 2
fi

titulo "Preparación de $MAQUINA"
verificar_sesion_azure

DIRECCION=$(az network public-ip show \
                --resource-group "$GRUPO_RECURSOS" \
                --name "$IP_PUBLICA" \
                --query ipAddress --output tsv)

listo "Conectando a $USUARIO_ADMIN@$DIRECCION"

# -----------------------------------------------------------------------------
#  Todo lo que sigue se ejecuta DENTRO de la máquina virtual
# -----------------------------------------------------------------------------
#  El bloque va entre comillas simples para que nada se expanda del lado local:
#  las variables se pasan explícitamente al principio, y así se ve exactamente
#  qué entra. Con comillas dobles, un carácter del token podría interpretarse
#  acá en lugar de allá.
ssh -o StrictHostKeyChecking=accept-new "$USUARIO_ADMIN@$DIRECCION" \
    "REPOSITORIO='$REPOSITORIO' TOKEN='$TOKEN' VERSION_AGENTE='$VERSION_AGENTE' bash -s" <<'REMOTO'
set -euo pipefail

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
    echo "Para volver a registrarlo: cd $CARPETA && sudo ./svc.sh uninstall && ./config.sh remove --token TOKEN"
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

    # Como servicio: sobrevive a un reinicio de la máquina, que en una máquina
    # de prioridad baja no es hipotético sino esperable.
    sudo ./svc.sh install "$USER"
    sudo ./svc.sh start

    echo "Agente registrado y en ejecución."
fi

echo ""
echo "=== 5. Comprobación final ==="
sudo systemctl is-active "actions.runner.$(echo "$REPOSITORIO" | tr '/' '-').vm-ventas.service" \
    || echo "(el nombre del servicio puede variar; verifíquelo con: systemctl list-units 'actions.runner.*')"
REMOTO

titulo "Máquina preparada"
echo "  El agente debería aparecer como 'Idle' en:"
echo "      https://github.com/$REPOSITORIO/settings/actions/runners"
echo ""
aviso "La pertenencia al grupo docker se aplica al iniciar sesión de nuevo."
aviso "Si el primer despliegue falla por permisos del socket de Docker,"
aviso "reinicie la máquina:  az vm restart -g $GRUPO_RECURSOS -n $MAQUINA"
