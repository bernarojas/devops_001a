# =============================================================================
#  Imagen de la aplicación web (MVC + API)
#
#  Construcción en dos etapas:
#    1. "build"   usa el SDK completo (~800 MB) para compilar y publicar.
#    2. "final"   usa sólo el runtime de ASP.NET (~220 MB) y copia el resultado.
#
#  Así la imagen final no arrastra el compilador ni el código fuente: pesa un
#  cuarto y expone mucha menos superficie.
#
#  Uso desde la raíz del repositorio:
#      docker build -f src/PruebaTecnica.Web/Dockerfile -t prueba-tecnica-web .
# =============================================================================

# --- Etapa 1: compilación ----------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /origen

# El .csproj se copia solo primero, y se restaura antes de traer el resto del
# código. Docker cachea cada capa: mientras las dependencias no cambien, un
# cambio en el código NO vuelve a descargar los paquetes NuGet.
COPY src/PruebaTecnica.Web/PruebaTecnica.Web.csproj src/PruebaTecnica.Web/
RUN dotnet restore src/PruebaTecnica.Web/PruebaTecnica.Web.csproj

COPY src/ src/
RUN dotnet publish src/PruebaTecnica.Web/PruebaTecnica.Web.csproj \
        --configuration Release \
        --no-restore \
        --output /publicado

# --- Etapa 2: ejecución ------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

# El idioma español se instala explícitamente. Las imágenes de .NET vienen en
# modo invariante de globalización, donde toda cultura se comporta como la
# invariante: sin esto, los montos saldrían con formato inglés (38,594,578,526)
# en lugar del chileno (38.594.578.526).
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false

# curl se instala junto con los locales, en la misma capa, porque la
# comprobación de estado del contenedor necesita un cliente HTTP y la imagen
# del runtime de ASP.NET no trae ninguno. Son unos dos megabytes; la
# alternativa —declarar la comprobación y que no exista la herramienta— deja
# el contenedor marcado como enfermo para siempre.
RUN apt-get update \
 && apt-get install -y --no-install-recommends locales curl \
 && sed -i '/es_CL.UTF-8/s/^# //g' /etc/locale.gen \
 && locale-gen \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /publicado .

# Usuario sin privilegios: si alguien lograra ejecutar código dentro del
# contenedor, no lo haría como root.
USER $APP_UID

EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080

# La comprobación se declara acá, dentro de la imagen, y no en el archivo de
# orquestación. Así viaja con el artefacto hasta el registro y cualquier
# orquestador que lo ejecute la hereda sin configuración adicional: quien sepa
# ejecutar la imagen sabe también cómo preguntarle si está sana.
#
# Consulta /salud, que NO toca la base de datos. Si consultara la base, una
# caída del motor haría que Docker reiniciara la aplicación en bucle, cuando
# la aplicación no tiene ningún problema.
#
# Se usa 127.0.0.1 y no "localhost": con el nombre, la resolución intenta IPv6
# primero y la comprobación falla con el servicio perfectamente sano.
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=5 \
    CMD curl -fsS http://127.0.0.1:8080/salud || exit 1

ENTRYPOINT ["dotnet", "PruebaTecnica.Web.dll"]
