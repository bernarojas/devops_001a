#!/usr/bin/env bash
# =============================================================================
#  PREPARACIÓN DE LA MÁQUINA VIRTUAL, DESDE FUERA
#
#  Envía preparar-maquina-desde-dentro.sh a la máquina por SSH y lo ejecuta
#  allá. Es un atajo: hace lo mismo que entrar por SSH a mano, pero averigua
#  la dirección solo, preguntándosela a Azure.
#
#  Instala Docker y los límites del sistema. El agente de la canalización se
#  registra aparte, con el comando que entrega el portal de Azure DevOps al
#  crear el recurso de máquina virtual dentro de un entorno; está documentado
#  en docs/AZURE-PIPELINES.md, paso 3.
#
#  Toda la lógica vive en preparar-maquina-desde-dentro.sh y no acá: así hay
#  una sola versión de los pasos, y no dos que se separan con el tiempo.
#
#  Requiere la CLI de Azure con sesión iniciada. Si prefieres no instalarla,
#  entra por SSH y ejecuta el otro script directamente.
#
#  Uso:
#      bash scripts/infraestructura/40-preparar-maquina.sh
#      bash scripts/infraestructura/40-preparar-maquina.sh --clave ~/.ssh/vm-web-01
# =============================================================================

set -euo pipefail

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/infraestructura/00-variables.sh
source "$DIRECTORIO/00-variables.sh"

CLAVE_SSH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clave) CLAVE_SSH="$2"; shift 2 ;;
        *) error "Opción desconocida: $1"; exit 2 ;;
    esac
done

titulo "Preparación de $MAQUINA"
verificar_sesion_azure

DIRECCION=$(az network public-ip show \
                --resource-group "$GRUPO_RECURSOS" \
                --name "$IP_PUBLICA" \
                --query ipAddress --output tsv)

listo "Conectando a $USUARIO_ADMIN@$DIRECCION"

# Si la máquina se creó desde el portal, la clave privada se descargó como
# archivo .pem y hay que indicarla. Si se creó con 30-maquina-virtual.sh, la
# clave quedó en ~/.ssh y ssh la encuentra sola.
OPCIONES_SSH=(-o StrictHostKeyChecking=accept-new)
if [[ -n "$CLAVE_SSH" ]]; then
    chmod 600 "$CLAVE_SSH" 2>/dev/null || true
    OPCIONES_SSH+=(-i "$CLAVE_SSH")
fi

paso "Enviando el script de preparación..."
scp "${OPCIONES_SSH[@]}" \
    "$DIRECTORIO/preparar-maquina-desde-dentro.sh" \
    "$USUARIO_ADMIN@$DIRECCION:/tmp/preparar.sh"

paso "Ejecutándolo en la máquina..."
ssh "${OPCIONES_SSH[@]}" "$USUARIO_ADMIN@$DIRECCION" "bash /tmp/preparar.sh"

titulo "Máquina preparada"
echo "  Siguiente paso: registrar el agente del entorno de Azure Pipelines."
echo "  El comando lo entrega el portal en Pipelines -> Entornos -> produccion,"
echo "  al agregar un recurso de tipo máquina virtual."
echo ""
echo "  Guía completa: docs/AZURE-PIPELINES.md"
echo ""
aviso "Si el primer despliegue falla por permisos del socket de Docker,"
aviso "reinicie la máquina:  az vm restart -g $GRUPO_RECURSOS -n $MAQUINA"
