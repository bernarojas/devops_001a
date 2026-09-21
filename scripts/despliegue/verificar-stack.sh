#!/usr/bin/env bash
# =============================================================================
#  VERIFICACIÓN DE LA SOLUCIÓN ORQUESTADA
#
#  Ejecuta catorce comprobaciones sobre la solución en marcha y devuelve un
#  código de salida distinto de cero si alguna falla.
#
#  POR QUÉ EXISTE
#  El informe no debe afirmar nada que no se pueda reproducir. Cada propiedad
#  que se describe —la segmentación de redes, el aislamiento de la capa de
#  datos, las cuotas, el puerto único— se comprueba acá contra el estado real
#  de Docker, no contra lo que dice el archivo de orquestación. Son cosas
#  distintas: el archivo declara una intención, y esto verifica el resultado.
#
#  Está incorporado a la etapa de despliegue de la canalización, de modo que
#  estas comprobaciones se ejecutan en cada publicación y no sólo cuando
#  alguien se acuerda.
#
#  Uso:
#      bash scripts/despliegue/verificar-stack.sh
#      bash scripts/despliegue/verificar-stack.sh --url http://20.10.1.5
# =============================================================================

set -uo pipefail

URL_BASE="http://127.0.0.1"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url) URL_BASE="$2"; shift 2 ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
done

PROXY=ventas-proxy
WEB=ventas-web
DATOS=ventas-datos
RED_BORDE=ventas-red-borde
RED_DATOS=ventas-red-datos

CORRECTAS=0
FALLAS=0

# -----------------------------------------------------------------------------
#  Ayudantes
# -----------------------------------------------------------------------------

# Compara lo obtenido con lo esperado e imprime una línea alineada. El valor
# obtenido se imprime SIEMPRE, también cuando la comprobación pasa: una línea
# que sólo dijera "OK" obligaría a volver a ejecutar los comandos a mano para
# saber qué se midió.
comprobar() {
    local descripcion="$1" esperado="$2" obtenido="$3"

    if [[ "$obtenido" == "$esperado" ]]; then
        printf '  %-7s %-50s %s\n' "[ OK ]" "$descripcion" "$obtenido"
        CORRECTAS=$((CORRECTAS + 1))
    else
        printf '  %-7s %-50s %s (se esperaba: %s)\n' \
               "[FALLA]" "$descripcion" "$obtenido" "$esperado"
        FALLAS=$((FALLAS + 1))
    fi
}

# Redes a las que pertenece un contenedor, ordenadas y sin el prefijo del
# proyecto, para que la salida se lea como el archivo de orquestación.
redes_de() {
    # awk NF descarta la línea vacía que deja el último salto de la plantilla.
    # Sin ese filtro, paste la toma como un campo más y devuelve ",red-borde".
    docker inspect -f \
        '{{range $nombre, $_ := .NetworkSettings.Networks}}{{$nombre}}{{"\n"}}{{end}}' \
        "$1" 2>/dev/null | sed 's/^ventas-//' | awk 'NF' | sort | paste -sd, -
}

codigo_http() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null || echo "sin-respuesta"
}

memoria_mb() {
    local bytes
    bytes=$(docker inspect -f '{{.HostConfig.Memory}}' "$1" 2>/dev/null || echo 0)
    echo $(( bytes / 1048576 ))
}

echo "==============================================================="
echo " Verificacion de la solucion orquestada   $(date '+%Y-%m-%d %H:%M')"
echo "==============================================================="

# -----------------------------------------------------------------------------
#  1. Estado de los contenedores
# -----------------------------------------------------------------------------
#  Informativo: muestra el panorama antes de entrar en el detalle.
echo ""
echo "1. Estado de los contenedores"
docker ps --filter "name=ventas-" \
          --format '{{.Names}}\t{{.Status}}' \
    | sed 's/^ventas-//' \
    | sort

# -----------------------------------------------------------------------------
#  2. Segmentación de redes            (5 comprobaciones)
# -----------------------------------------------------------------------------
#  El diseño completo se apoya en quién pertenece a qué red. Si el proxy
#  llegara a estar en la red de datos, el aislamiento de la base dejaría de
#  existir aunque todo lo demás siguiera igual.
echo ""
echo "2. Segmentacion de redes"
comprobar "el proxy solo ve la red de borde"       "red-borde"            "$(redes_de $PROXY)"
comprobar "la base solo ve la red de datos"        "red-datos"            "$(redes_de $DATOS)"
comprobar "la aplicacion es el unico puente"       "red-borde,red-datos"  "$(redes_de $WEB)"
comprobar "la red de datos es interna"             "true"  \
          "$(docker network inspect -f '{{.Internal}}' $RED_DATOS 2>/dev/null || echo desconocido)"
comprobar "la red de borde no es interna"          "false" \
          "$(docker network inspect -f '{{.Internal}}' $RED_BORDE 2>/dev/null || echo desconocido)"

# -----------------------------------------------------------------------------
#  3. Exposición hacia el anfitrión    (1 comprobación)
# -----------------------------------------------------------------------------
#  Se cuentan los contenedores del proyecto que publican algún puerto. Debe
#  ser exactamente uno. Es la comprobación que habría detectado el problema
#  del archivo de desarrollo, donde el motor de base de datos publicaba el
#  1433 hacia el anfitrión.
echo ""
echo "3. Exposicion hacia el anfitrion"
PUBLICAN=$(docker ps --filter "name=ventas-" --format '{{.Ports}}' \
           | grep -c '\->' || true)
comprobar "un unico contenedor publica puerto"     "1"  "$PUBLICAN"

# -----------------------------------------------------------------------------
#  4. Aislamiento de la capa de datos  (1 comprobación)
# -----------------------------------------------------------------------------
#  No basta con declarar la red como interna: hay que comprobar que el
#  contenedor efectivamente no consigue salir. Se intenta abrir una conexión
#  TCP a una dirección numérica —sin DNS de por medio, que en una red interna
#  fallaría por otro motivo y daría un falso positivo.
echo ""
echo "4. Aislamiento de la capa de datos"
SALIDA=$(docker exec "$DATOS" bash -c \
            'timeout 3 bash -c "echo > /dev/tcp/8.8.8.8/53" 2>/dev/null \
             && echo con-salida || echo sin-salida' 2>/dev/null \
         || echo sin-respuesta)
comprobar "la base no tiene ruta hacia Internet"   "sin-salida"  "$SALIDA"

# -----------------------------------------------------------------------------
#  5. Cuotas de recursos declaradas    (3 comprobaciones)
# -----------------------------------------------------------------------------
#  Se leen del contenedor en ejecución y no del archivo, que es la diferencia
#  entre comprobar y suponer.
echo ""
echo "5. Cuotas de recursos declaradas"
comprobar "memoria de ventas-proxy"                "128"   "$(memoria_mb $PROXY)"
comprobar "memoria de ventas-web"                  "640"   "$(memoria_mb $WEB)"
comprobar "memoria de ventas-datos"                "2048"  "$(memoria_mb $DATOS)"

# -----------------------------------------------------------------------------
#  6. Respuesta de los servicios       (4 comprobaciones)
# -----------------------------------------------------------------------------
#  Las cuatro pasan por el proxy, que es el único camino disponible desde
#  fuera. Cada una prueba un tramo distinto:
#    /proxy-salud  llega hasta nginx y vuelve
#    /salud        llega hasta la aplicación
#    /listo        llega hasta la base de datos
#    /             recorre además la capa de vistas
echo ""
echo "6. Respuesta de los servicios"
comprobar "GET /proxy-salud"                       "200"  "$(codigo_http "$URL_BASE/proxy-salud")"
comprobar "GET /salud"                             "200"  "$(codigo_http "$URL_BASE/salud")"
comprobar "GET /listo"                             "200"  "$(codigo_http "$URL_BASE/listo")"
comprobar "GET /"                                  "200"  "$(codigo_http "$URL_BASE/")"

# -----------------------------------------------------------------------------
#  7. Consumo real frente al límite
# -----------------------------------------------------------------------------
#  Informativo, y es el dato que sostiene el argumento de fondo: tres capas
#  independientes sobre una máquina de 4 GB. Tres máquinas virtuales no habrían
#  cabido.
echo ""
echo "7. Consumo real frente al limite"
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' \
             $PROXY $WEB $DATOS 2>/dev/null || echo "  (sin datos de consumo)"

# -----------------------------------------------------------------------------
#  Resumen
# -----------------------------------------------------------------------------
echo ""
echo "==============================================================="
if (( FALLAS == 0 )); then
    echo " $CORRECTAS comprobaciones correctas, 0 fallas"
    echo "==============================================================="
    exit 0
else
    echo " $CORRECTAS comprobaciones correctas, $FALLAS fallas"
    echo "==============================================================="
    # El código de salida distinto de cero es lo que permite que la
    # canalización marque el despliegue como fallido en lugar de darlo por
    # bueno porque los contenedores "arrancaron".
    exit 1
fi
