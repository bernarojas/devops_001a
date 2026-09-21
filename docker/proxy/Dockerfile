# =============================================================================
#  Imagen del proxy inverso.
#
#  La configuración NO se monta desde un volumen ni se copia por SSH a la
#  máquina: se hornea dentro de la imagen. Es una decisión deliberada y es lo
#  que permite tratar la configuración como un artefacto más:
#
#    - se versiona junto al código y pasa por la misma revisión;
#    - se etiqueta con el número de compilación, igual que la aplicación;
#    - el despliegue no depende de que alguien haya dejado un archivo en el
#      lugar correcto de la máquina de destino;
#    - volver atrás es desplegar la etiqueta anterior, no editar un archivo
#      en el servidor.
#
#  Uso desde la raíz del repositorio:
#      docker build -f docker/proxy/Dockerfile -t ventas-proxy .
# =============================================================================

FROM nginx:1.27-alpine

# La configuración por omisión se elimina en lugar de dejarla al lado: si
# quedara, seguiría sirviendo la página de bienvenida de nginx en cualquier
# nombre de servidor que no coincida con el nuestro.
RUN rm -f /etc/nginx/conf.d/default.conf

# El script de arranque que la imagen trae para activar IPv6 reescribe
# /etc/nginx/conf.d, que con el sistema de archivos en modo de sólo lectura no
# es escribible. Se quita porque además no aplica: la red de Docker de este
# despliegue es IPv4.
RUN rm -f /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh

COPY docker/proxy/nginx.conf /etc/nginx/nginx.conf

# Falla la construcción si la configuración tiene un error de sintaxis, en vez
# de descubrirlo cuando el contenedor no arranque en la máquina de destino.
RUN nginx -t -c /etc/nginx/nginx.conf

EXPOSE 80

# La comprobación consulta 127.0.0.1 y no "localhost" a propósito.
#
# Con el nombre, wget resuelve primero ::1 y no reintenta en IPv4; nginx
# atiende sólo en IPv4, así que la comprobación fallaba con el servicio
# perfectamente sano. Una comprobación que falla estando todo bien es peor que
# no tener ninguna: Docker reinicia en bucle un contenedor que funciona.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://127.0.0.1/proxy-salud || exit 1

CMD ["nginx", "-g", "daemon off;"]
