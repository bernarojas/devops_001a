#!/usr/bin/env bash
# =============================================================================
#  MÁQUINA VIRTUAL
#
#  Crea la máquina que aloja la solución contenerizada, dentro de la subred de
#  presentación y detrás de la dirección pública estática.
#
#  EL TAMAÑO Y POR QUÉ IMPORTA
#  Standard_B2s: dos núcleos y 4 GB. Es el tamaño que describe el informe, y
#  es el que sostiene su argumento central: las tres capas contenerizadas
#  ocupan menos de un cuarto de esa memoria, mientras que tres máquinas
#  virtuales con tres sistemas operativos completos no habrían cabido.
#
#  SI LA CUOTA NO ALCANZA
#  Azure for Students a veces tiene la cuota de núcleos en cero para las
#  familias con capacidad en la región habilitada. En ese caso queda la cuota
#  de prioridad baja (Spot), que se activa con PRIORIDAD=Spot. La familia B no
#  admite Spot, así que hay que cambiar también el tamaño.
#
#  Con Spot, Azure puede desalojar la máquina si necesita la capacidad. La
#  política de desalojo se fija en Deallocate y no en Delete, de modo que la
#  máquina se detiene pero conserva su disco y su configuración. La dirección
#  pública es estática justamente por esto: sin eso, cada desalojo cambiaría la
#  dirección del sitio.
#
#  Uso:
#      bash scripts/infraestructura/30-maquina-virtual.sh
# =============================================================================

set -euo pipefail

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/infraestructura/00-variables.sh
source "$DIRECTORIO/00-variables.sh"

titulo "Máquina virtual $MAQUINA"
verificar_sesion_azure

# -----------------------------------------------------------------------------
#  Si ya existe, no se toca
# -----------------------------------------------------------------------------
if az vm show --resource-group "$GRUPO_RECURSOS" --name "$MAQUINA" > /dev/null 2>&1; then
    listo "La máquina $MAQUINA ya existe."
    ESTADO=$(az vm get-instance-view \
                --resource-group "$GRUPO_RECURSOS" --name "$MAQUINA" \
                --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" \
                --output tsv)
    echo "  Estado actual: $ESTADO"

    if [[ "$ESTADO" != "VM running" ]]; then
        paso "Iniciando la máquina..."
        az vm start --resource-group "$GRUPO_RECURSOS" --name "$MAQUINA" --output none
        listo "Máquina iniciada."
    fi
else
    # -------------------------------------------------------------------------
    #  Aviso sobre la cuota
    # -------------------------------------------------------------------------
    #  Si la máquina de la experiencia anterior sigue existiendo, es muy
    #  probable que esté consumiendo la única cuota de prioridad baja
    #  disponible. Mejor advertirlo antes que interpretar el error de cuota.
    if az vm show --resource-group "$GRUPO_RECURSOS" --name "vm-web-01" > /dev/null 2>&1; then
        aviso "La máquina vm-web-01 de la experiencia anterior todavía existe."
        aviso "La cuota de prioridad baja alcanza para una sola máquina de dos"
        aviso "núcleos, así que la creación de $MAQUINA probablemente falle."
        aviso "Para liberar la cuota, eliminándola con todos sus recursos:"
        aviso "    az vm delete -g $GRUPO_RECURSOS -n vm-web-01 --yes"
        echo ""
    fi

    paso "Creando $MAQUINA ($TAMANO_MAQUINA, prioridad $PRIORIDAD) en $SUBRED_WEB..."

    # --nsg "" es deliberado: la seguridad de red está definida A NIVEL DE
    # SUBRED. Si se creara además un grupo de seguridad por interfaz, habría
    # dos conjuntos de reglas que mantener sincronizados y el diagnóstico de
    # "por qué no pasa este tráfico" se volvería el doble de difícil.
    opciones=(
        --resource-group "$GRUPO_RECURSOS"
        --name            "$MAQUINA"
        --location        "$REGION"
        --image           "$IMAGEN_MAQUINA"
        --size            "$TAMANO_MAQUINA"
        --admin-username  "$USUARIO_ADMIN"
        --generate-ssh-keys
        --vnet-name       "$RED_VIRTUAL"
        --subnet          "$SUBRED_WEB"
        --public-ip-address "$IP_PUBLICA"
        --nsg             ""
        --os-disk-size-gb 64
        --output          none
    )

    if [[ "$PRIORIDAD" == "Spot" ]]; then
        # --max-price -1 significa "pagar hasta el precio bajo demanda", que es
        # lo que evita el desalojo por precio: sólo queda el desalojo por
        # capacidad. La política Deallocate conserva el disco, así que la
        # máquina vuelve tal como estaba cuando haya capacidad de nuevo.
        opciones+=(--priority Spot --max-price -1 --eviction-policy Deallocate)
    fi

    if az vm create "${opciones[@]}"; then
        listo "Máquina $MAQUINA creada."
    else
        error "No se pudo crear la máquina virtual."
        error ""
        error "La causa más frecuente en Azure for Students es la cuota de"
        error "núcleos. Para ver la situación real:"
        error "    az vm list-usage --location $REGION --output table"
        error ""
        error "Las salidas posibles, en orden de menor a mayor esfuerzo:"
        error "  1. Probar otra región:"
        error "       REGION=eastus2 bash $0"
        error "  2. Usar la cuota de prioridad baja, que suele estar libre"
        error "     cuando la normal está en cero. Ojo: la familia B no admite"
        error "     Spot, así que hay que cambiar también el tamaño, y esa"
        error "     máquina tiene 8 GB en lugar de 4:"
        error "       PRIORIDAD=Spot TAMANO_MAQUINA=Standard_D2s_v3 bash $0"
        error "  3. Si ya existe una máquina de una experiencia anterior,"
        error "     eliminarla para liberar su cuota."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
#  Datos de conexión
# -----------------------------------------------------------------------------
DIRECCION=$(az network public-ip show \
                --resource-group "$GRUPO_RECURSOS" \
                --name "$IP_PUBLICA" \
                --query ipAddress --output tsv)

titulo "Máquina virtual lista"
echo "  Nombre    : $MAQUINA ($TAMANO_MAQUINA, prioridad $PRIORIDAD)"
echo "  Subred    : $SUBRED_WEB"
echo "  Direccion : $DIRECCION"
echo ""
echo "  Conexion  : ssh $USUARIO_ADMIN@$DIRECCION"
echo ""
echo "  Siguiente paso, para instalar Docker y el agente de GitHub:"
echo "      bash scripts/infraestructura/40-preparar-maquina.sh"
