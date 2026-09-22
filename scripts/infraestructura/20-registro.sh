#!/usr/bin/env bash
# =============================================================================
#  REGISTRO DE CONTENEDORES (Azure Container Registry)
#
#  Crea el registro privado donde se centralizan las imágenes de la solución.
#
#  Las canalizaciones se autentican mediante una conexión de servicio de Azure
#  DevOps, no con estas credenciales. El usuario administrador se habilita
#  igualmente para poder entrar a mano desde la máquina o desde una terminal.
#
#  QUÉ APORTA TENER UN REGISTRO, CONCRETAMENTE
#    - Trazabilidad: la etiqueta conecta la imagen en marcha con el commit que
#      la originó y con la ejecución que la construyó y la probó.
#    - Reversión inmediata: volver atrás es desplegar otra etiqueta.
#    - La máquina virtual deja de compilar: no necesita SDK ni código fuente.
#    - Un solo origen para varios destinos: el mismo registro puede alimentar
#      hoy a la máquina virtual y mañana a Azure Container Apps o a un clúster,
#      sin reconstruir nada.
#
#  Uso:
#      bash scripts/infraestructura/20-registro.sh
# =============================================================================

set -euo pipefail

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/infraestructura/00-variables.sh
source "$DIRECTORIO/00-variables.sh"

titulo "Registro de contenedores"
verificar_sesion_azure

# -----------------------------------------------------------------------------
#  Creación
# -----------------------------------------------------------------------------
if az acr show --name "$REGISTRO_NOMBRE" > /dev/null 2>&1; then
    listo "El registro $REGISTRO_NOMBRE ya existe."
else
    # El nombre es único en todo Azure, no sólo en la suscripción. Se comprueba
    # antes de intentar crear, porque el error de nombre tomado es críptico.
    paso "Comprobando que el nombre $REGISTRO_NOMBRE esté disponible..."
    DISPONIBLE=$(az acr check-name --name "$REGISTRO_NOMBRE" --query nameAvailable --output tsv)

    if [[ "$DISPONIBLE" != "true" ]]; then
        error "El nombre $REGISTRO_NOMBRE no está disponible en Azure."
        error "Elija otro:  REGISTRO_NOMBRE=acrventasgrupo14 bash $0"
        exit 1
    fi

    paso "Creando el registro $REGISTRO_NOMBRE (nivel $REGISTRO_SKU)..."
    # Nivel Basic: 10 GB de almacenamiento. Las dos imágenes del proyecto
    # juntas no superan los 500 MB, de modo que el margen es amplio.
    az acr create \
        --resource-group "$GRUPO_RECURSOS" \
        --name "$REGISTRO_NOMBRE" \
        --location "$REGION" \
        --sku "$REGISTRO_SKU" \
        --output none
    listo "Registro creado."
fi

# -----------------------------------------------------------------------------
#  Usuario administrador
# -----------------------------------------------------------------------------
#  COMPROMISO ASUMIDO Y DOCUMENTADO.
#
#  Esta credencial es única para todo el registro y concede lectura Y
#  escritura, cuando la máquina virtual sólo necesita descargar.
#
#  Lo correcto es una identidad administrada con el rol AcrPull, que permite
#  únicamente descargar y no requiere contraseña alguna. No se adoptó porque
#  asignar ese rol exige permisos sobre el directorio de la institución que una
#  suscripción Azure for Students no otorga. Queda como propuesta de mejora.
paso "Habilitando el usuario administrador del registro..."
az acr update --name "$REGISTRO_NOMBRE" --admin-enabled true --output none
listo "Usuario administrador habilitado."

# -----------------------------------------------------------------------------
#  Política de retención
# -----------------------------------------------------------------------------
#  Cada compilación deja un manifiesto sin etiqueta al reemplazar la anterior.
#  Sin limpieza, esos manifiestos se acumulan indefinidamente.
paso "Configurando la retención de manifiestos sin etiqueta..."
if az acr config retention update \
        --registry "$REGISTRO_NOMBRE" \
        --status enabled \
        --days 30 \
        --type UntaggedManifests \
        --output none 2>/dev/null; then
    listo "Retención automática: 30 días."
else
    # El nivel Basic no admite retención automática. No es un fallo del
    # aprovisionamiento: se informa el comando equivalente para ejecutarlo a
    # demanda y se sigue adelante.
    aviso "El nivel $REGISTRO_SKU no admite retención automática."
    aviso "Limpieza manual cuando haga falta:"
    aviso "    az acr run --registry $REGISTRO_NOMBRE \\"
    aviso "      --cmd 'acr purge --filter \"ventas-web:.*\" --untagged --ago 30d' /dev/null"
fi

# -----------------------------------------------------------------------------
#  Credenciales para el acceso manual
# -----------------------------------------------------------------------------
SERVIDOR=$(az acr show --name "$REGISTRO_NOMBRE" --query loginServer --output tsv)
USUARIO=$(az acr credential show --name "$REGISTRO_NOMBRE" --query username --output tsv)
CLAVE=$(az acr credential show --name "$REGISTRO_NOMBRE" --query 'passwords[0].value' --output tsv)

titulo "Registro listo"
echo "  Servidor : $SERVIDOR"
echo ""
echo "  Estos valores permiten autenticarse a mano contra el registro."
echo "  Las canalizaciones NO los necesitan: usan una conexion de servicio."
echo ""
echo "    REGISTRO_SERVIDOR = $SERVIDOR"
echo "    REGISTRO_USUARIO  = $USUARIO"
echo "    REGISTRO_CLAVE    = $CLAVE"
echo ""
aviso "La clave es una credencial real: no la pegue en el informe ni la muestre"
aviso "en pantalla durante la presentación grabada."
