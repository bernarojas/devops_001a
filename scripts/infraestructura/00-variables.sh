#!/usr/bin/env bash
# =============================================================================
#  Variables compartidas por los scripts de aprovisionamiento.
#
#  No se ejecuta solo: los demás scripts lo cargan con `source`.
#
#  Todo lo que define este archivo se puede sobrescribir desde el entorno antes
#  de invocar el aprovisionamiento, sin editar nada:
#
#      REGION=eastus2 bash scripts/infraestructura/aprovisionar.sh
# =============================================================================

# ${VAR:-valor} toma lo que venga del entorno y, si no viene nada, el valor por
# omisión. Es lo que permite parametrizar sin tocar el archivo.

# --- Grupo de recursos y región ----------------------------------------------
GRUPO_RECURSOS="${GRUPO_RECURSOS:-rg-devops-001a}"

# La región está impuesta por la suscripción: Azure for Students sólo habilita
# unas pocas, y ésta es la que tiene capacidad para la familia de máquinas que
# la cuota permite crear.
REGION="${REGION:-westus3}"

# --- Red ----------------------------------------------------------------------
RED_VIRTUAL="${RED_VIRTUAL:-vnet-devops}"
ESPACIO_RED="${ESPACIO_RED:-10.10.0.0/16}"

SUBRED_WEB="${SUBRED_WEB:-snet-web}"
RANGO_WEB="${RANGO_WEB:-10.10.1.0/24}"

SUBRED_DATOS="${SUBRED_DATOS:-snet-data}"
RANGO_DATOS="${RANGO_DATOS:-10.10.2.0/24}"

NSG_WEB="${NSG_WEB:-nsg-web}"
NSG_DATOS="${NSG_DATOS:-nsg-data}"

IP_PUBLICA="${IP_PUBLICA:-ip-web-publica}"

# --- Máquina virtual ----------------------------------------------------------
# Es una máquina NUEVA. La de la experiencia anterior, vm-web-01, se conserva
# o se elimina según convenga, pero el despliegue de esta experiencia apunta
# acá. Ver la advertencia sobre la cuota en 30-maquina-virtual.sh.
MAQUINA="${MAQUINA:-vm-web-02}"

# Standard_B2s son exactamente dos núcleos y 4 GB, que es el tamaño que el
# informe describe y el que sostiene el argumento de la contenerización: las
# tres capas juntas ocupan menos de un cuarto de esa memoria.
#
# Se prefiere sobre Standard_D2s_v3, que tiene 8 GB y cuesta más del doble.
TAMANO_MAQUINA="${TAMANO_MAQUINA:-Standard_B2s}"

# Regular o Spot.
#
# Spot sale mucho más barato y consume la cuota de prioridad baja en lugar de
# la normal, pero la familia B NO admite Spot: si se pide Spot hay que cambiar
# también el tamaño a uno que lo admita, por ejemplo Standard_D2s_v3.
#
#     PRIORIDAD=Spot TAMANO_MAQUINA=Standard_D2s_v3 bash aprovisionar.sh
#
# Ojo si se toma ese camino: esa máquina tiene 8 GB, no 4, y el informe habla
# de 4 GB en varios lugares.
PRIORIDAD="${PRIORIDAD:-Regular}"

IMAGEN_MAQUINA="${IMAGEN_MAQUINA:-Ubuntu2204}"
USUARIO_ADMIN="${USUARIO_ADMIN:-azureuser}"

# --- Registro de contenedores -------------------------------------------------
# El nombre del registro debe ser único en todo Azure y admite sólo minúsculas
# y dígitos. Si el que está por omisión ya está tomado, se pasa otro:
#     REGISTRO_NOMBRE=acrventasgrupo14 bash scripts/infraestructura/aprovisionar.sh
REGISTRO_NOMBRE="${REGISTRO_NOMBRE:-acrventasdevops001a}"
REGISTRO_SKU="${REGISTRO_SKU:-Basic}"

# --- Acceso administrativo ----------------------------------------------------
# Dirección desde la que se permite SSH. Vacío significa "detectarla sola".
# Nunca 0.0.0.0/0: abrir el 22 a Internet en una máquina con dirección pública
# es recibir intentos de acceso por fuerza bruta a los pocos minutos.
IP_ADMINISTRADOR="${IP_ADMINISTRADOR:-}"

# --- Ayudantes de salida ------------------------------------------------------
titulo()  { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }
paso()    { printf '  \033[0;36m->\033[0m %s\n' "$1"; }
listo()   { printf '  \033[0;32m[ OK ]\033[0m %s\n' "$1"; }
aviso()   { printf '  \033[0;33m[ ! ]\033[0m %s\n' "$1"; }
error()   { printf '  \033[0;31m[ERROR]\033[0m %s\n' "$1" >&2; }

# Comprueba que la CLI de Azure esté instalada y con sesión iniciada. Fallar
# acá con un mensaje claro ahorra descifrar un error de autenticación quince
# comandos más adelante.
verificar_sesion_azure() {
    if ! command -v az > /dev/null 2>&1; then
        error "No se encontró la CLI de Azure. Instalación: https://aka.ms/InstallAzureCLI"
        exit 1
    fi

    if ! az account show > /dev/null 2>&1; then
        error "No hay sesión iniciada en Azure. Ejecute:  az login"
        exit 1
    fi

    local suscripcion
    suscripcion=$(az account show --query name --output tsv)
    listo "Sesión activa en la suscripción: $suscripcion"
}
