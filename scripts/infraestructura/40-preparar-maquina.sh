#!/usr/bin/env bash
# =============================================================================
#  PREPARACIÓN DE LA MÁQUINA VIRTUAL, DESDE FUERA
#
#  Envía preparar-maquina-desde-dentro.sh a la máquina por SSH y lo ejecuta
#  allá. Es un atajo: hace lo mismo que entrar por SSH a mano, pero averigua
#  la dirección solo, preguntándosela a Azure.
#
#  Requiere la CLI de Azure con sesión iniciada. Si prefieres no instalarla,
#  entra por SSH y ejecuta el otro script directamente; está documentado en
#  docs/PUESTA-EN-MARCHA.md.
#
#  Toda la lógica vive en preparar-maquina-desde-dentro.sh y no acá: así hay
#  una sola versión de los pasos, y no dos que se separan con el tiempo.
#
#  El token de registro se obtiene en:
#      GitHub -> Settings -> Actions -> Runners -> New self-hosted runner
#  Caduca en una hora.
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
CLAVE_SSH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)  REPOSITORIO="$2"; shift 2 ;;
        --token) TOKEN="$2";       shift 2 ;;
        --clave) CLAVE_SSH="$2";   shift 2 ;;
        *) error "Opción desconocida: $1"; exit 2 ;;
    esac
done

if [[ -z "$REPOSITORIO" || -z "$TOKEN" ]]; then
    error "Faltan argumentos obligatorios."
    error "Uso: bash $0 --repo usuario/repositorio --token TOKEN_DE_REGISTRO"
    error "     [--clave ruta/a/la/clave.pem]"
    exit 2
fi

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
# Las comillas simples alrededor del comando remoto evitan que el token se
# expanda o se interprete de este lado.
ssh "${OPCIONES_SSH[@]}" "$USUARIO_ADMIN@$DIRECCION" \
    "bash /tmp/preparar.sh --repo '$REPOSITORIO' --token '$TOKEN'"

titulo "Máquina preparada"
echo "  El agente debería aparecer como 'Idle' en:"
echo "      https://github.com/$REPOSITORIO/settings/actions/runners"
echo ""
aviso "Si el primer despliegue falla por permisos del socket de Docker,"
aviso "reinicie la máquina:  az vm restart -g $GRUPO_RECURSOS -n $MAQUINA"
