#!/usr/bin/env bash
# =============================================================================
#  PREPARACIÓN DE LA MÁQUINA, EJECUTADA DENTRO DE ELLA
#
#  Instala Docker y ajusta los límites del sistema que SQL Server necesita.
#  Es todo lo que la máquina requiere antes de poder recibir un despliegue.
#
#  NO registra el agente de la canalización. Ese paso lo cubre el propio portal
#  de Azure DevOps: al crear el recurso de máquina virtual dentro de un entorno
#  entrega un comando con un token de un solo uso, que se pega y se ejecuta
#  aquí mismo. Está documentado en docs/AZURE-PIPELINES.md, paso 3.
#
#  Mantener esas dos cosas separadas tiene una razón: lo que este script hace
#  es idempotente y se puede repetir sin consecuencias, mientras que registrar
#  un agente es una operación con estado y con una credencial que caduca.
#
#  Hay dos formas de llegar acá:
#    - A mano, entrando por SSH y clonando el repositorio.
#    - Desde la máquina del administrador, con 40-preparar-maquina.sh, que
#      hace lo mismo pero se conecta solo.
#
#  Uso, ya dentro de la máquina:
#      bash scripts/infraestructura/preparar-maquina-desde-dentro.sh
# =============================================================================

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

# El agente de la canalización ejecuta como este usuario, no como root. Para
# que pueda hablar con el demonio de Docker tiene que pertenecer al grupo
# docker.
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
echo "=== 4. Comprobación ==="
docker --version
docker compose version
echo "Memoria disponible:"
free -h | awk 'NR<=2'

echo ""
echo "Preparación completada."
echo ""
echo "SIGUIENTE PASO: registrar el agente del entorno de Azure Pipelines."
echo "El comando lo entrega el portal en Pipelines -> Entornos -> produccion,"
echo "al agregar un recurso de tipo máquina virtual. Ver docs/AZURE-PIPELINES.md"
echo ""
echo "AVISO: la pertenencia al grupo docker se aplica al iniciar sesión de"
echo "nuevo. Cierra esta sesión SSH y vuelve a entrar antes de registrar el"
echo "agente, o reinicia la máquina desde el portal."
