# Capa DevOps — contenedores, registro y CI/CD

Documentación de la infraestructura y el ciclo de entrega de la solución de
ventas. La aplicación en sí está documentada en el [README](../README.md).

El ciclo completo vive en **GitHub** (código y canalizaciones) y se despliega
sobre **Microsoft Azure** (registro de contenedores y máquina virtual).

---

## 1. El recorrido de un cambio

```
  commit en una rama
        │
        ▼
  GitHub · Integración continua          .github/workflows/integracion-continua.yml
        restaura, compila, 15 pruebas
        construye las 2 imágenes (sin publicar)
        valida la orquestación y los scripts
        │
        ▼  (al integrar en main)
  GitHub · Entrega continua              .github/workflows/entrega-continua.yml
        vuelve a compilar y probar
        construye y publica las 2 imágenes
        │
        ▼
  Azure Container Registry
        ventas-web:<n.º de ejecución>   + latest
        ventas-proxy:<n.º de ejecución> + latest
        │
        ▼  (agente autoalojado, dentro de la máquina)
  Máquina virtual · despliegue
        descarga las imágenes de esa etiqueta
        orquesta con Docker Compose
        ejecuta las 14 comprobaciones
```

La máquina virtual **no compila**: no tiene el SDK, ni el código fuente, ni
las dependencias de compilación. Sólo descarga y ejecuta. Es lo que garantiza
que el artefacto probado y el ejecutado sean literalmente el mismo.

---

## 2. Los cuatro contenedores

```
   Internet
      │  :80
      ▼
 ┌─ vm-web-01  (snet-web 10.10.1.0/24) ───────────────────────┐
 │                                                            │
 │   ┌─ red-borde (bridge) ────────────────────────────────┐  │
 │   │   ventas-proxy    nginx 1.27 / Alpine    128 MB     │  │
 │   │        │                                            │  │
 │   │        ▼                                            │  │
 │   │   ventas-web      ASP.NET Core 9         640 MB     │  │
 │   └────────┼────────────────────────────────────────────┘  │
 │            │                                               │
 │   ┌─ red-datos (internal: true) ────────────────────────┐  │
 │   │        ▼                                            │  │
 │   │   ventas-datos    SQL Server 2022       2048 MB     │  │
 │   │   ventas-migraciones  (vida corta)       256 MB     │  │
 │   │   volumen: ventas-datos-volumen                     │  │
 │   └─────────────────────────────────────────────────────┘  │
 └────────────────────────────────────────────────────────────┘
```

| Contenedor | Imagen | Runtime | Ciclo de vida | CPU y memoria |
|---|---|---|---|---|
| `ventas-proxy` | propia | nginx 1.27 sobre Alpine | permanente | 0,25 · 128 MB |
| `ventas-web` | propia | ASP.NET Core 9 sobre Debian | permanente | 0,75 · 640 MB |
| `ventas-datos` | Microsoft | SQL Server 2022 sobre Ubuntu | permanente | 1,00 · 2048 MB |
| `ventas-migraciones` | Microsoft | SQL Server 2022 (sólo `sqlcmd`) | vida corta | 0,50 · 256 MB |

### Independencia de códigos

Tres runtimes distintos que se actualizan por separado. La aplicación puede
pasar a .NET 10 sin tocar el proxy; el proxy puede recibir una corrección de
nginx sin recompilar la aplicación; el motor puede cambiar de versión sin que
los otros dos se enteren. Sobre un servidor tradicional, los tres compartirían
el mismo sistema operativo y cualquiera de esas actualizaciones exigiría
coordinar a las otras dos.

### Independencia de tiempos de ejecución

`ventas-migraciones` aplica el esquema y **termina**, mientras los otros tres
siguen corriendo. La aplicación declara `service_completed_successfully` sobre
él: si la inicialización falla, el despliegue se detiene y no se levanta una
aplicación contra una base a medio construir.

Su política de reinicio es `no` y la de los demás `unless-stopped`. La
diferencia es deliberada: un proceso que terminó su trabajo correctamente no
debe relanzarse. Con la política de los otros, Docker lo ejecutaría en bucle.

### Aislamiento de red

| Red | Contenedores | Característica |
|---|---|---|
| `red-borde` | `ventas-proxy`, `ventas-web` | Puente hacia el exterior |
| `red-datos` | `ventas-web`, `ventas-datos`, `ventas-migraciones` | `internal: true`: sin ruta hacia Internet |

La aplicación es el único contenedor que pertenece a ambas, y por lo tanto el
único puente entre el exterior y los datos. El proxy no alcanza la base —no
consigue siquiera resolver su nombre— y la base no alcanza al proxy.

**Sólo el proxy publica un puerto.** La aplicación y el motor son alcanzables
únicamente desde dentro de las redes de Docker.

### Cuotas de recursos

Sin límite, un contenedor con una fuga de memoria consume la del anfitrión y
el sistema operativo termina procesos hasta recuperarla: un problema en una
pieza derriba a las otras dos. Con límites, el problema queda contenido.

Al motor se le fija además un techo **interno** de 1536 MB
(`MSSQL_MEMORY_LIMIT_MB`). Ese segundo límite importa: SQL Server toma por
omisión toda la memoria que encuentra y, sin él, chocaría contra el límite del
contenedor y el sistema lo terminaría por falta de memoria, en lugar de que el
motor administre la suya.

Las cuotas se declaran con `deploy.resources.limits`, que es la clave que
también entiende Docker Swarm: el mismo archivo se despliega en un clúster sin
reescribirlo.

---

## 3. El registro de contenedores

Las imágenes se centralizan en **Azure Container Registry**, nivel Basic.

| Repositorio | Contenido | Etiquetas |
|---|---|---|
| `ventas-web` | Aplicación .NET 9 (MVC + API), construida en dos etapas | n.º de ejecución y `latest` |
| `ventas-proxy` | nginx con la configuración del proyecto ya incorporada | n.º de ejecución y `latest` |

La imagen del motor **no se republica**: se consume del registro público de
Microsoft. Copiarla agregaría más de dos gigabytes sin aportar nada, porque no
es una imagen que el equipo modifique.

### Por qué dos etiquetas

La numérica identifica una versión exacta y es **la que usa el despliegue**;
`latest` apunta siempre a la última y existe para consultas manuales.
Desplegar con `latest` sería cómodo y equivocado: dos máquinas que la
descargaran en momentos distintos podrían terminar ejecutando versiones
distintas, y no habría forma de saberlo.

### Qué mejora concretamente

- **Trazabilidad.** La etiqueta conecta la imagen en ejecución con el commit
  que la originó y con la ejecución que la construyó y la probó. El commit
  queda además grabado en los metadatos de la imagen
  (`org.opencontainers.image.revision`).
- **Reversión inmediata.** Volver atrás es desplegar otra etiqueta, no
  reconstruir nada. Está automatizado en
  [`revertir-version.yml`](../.github/workflows/revertir-version.yml).
- **La máquina deja de compilar.** Sobre dos núcleos, compilar competiría por
  los recursos con el servicio en producción.
- **Un solo origen para varios destinos.** El mismo registro puede alimentar
  hoy a la máquina virtual y mañana a Azure Container Apps o a un clúster.

### Limitación asumida

El acceso desde la máquina se resolvió con el **usuario administrador** del
registro. Es un compromiso documentado: esa credencial es única para todo el
registro y concede lectura y escritura, cuando la máquina sólo necesita
descargar.

Lo correcto es una identidad administrada con el rol `AcrPull`, que permite
únicamente descargar y no requiere contraseña. No se adoptó porque asignar ese
rol exige permisos sobre el directorio de la institución que una suscripción
Azure for Students no otorga.

---

## 4. Clasificación de las herramientas de orquestación

Orquestar no es lo mismo que ejecutar un contenedor. Un orquestador resuelve
al menos cinco problemas: el **orden de arranque** respetando dependencias y
estado de salud; el **ciclo de vida**, reiniciando lo que se cae; el
**descubrimiento**, para que un contenedor encuentre a otro por su nombre; el
**aislamiento**, definiendo quién habla con quién; y el **reparto de
recursos**.

| Herramienta | Qué es | Caso de uso en el que encaja |
|---|---|---|
| **Docker Compose** | Orquestador de un solo host | Pocos contenedores sobre una máquina; desarrollo y ambientes pequeños |
| **Docker Swarm** | Orquestador de clúster, integrado en Docker | Varios hosts con necesidad de réplicas, sin la complejidad de Kubernetes |
| **Azure Container Instances** | *Ejecuta* contenedores, **no los orquesta** | Trabajos por lotes, tareas puntuales de vida corta |
| **Azure Container Apps** | Servicio administrado sobre Kubernetes | Microservicios con escalado por demanda, sin operar el clúster |
| **Azure Kubernetes Service** | Kubernetes administrado | Decenas de servicios, varios equipos, políticas finas |
| **App Service para contenedores** | Alojamiento web administrado | Una aplicación web en un contenedor, sin varias piezas que coordinar |
| **Service Fabric** | Plataforma de microservicios con estado | Sistemas distribuidos con estado; poco frecuente en proyectos nuevos |

Dos aclaraciones que conviene no saltarse:

- **Azure Container Instances ejecuta contenedores pero no los orquesta**: no
  tiene escalado por métricas ni actualización progresiva.
- **GitHub Actions y Azure Pipelines tampoco son orquestadores de
  contenedores.** Orquestan el *despliegue*: deciden cuándo se construye una
  imagen, cuándo se publica y cuándo se le pide al orquestador del destino que
  la ponga en ejecución. Son planos distintos y conviven en este proyecto.

### Decisión adoptada: Docker Compose v2

El criterio no fue cuál es la herramienta más potente sino cuál es
**proporcionada al problema**:

1. Hay una sola máquina virtual, y un orquestador de clúster necesita un
   clúster.
2. La solución son cuatro contenedores. Compose cubre por completo los cinco
   problemas de la orquestación para ese tamaño.
3. El manifiesto no queda atrapado: las cuotas usan la clave que también
   entiende Swarm.
4. Las imágenes ya están en el registro: migrar no exigiría reconstruir nada.

**Camino de evolución.** Si apareciera la necesidad de alta disponibilidad o
escalado por demanda, la herramienta siguiente es **Azure Container Apps**;
para trabajos por lotes nocturnos, **Azure Container Instances**; y si el
proyecto creciera a decenas de servicios, **AKS**.

---

## 5. Las canalizaciones

| Archivo | Cuándo se ejecuta | Qué hace |
|---|---|---|
| [`compilar-y-probar.yml`](../.github/workflows/compilar-y-probar.yml) | invocado por las otras dos | Restaura, compila y ejecuta las 15 pruebas |
| [`integracion-continua.yml`](../.github/workflows/integracion-continua.yml) | solicitudes de cambios y ramas de trabajo | Pruebas, construcción de imágenes sin publicar, validación de la orquestación y `shellcheck` |
| [`entrega-continua.yml`](../.github/workflows/entrega-continua.yml) | al integrar en `main` | Pruebas, publicación en el registro y despliegue verificado |
| [`revertir-version.yml`](../.github/workflows/revertir-version.yml) | a mano, indicando una etiqueta | Despliega una versión anterior sin reconstruir nada |

La compilación y las pruebas viven en **un flujo reutilizable** que las otras
dos invocan. La alternativa —copiar los pasos— deja dos copias que se separan
con el tiempo, y la que se queda atrás suele ser la de despliegue: se termina
publicando sin haber ejecutado las pruebas.

### Por qué un agente autoalojado

El despliegue corre en un agente instalado **dentro de la máquina virtual**,
que se conecta **de salida** hacia GitHub. No hace falta abrir ningún puerto
de administración hacia Internet.

La alternativa —desplegar por SSH desde un agente alojado por GitHub—
obligaría a autorizar en el grupo de seguridad de red los rangos de
direcciones de GitHub, que son amplios y cambian con el tiempo. Eso desharía
buena parte del trabajo de segmentación de la Experiencia 1.

---

## 6. Puesta en marcha desde cero

> Esta sección es el resumen técnico. Para seguirlo paso a paso, con los
> comandos exactos, qué esperar en cada uno y qué hacer cuando algo falla,
> está [PUESTA-EN-MARCHA.md](PUESTA-EN-MARCHA.md).

### 6.1 Infraestructura

```bash
az login
bash scripts/infraestructura/aprovisionar.sh
```

Crea, de forma idempotente: el grupo de recursos, la red virtual
`10.10.0.0/16` con sus dos subredes, los dos grupos de seguridad con reglas de
mínimo privilegio, la dirección pública **estática**, el registro de
contenedores y la máquina virtual.

Todo se parametriza por entorno, sin editar archivos:

```bash
REGION=eastus2 REGISTRO_NOMBRE=acrventasgrupo14 bash scripts/infraestructura/aprovisionar.sh
```

### 6.2 Secretos y variables del repositorio

En **Settings → Secrets and variables → Actions**:

| Secreto | Valor |
|---|---|
| `REGISTRO_SERVIDOR` | servidor del registro, p. ej. `acrventas.azurecr.io` |
| `REGISTRO_USUARIO` | usuario administrador del registro |
| `REGISTRO_CLAVE` | contraseña del registro |
| `MSSQL_SA_PASSWORD` | contraseña del usuario `sa` |

| Variable | Valor |
|---|---|
| `DIRECCION_PUBLICA` | dirección pública de la máquina virtual |

Los tres primeros los imprime `20-registro.sh` al terminar.

### 6.3 Agente de GitHub en la máquina

El token de registro se obtiene en **Settings → Actions → Runners → New
self-hosted runner** y caduca en una hora.

```bash
bash scripts/infraestructura/40-preparar-maquina.sh \
     --repo bernarojas/devops_001a \
     --token AXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Instala Docker, ajusta los límites del sistema que SQL Server necesita y
registra el agente como servicio con las etiquetas `self-hosted, linux,
ventas`.

### 6.4 Desplegar

Integrar en `main`. El despliegue se dispara solo.

---

## 7. Verificación

```bash
bash scripts/despliegue/verificar-stack.sh
bash scripts/despliegue/generar-evidencia.sh
```

Catorce comprobaciones sobre la solución **en marcha**, no sobre el archivo de
orquestación: son cosas distintas, porque el archivo declara una intención y
esto verifica el resultado. El script está incorporado a la etapa de
despliegue, así que se ejecuta en cada publicación y devuelve un código
distinto de cero si algo falla.

| Grupo | Comprobaciones |
|---|---|
| Segmentación de redes | 5 |
| Exposición hacia el anfitrión | 1 |
| Aislamiento de la capa de datos | 1 |
| Cuotas de recursos | 3 |
| Respuesta de los servicios | 4 |

Resultado sobre el ambiente de validación del equipo: **14 correctas, 0
fallas**. Consumo real de las tres capas: unos **800 MB** de los 4 GB de la
máquina.

---

## 8. Probar la orquestación en una máquina local

```bash
cp .env.ejemplo .env      # completar REGISTRO, ETIQUETA y la contraseña

docker build -f src/PruebaTecnica.Web/Dockerfile -t local/ventas-web:prueba .
docker build -f docker/proxy/Dockerfile          -t local/ventas-proxy:prueba .

# con REGISTRO=local y ETIQUETA=prueba en el .env
docker compose -f docker-compose.prod.yml up -d
bash scripts/despliegue/verificar-stack.sh
```

---

## 9. Seguridad

| Problema del archivo de desarrollo | Cómo quedó |
|---|---|
| La aplicación y el motor publicaban su puerto | Sólo el proxy publica uno |
| Contraseña en texto plano y versionada | Llega del entorno; `.env` con permisos `600` y excluido de Git |
| Contenedores sin restricciones | Usuario sin privilegios, `no-new-privileges`, proxy en sólo lectura |

La base se puebla con **datos sintéticos** generados por un script versionado
—2.008 ventas y 8 productos, deterministas— y no con el respaldo de
información comercial real. Así el ambiente se reconstruye entero desde el
repositorio sin exponer datos de terceros.

---

## 10. Archivos

```
.github/workflows/
├── compilar-y-probar.yml         Flujo reutilizable: restaura, compila, prueba
├── integracion-continua.yml      Solicitudes de cambios y ramas de trabajo
├── entrega-continua.yml          Publicación en el registro y despliegue
└── revertir-version.yml          Reversión a una etiqueta anterior

docker/
├── proxy/
│   ├── Dockerfile                nginx 1.27, configuración horneada
│   └── nginx.conf                Resolución dinámica, /proxy-salud
└── inicializacion/
    └── aplicar-esquema.sh        Espera al motor y aplica los 4 scripts

scripts/
├── infraestructura/
│   ├── 00-variables.sh           Parámetros comunes
│   ├── 10-red.sh                 Red, subredes, grupos de seguridad, IP
│   ├── 20-registro.sh            Azure Container Registry
│   ├── 30-maquina-virtual.sh     Máquina virtual de prioridad baja
│   ├── 40-preparar-maquina.sh    Docker y agente de GitHub
│   └── aprovisionar.sh           Ejecuta todo en orden
└── despliegue/
    ├── verificar-stack.sh        14 comprobaciones
    └── generar-evidencia.sh      Evidencia reproducible para el anexo

docker-compose.prod.yml           Orquestación de producción
docker-compose.yml                Orquestación de desarrollo
.env.ejemplo                      Plantilla de variables
sql/00_base_y_datos_sinteticos.sql  Base y datos deterministas
tests/PruebaTecnica.Tests/        15 pruebas
```
