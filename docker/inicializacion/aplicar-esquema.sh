#!/bin/bash
# =============================================================================
#  Contenedor de inicialización de la base de datos.
#
#  Se ejecuta UNA vez por despliegue, aplica el esquema y los datos, y termina.
#  Los otros tres contenedores siguen corriendo mientras tanto: es exactamente
#  la independencia de tiempos de ejecución que la experiencia pide demostrar.
#
#  POR QUÉ UN CONTENEDOR PROPIO Y NO CÓDIGO DENTRO DE LA APLICACIÓN
#    - Se ejecuta una vez por despliegue y no en cada arranque del proceso.
#    - Su política de reinicio es distinta: los servicios permanentes se
#      reinician si se caen; éste no, porque un proceso que terminó bien no
#      debe relanzarse. Con la política de los demás, Docker lo ejecutaría en
#      bucle indefinidamente.
#    - Si falla, el despliegue se detiene y la aplicación no llega a levantarse
#      contra una base a medio construir.
#
#  POR QUÉ REUTILIZA LA IMAGEN DEL MOTOR
#    Porque ya está descargada para el servicio de datos y trae sqlcmd. No
#    agrega ni una descarga ni un megabyte al despliegue, y aun así se ejecuta
#    como una unidad completamente separada, con su propio ciclo de vida.
# =============================================================================

set -euo pipefail

SQLCMD=/opt/mssql-tools18/bin/sqlcmd
SERVIDOR="${SQL_SERVIDOR:-datos}"
USUARIO="${SQL_USUARIO:-sa}"
DIRECTORIO_SQL="${SQL_DIRECTORIO:-/sql}"

if [[ -z "${MSSQL_SA_PASSWORD:-}" ]]; then
    echo "ERROR: falta la variable MSSQL_SA_PASSWORD." >&2
    exit 1
fi

# -C confía en el certificado autofirmado del contenedor y -No no exige
# cifrado, que no aporta nada en una red interna de Docker que no sale a
# Internet. -b hace que sqlcmd devuelva un código de salida distinto de cero
# ante un error de SQL: sin esa opción, un script que falla termina "bien" y el
# despliegue continuaría sobre una base incompleta.
ejecutar_consulta() {
    "$SQLCMD" -S "$SERVIDOR" -U "$USUARIO" -P "$MSSQL_SA_PASSWORD" \
              -C -No -b -d "${2:-master}" -Q "$1"
}

ejecutar_archivo() {
    local archivo="$1"
    local base="${2:-Tecnica}"
    echo ""
    echo "--- Aplicando $(basename "$archivo") sobre [$base] ---"
    "$SQLCMD" -S "$SERVIDOR" -U "$USUARIO" -P "$MSSQL_SA_PASSWORD" \
              -C -No -b -d "$base" -i "$archivo"
}

# -----------------------------------------------------------------------------
#  1. Esperar a que el motor acepte conexiones
# -----------------------------------------------------------------------------
#  No basta con que el contenedor exista: SQL Server tarda en estar listo para
#  atender. Se espera a que responda una consulta real, no a que el puerto esté
#  abierto, porque el puerto abre antes de que el motor termine de arrancar.
echo "Esperando a que $SERVIDOR acepte conexiones..."

INTENTOS=60
for ((i = 1; i <= INTENTOS; i++)); do
    if ejecutar_consulta "SELECT 1" > /dev/null 2>&1; then
        echo "El motor respondió en el intento $i."
        break
    fi

    if (( i == INTENTOS )); then
        echo "ERROR: $SERVIDOR no respondió tras $INTENTOS intentos." >&2
        exit 1
    fi

    sleep 2
done

# -----------------------------------------------------------------------------
#  2. Aplicar los scripts, en orden
# -----------------------------------------------------------------------------
#  El orden importa y no es intercambiable:
#    00  crea la base y la tabla de origen con sus datos
#    01  construye el maestro de productos, la relación y la matriz mensual
#    02  analiza la calidad de los datos y reporta las anomalías
#    03  publica la vista que consume Power BI
#
#  Los cuatro son idempotentes, así que un segundo despliegue los vuelve a
#  aplicar sin duplicar nada.
ejecutar_archivo "$DIRECTORIO_SQL/00_base_y_datos_sinteticos.sql" "master"
ejecutar_archivo "$DIRECTORIO_SQL/01_esquema_y_matriz.sql"        "Tecnica"
ejecutar_archivo "$DIRECTORIO_SQL/02_analisis_datos.sql"          "Tecnica"
ejecutar_archivo "$DIRECTORIO_SQL/03_vista_powerbi.sql"           "Tecnica"

# -----------------------------------------------------------------------------
#  3. Dejar constancia de con qué quedó la base
# -----------------------------------------------------------------------------
echo ""
echo "--- Estado final de la base ---"
ejecutar_consulta \
    "SET NOCOUNT ON;
     SELECT CONCAT('ventas=',    (SELECT COUNT(*) FROM dbo.Ventas),
                   ' productos=',(SELECT COUNT(*) FROM dbo.Productos));" \
    "Tecnica"

echo ""
echo "Inicialización completada correctamente."
