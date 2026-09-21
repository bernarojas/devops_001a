#!/usr/bin/env bash
# =============================================================================
#  GENERACIÓN DE EVIDENCIA PARA EL ANEXO DEL INFORME
#
#  Recoge el estado real de la solución en marcha y lo deja en un archivo de
#  texto listo para adjuntar.
#
#  POR QUÉ UN SCRIPT Y NO CAPTURAS DE PANTALLA PEGADAS A MANO
#  Porque una captura no se puede volver a generar ni contrastar: si alguien
#  pregunta de cuándo es o con qué versión se tomó, no hay respuesta. Esto sí
#  se vuelve a ejecutar, y si la solución cambió, el archivo cambia con ella.
#  Las capturas siguen haciendo falta para el informe, pero como ilustración
#  de algo que además está escrito.
#
#  Uso:
#      bash scripts/despliegue/generar-evidencia.sh
#      bash scripts/despliegue/generar-evidencia.sh --salida /ruta/evidencia.txt
# =============================================================================

set -uo pipefail

SALIDA="evidencia-contenedores.txt"
URL_BASE="http://127.0.0.1"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --salida) SALIDA="$2";   shift 2 ;;
        --url)    URL_BASE="$2"; shift 2 ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
done

PROXY=ventas-proxy
WEB=ventas-web
DATOS=ventas-datos
MIGRACIONES=ventas-migraciones

seccion() { printf '\n----- %s %s\n' "$1" \
    "$(printf '%*s' $(( 70 - ${#1} )) '' | tr ' ' '-')"; }

codigo_http() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null || echo "---"
}

# Todo el cuerpo se agrupa y se redirige una sola vez al final: así el archivo
# se escribe completo o no se escribe, en lugar de quedar a medias si algo
# falla en el camino.
{
    echo "==============================================================================="
    echo " EVIDENCIA DE LA SOLUCION ORQUESTADA - ISY2201 Experiencia 2 (Semana 6)"
    echo " Generada el $(date '+%d-%m-%Y %H:%M')"
    echo "==============================================================================="

    seccion "1. CONTENEDORES EN EJECUCION"
    docker compose -f docker-compose.prod.yml ps \
        --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null

    seccion "2. IMAGENES Y SU TAMANO"
    printf '%-46s %s\n' "REPOSITORY:TAG" "SIZE"
    for contenedor in "$PROXY" "$WEB" "$DATOS"; do
        imagen=$(docker inspect -f '{{.Config.Image}}' "$contenedor" 2>/dev/null) || continue
        # El tamaño se toma de `docker image ls` y no de `docker image inspect`.
        # Con el almacén de imágenes de containerd, el campo .Size del inspect
        # devuelve el tamaño COMPRIMIDO del contenido (21 MB para el proxy),
        # mientras que lo que interesa informar es lo que ocupa desplegada
        # (73,7 MB). Son dos cifras distintas y la segunda es la relevante.
        tamano=$(docker image ls --format '{{.Size}}' --filter "reference=$imagen" | head -1)
        printf '%-46s %s\n' "$imagen" "${tamano:-desconocido}"
    done

    seccion "3. REDES: A QUE RED PERTENECE CADA CONTENEDOR"
    for contenedor in "$PROXY" "$WEB" "$DATOS" "$MIGRACIONES"; do
        redes=$(docker inspect -f \
            '{{range $n, $_ := .NetworkSettings.Networks}}{{$n}} {{end}}' \
            "$contenedor" 2>/dev/null | sed 's/ventas-//g')
        printf '%-22s %s\n' "$contenedor" "$redes"
    done
    echo ""
    for red in ventas-red-borde ventas-red-datos; do
        printf '%-22s internal=%s\n' "${red#ventas-}" \
            "$(docker network inspect -f '{{.Internal}}' "$red" 2>/dev/null || echo '?')"
    done

    seccion "4. CUOTAS DE RECURSOS APLICADAS"
    printf '%-22s %10s %8s\n' "CONTENEDOR" "MEMORIA" "VCPU"
    for contenedor in "$PROXY" "$WEB" "$DATOS" "$MIGRACIONES"; do
        memoria=$(docker inspect -f '{{.HostConfig.Memory}}' "$contenedor" 2>/dev/null || echo 0)

        # La cuota de CPU se puede expresar de dos formas y hay que mirar las
        # dos. Al declararla con `deploy.resources.limits.cpus`, Docker la
        # guarda en NanoCpus (mil millones = un núcleo); con la clave clásica
        # `cpus`, la guarda como cuota y período en microsegundos. Leer sólo
        # una de las dos informa "sin limite" sobre un contenedor que sí lo
        # tiene, que es peor que no informar nada.
        nanocpus=$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$contenedor" 2>/dev/null || echo 0)
        cuota=$(docker inspect -f '{{.HostConfig.CpuQuota}}' "$contenedor" 2>/dev/null || echo 0)
        periodo=$(docker inspect -f '{{.HostConfig.CpuPeriod}}' "$contenedor" 2>/dev/null || echo 0)

        if [[ "$nanocpus" -gt 0 ]]; then
            vcpu=$(awk "BEGIN { printf \"%.2f\", $nanocpus / 1000000000 }")
        elif [[ "$periodo" -gt 0 ]]; then
            vcpu=$(awk "BEGIN { printf \"%.2f\", $cuota / $periodo }")
        else
            vcpu="sin limite"
        fi

        printf '%-22s %7s MB %8s\n' "$contenedor" $(( memoria / 1048576 )) "$vcpu"
    done

    seccion "5. COMPROBACIONES DE ESTADO"
    for contenedor in "$PROXY" "$WEB" "$DATOS"; do
        printf '%-22s %s\n' "$contenedor" \
            "$(docker inspect -f '{{.State.Health.Status}}' "$contenedor" 2>/dev/null || echo 'sin comprobacion')"
    done

    seccion "6. CONTENEDOR DE INICIALIZACION (termino y no se reinicia)"
    echo "estado=$(docker inspect -f '{{.State.Status}}' $MIGRACIONES 2>/dev/null || echo '?')" \
         " codigo de salida=$(docker inspect -f '{{.State.ExitCode}}' $MIGRACIONES 2>/dev/null || echo '?')" \
         " politica de reinicio=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' $MIGRACIONES 2>/dev/null || echo '?')"
    echo ""
    echo "Ultima linea de su registro:"
    docker logs "$MIGRACIONES" 2>&1 | grep -E 'ventas=|completada' | tail -2

    seccion "7. RESPUESTA DE LOS SERVICIOS"
    for ruta in "/proxy-salud" "/salud" "/listo" "/" "/api/ventas?pagina=1&tamano=1"; do
        printf '%-36s HTTP %s\n' "GET $ruta" "$(codigo_http "$URL_BASE$ruta")"
    done

    seccion "8. CONSUMO REAL"
    docker stats --no-stream \
        --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' \
        "$PROXY" "$WEB" "$DATOS" 2>/dev/null

    echo ""
    echo "==============================================================================="
} > "$SALIDA"

echo "Evidencia escrita en: $SALIDA"
