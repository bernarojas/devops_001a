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
  1. Configurar Azure DevOps, siguiendo docs/AZURE-PIPELINES.md:

       Conexión de servicio a GitHub          github-devops001a
       Conexión de servicio al registro       acrventas-conexion
       Entorno con recurso de máquina virtual produccion / vm-web-01
       Variable secreta                       MSSQL_SA_PASSWORD

  2. Preparar la máquina con Docker y los límites del sistema:

       bash scripts/infraestructura/40-preparar-maquina.sh

  3. Registrar el agente del entorno dentro de la máquina, con el comando
     que entrega el portal al crear el recurso de máquina virtual.

  4. Crear las tres canalizaciones apuntando a los archivos del repositorio
     y ejecutar la de entrega continua.
PENDIENTE
