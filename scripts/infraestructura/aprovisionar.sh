#!/usr/bin/env bash
# =============================================================================
#  APROVISIONAMIENTO COMPLETO
#
#  Ejecuta en orden los scripts de infraestructura. Todo es idempotente: si el
#  ambiente ya existe, no se recrea nada y el script termina describiendo lo
#  que hay.
#
#  POR QUÉ SCRIPTS Y NO CLICS EN EL PORTAL
#  Porque el ambiente tiene que poder reconstruirse desde el repositorio, sin
#  que nadie recuerde qué casilla marcó. Un ambiente creado a mano es un
#  ambiente que nadie puede reproducir ni revisar, y del que no se sabe en qué
#  se diferencia del que alguien describió en un informe.
#
#  El registro del agente de GitHub queda fuera a propósito: necesita un token
#  que caduca en una hora y que hay que copiar del sitio en ese momento.
#
#  Uso:
#      az login
#      bash scripts/infraestructura/aprovisionar.sh
# =============================================================================

set -euo pipefail

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/infraestructura/00-variables.sh
source "$DIRECTORIO/00-variables.sh"

titulo "Aprovisionamiento del ambiente"
echo "  Grupo de recursos : $GRUPO_RECURSOS"
echo "  Region            : $REGION"
echo "  Maquina virtual   : $MAQUINA"
echo "  Registro          : $REGISTRO_NOMBRE"

bash "$DIRECTORIO/10-red.sh"
bash "$DIRECTORIO/20-registro.sh"
bash "$DIRECTORIO/30-maquina-virtual.sh"

titulo "Qué falta para que el despliegue funcione"
cat <<'PENDIENTE'
  1. Cargar los secretos del repositorio, en
     GitHub -> Settings -> Secrets and variables -> Actions -> Secrets:

       REGISTRO_SERVIDOR    servidor del registro (lo imprimió 20-registro.sh)
       REGISTRO_USUARIO     usuario administrador del registro
       REGISTRO_CLAVE       contraseña del registro
       MSSQL_SA_PASSWORD    contraseña del usuario sa del motor

  2. Cargar la variable del repositorio, en la pestaña Variables:

       DIRECCION_PUBLICA    la dirección que imprimió 30-maquina-virtual.sh

  3. Registrar el agente autoalojado dentro de la máquina:

       bash scripts/infraestructura/40-preparar-maquina.sh \
            --repo usuario/repositorio --token TOKEN_DE_REGISTRO

  4. Integrar en la rama principal. El despliegue se dispara solo.
PENDIENTE
