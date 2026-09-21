#!/usr/bin/env bash
# =============================================================================
#  RED VIRTUAL, SUBREDES Y GRUPOS DE SEGURIDAD
#
#  Aprovisiona la red sobre la que corre la solución. Es IDEMPOTENTE: se puede
#  ejecutar las veces que haga falta; lo que ya existe no se recrea.
#
#  EL DISEÑO, EN UNA FRASE
#  Una red 10.10.0.0/16 partida en dos subredes —presentación y datos— cada una
#  con su propio grupo de seguridad y reglas de mínimo privilegio.
#
#  POR QUÉ SE ESCRIBEN LAS REGLAS DE DENEGACIÓN SI AZURE YA DENIEGA POR OMISIÓN
#  Porque una decisión de seguridad que no está escrita no se puede auditar.
#  Quien revise esta configuración dentro de seis meses verá la intención
#  declarada, y no tendrá que deducirla de lo que falta.
#
#  Uso:
#      bash scripts/infraestructura/10-red.sh
# =============================================================================

set -euo pipefail

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/infraestructura/00-variables.sh
source "$DIRECTORIO/00-variables.sh"

titulo "Red virtual y seguridad"
verificar_sesion_azure

# -----------------------------------------------------------------------------
#  Dirección del administrador
# -----------------------------------------------------------------------------
if [[ -z "$IP_ADMINISTRADOR" ]]; then
    paso "Detectando la dirección pública de esta máquina..."
    IP_ADMINISTRADOR="$(curl -fsS --max-time 10 https://api.ipify.org || true)"

    if [[ -z "$IP_ADMINISTRADOR" ]]; then
        error "No se pudo detectar la dirección. Indíquela a mano:"
        error "    IP_ADMINISTRADOR=203.0.113.7 bash scripts/infraestructura/10-red.sh"
        exit 1
    fi
fi
listo "SSH se permitirá únicamente desde $IP_ADMINISTRADOR"

# -----------------------------------------------------------------------------
#  Grupo de recursos
# -----------------------------------------------------------------------------
if az group show --name "$GRUPO_RECURSOS" > /dev/null 2>&1; then
    listo "El grupo de recursos $GRUPO_RECURSOS ya existe."
else
    paso "Creando el grupo de recursos $GRUPO_RECURSOS en $REGION..."
    az group create --name "$GRUPO_RECURSOS" --location "$REGION" --output none
    listo "Grupo de recursos creado."
fi

# -----------------------------------------------------------------------------
#  Grupos de seguridad de red
# -----------------------------------------------------------------------------
crear_nsg() {
    local nombre="$1"
    if az network nsg show --resource-group "$GRUPO_RECURSOS" --name "$nombre" > /dev/null 2>&1; then
        listo "El grupo de seguridad $nombre ya existe."
    else
        paso "Creando el grupo de seguridad $nombre..."
        az network nsg create \
            --resource-group "$GRUPO_RECURSOS" \
            --name "$nombre" \
            --location "$REGION" \
            --output none
        listo "Grupo de seguridad $nombre creado."
    fi
}

# `az network nsg rule create` sobrescribe la regla si ya existe con el mismo
# nombre, de modo que volver a ejecutar el script converge al estado descrito
# acá en lugar de fallar. Eso es lo que hace idempotente al aprovisionamiento.
regla() {
    local nsg="$1" nombre="$2" prioridad="$3" direccion="$4" acceso="$5"
    local protocolo="$6" origen="$7" puertos="$8" descripcion="$9"

    az network nsg rule create \
        --resource-group "$GRUPO_RECURSOS" \
        --nsg-name "$nsg" \
        --name "$nombre" \
        --priority "$prioridad" \
        --direction "$direccion" \
        --access "$acceso" \
        --protocol "$protocolo" \
        --source-address-prefixes "$origen" \
        --destination-port-ranges "$puertos" \
        --description "$descripcion" \
        --output none
    listo "$nsg / $nombre"
}

crear_nsg "$NSG_WEB"
crear_nsg "$NSG_DATOS"

paso "Aplicando las reglas de $NSG_WEB (capa de presentación)..."
regla "$NSG_WEB" "permitir-http"  100 Inbound Allow Tcp "Internet"        "80"  \
      "Trafico web desde Internet hacia el proxy inverso."
regla "$NSG_WEB" "permitir-https" 110 Inbound Allow Tcp "Internet"        "443" \
      "Reservado para cuando se incorpore TLS en el proxy."
regla "$NSG_WEB" "permitir-ssh-administracion" 120 Inbound Allow Tcp "$IP_ADMINISTRADOR" "22" \
      "Administracion unicamente desde la direccion del administrador."
# Prioridad 4096, la más baja posible: se evalúa después de todas las reglas
# anteriores y cierra explícitamente lo que no se permitió.
regla "$NSG_WEB" "denegar-todo-lo-demas" 4096 Inbound Deny "*" "Internet" "*" \
      "Denegacion explicita del resto del trafico entrante."

paso "Aplicando las reglas de $NSG_DATOS (capa de datos)..."
# El origen NO es Internet ni "*": es el rango de la subred web. La capa de
# datos sólo acepta conexiones de la capa que efectivamente la consulta.
regla "$NSG_DATOS" "permitir-sql-desde-web" 100 Inbound Allow Tcp "$RANGO_WEB" "1433" \
      "SQL Server accesible solo desde la subred de presentacion."
regla "$NSG_DATOS" "permitir-ssh-desde-web" 110 Inbound Allow Tcp "$RANGO_WEB" "22" \
      "Administracion de la capa de datos solo a traves de la capa web."
regla "$NSG_DATOS" "denegar-internet" 4096 Inbound Deny "*" "Internet" "*" \
      "La capa de datos no recibe trafico de Internet en ningun caso."

# -----------------------------------------------------------------------------
#  Red virtual y subredes
# -----------------------------------------------------------------------------
if az network vnet show --resource-group "$GRUPO_RECURSOS" --name "$RED_VIRTUAL" > /dev/null 2>&1; then
    listo "La red virtual $RED_VIRTUAL ya existe."
else
    paso "Creando la red virtual $RED_VIRTUAL ($ESPACIO_RED)..."
    az network vnet create \
        --resource-group "$GRUPO_RECURSOS" \
        --name "$RED_VIRTUAL" \
        --location "$REGION" \
        --address-prefixes "$ESPACIO_RED" \
        --subnet-name "$SUBRED_WEB" \
        --subnet-prefixes "$RANGO_WEB" \
        --output none
    listo "Red virtual creada con la subred $SUBRED_WEB."
fi

crear_subred() {
    local nombre="$1" rango="$2" nsg="$3"

    if az network vnet subnet show \
            --resource-group "$GRUPO_RECURSOS" \
            --vnet-name "$RED_VIRTUAL" \
            --name "$nombre" > /dev/null 2>&1; then
        paso "La subred $nombre ya existe: se asegura su grupo de seguridad."
        az network vnet subnet update \
            --resource-group "$GRUPO_RECURSOS" \
            --vnet-name "$RED_VIRTUAL" \
            --name "$nombre" \
            --network-security-group "$nsg" \
            --output none
    else
        paso "Creando la subred $nombre ($rango)..."
        az network vnet subnet create \
            --resource-group "$GRUPO_RECURSOS" \
            --vnet-name "$RED_VIRTUAL" \
            --name "$nombre" \
            --address-prefixes "$rango" \
            --network-security-group "$nsg" \
            --output none
    fi
    listo "Subred $nombre asociada a $nsg."
}

crear_subred "$SUBRED_WEB"   "$RANGO_WEB"   "$NSG_WEB"
crear_subred "$SUBRED_DATOS" "$RANGO_DATOS" "$NSG_DATOS"

# -----------------------------------------------------------------------------
#  Dirección IP pública
# -----------------------------------------------------------------------------
#  ESTÁTICA y no dinámica, y la diferencia importa: una dirección dinámica se
#  libera cada vez que la máquina se detiene, de modo que el sitio dejaría de
#  responder en la misma dirección después de cada apagado. En una máquina de
#  prioridad baja, que Azure puede desalojar, eso ocurriría a menudo.
if az network public-ip show --resource-group "$GRUPO_RECURSOS" --name "$IP_PUBLICA" > /dev/null 2>&1; then
    listo "La dirección pública $IP_PUBLICA ya existe."
else
    paso "Creando la dirección pública estática $IP_PUBLICA..."
    az network public-ip create \
        --resource-group "$GRUPO_RECURSOS" \
        --name "$IP_PUBLICA" \
        --location "$REGION" \
        --sku Standard \
        --allocation-method Static \
        --output none
    listo "Dirección pública creada."
fi

DIRECCION=$(az network public-ip show \
                --resource-group "$GRUPO_RECURSOS" \
                --name "$IP_PUBLICA" \
                --query ipAddress --output tsv)

titulo "Red lista"
echo "  Grupo de recursos : $GRUPO_RECURSOS ($REGION)"
echo "  Red virtual       : $RED_VIRTUAL  $ESPACIO_RED"
echo "  Subred web        : $SUBRED_WEB   $RANGO_WEB   -> $NSG_WEB"
echo "  Subred datos      : $SUBRED_DATOS $RANGO_DATOS -> $NSG_DATOS"
echo "  Direccion publica : $DIRECCION (estatica)"
