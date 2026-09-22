# Configurar Azure Pipelines, paso a paso

El código y los archivos YAML viven en **GitHub**. El motor que los ejecuta es
**Azure Pipelines**. Esta guía cubre lo que hay que configurar en Azure DevOps
para que ese enlace funcione.

Los archivos de canalización ya están en el repositorio:

| Archivo | Cuándo se ejecuta |
|---|---|
| [`azure-pipelines-integracion-continua.yml`](../azure-pipelines-integracion-continua.yml) | Solicitudes de cambios y ramas de trabajo |
| [`azure-pipelines-entrega-continua.yml`](../azure-pipelines-entrega-continua.yml) | Al integrar en `main` |
| [`azure-pipelines-revertir-version.yml`](../azure-pipelines-revertir-version.yml) | A mano, indicando una etiqueta |
| [`pipelines/plantilla-compilar-y-probar.yml`](../pipelines/plantilla-compilar-y-probar.yml) | Plantilla que incluyen las dos primeras |

---

## Antes de empezar: limpiar los contenedores actuales

El archivo de orquestación ahora fija el nombre del proyecto en `ventas`, para
que cualquier agente lo administre igual sin importar desde qué carpeta
trabaje. Los contenedores que están corriendo se crearon con otro nombre de
proyecto, así que el primer despliegue chocaría con ellos.

Entra por SSH a la máquina y ejecútalo **una sola vez**:

```bash
ssh -i ~/.ssh/vm-web-01 azureuser@20.106.92.227
```

```bash
docker rm -f ventas-proxy ventas-web ventas-datos ventas-migraciones
```

> **Los datos no se pierden.** El volumen se llama `ventas-datos-volumen` de
> forma explícita, igual que las dos redes, así que no dependen del nombre del
> proyecto y sobreviven. El primer despliegue los vuelve a usar tal cual.

> Justamente por eso, la variable `MSSQL_SA_PASSWORD` de la canalización tiene
> que ser la **misma de antes**. Si no, la base queda inaccesible: ver el último
> apartado de esta guía.

---

## Paso 1 — Conexión de servicio con GitHub

Permite que Azure Pipelines lea el repositorio y reciba aviso de cada cambio.

**Azure DevOps** → proyecto `devops_001a` → abajo a la izquierda,
**Configuración del proyecto** → **Conexiones de servicio** → **Nueva conexión
de servicio** → **GitHub**.

| Campo | Valor |
|---|---|
| Método de autenticación | `AzureRepos` o `Grant authorization` (OAuth) |
| Nombre de la conexión | `github-devops001a` |
| Conceder permiso de acceso a todas las canalizaciones | marcado |

Autoriza en la ventana de GitHub que se abre.

---

## Paso 2 — Conexión de servicio con el registro de contenedores

Es la que permite publicar las imágenes en `acrventas` sin escribir la
contraseña en ningún archivo.

**Conexiones de servicio** → **Nueva conexión de servicio** → **Docker
Registry** → **Azure Container Registry**.

| Campo | Valor |
|---|---|
| Tipo de autenticación | `Service Principal` |
| Suscripción | Azure for Students |
| Registro de contenedor | `acrventas` |
| **Nombre de la conexión de servicio** | **`acrventas-conexion`** |
| Conceder permiso de acceso a todas las canalizaciones | marcado |

> ⚠️ **El nombre tiene que ser exactamente `acrventas-conexion`.** Es el que
> las canalizaciones esperan, en la variable `conexionRegistro`. Si prefieres
> otro, cámbialo también en los dos archivos YAML.

---

## Paso 3 — Entorno con la máquina virtual

Un *entorno* en Azure Pipelines representa el destino de un despliegue. Al
registrar en él un recurso de máquina virtual, Azure instala un agente dentro
de la máquina que **se conecta de salida** hacia Azure DevOps.

Esa dirección de la conexión es lo importante: no hay que abrir ningún puerto
de administración hacia Internet, ni autorizar rangos de direcciones de Azure
DevOps en el grupo de seguridad de red.

**Pipelines** → **Entornos** → **Nuevo entorno**

| Campo | Valor |
|---|---|
| Nombre | **`produccion`** |
| Recurso | **Máquinas virtuales** |

Siguiente. Azure muestra un **script de registro**; elige **Linux** y cópialo.

Ahora, en la sesión SSH de la máquina, pégalo y ejecútalo. Te preguntará:

| Pregunta | Respuesta |
|---|---|
| Environment Virtual Machine resource tags | deja vacío, Enter |
| Enter name for environment resource | **`vm-web-01`** |

> El nombre del recurso debe ser exactamente **`vm-web-01`**: es el que
> declaran las canalizaciones en `resourceName`.

Al terminar, el recurso aparece en el entorno con estado **Online**.

📸 **Evidencia:** esa pantalla del entorno con la máquina en línea.

---

## Paso 4 — La contraseña del motor de base de datos

Es el único secreto que las canalizaciones necesitan además de las conexiones
de servicio. Se define como **variable secreta**, nunca en el archivo YAML.

Se hace al crear cada canalización (paso 5), en **Variables**:

| Campo | Valor |
|---|---|
| Nombre | `MSSQL_SA_PASSWORD` |
| Valor | la misma contraseña que usaste en GitHub |
| **Mantener este valor secreto** | ✅ **marcado** |

Hay que definirla en las canalizaciones de **entrega** y de **reversión**. La
de integración continua no la necesita: no despliega nada.

> Marcar la casilla de secreto hace que Azure la enmascare en todos los
> registros de ejecución. Sin ella, aparecería en texto plano en cualquier paso
> que la imprima.

---

## Paso 5 — Crear las tres canalizaciones

Se repite tres veces el mismo procedimiento, cambiando sólo el archivo.

**Pipelines** → **Nueva canalización**

| Pantalla | Qué elegir |
|---|---|
| ¿Dónde está el código? | **GitHub** |
| Repositorio | `bernarojas/devops_001a` |
| Configura tu canalización | **Archivo YAML de Azure Pipelines existente** |
| Rama | `main` |
| Ruta | el archivo de la tabla de abajo |

| Canalización | Ruta | Nombre sugerido |
|---|---|---|
| Integración continua | `/azure-pipelines-integracion-continua.yml` | `Integración continua` |
| Entrega continua | `/azure-pipelines-entrega-continua.yml` | `Entrega continua` |
| Revertir versión | `/azure-pipelines-revertir-version.yml` | `Revertir a una versión anterior` |

En la pantalla de revisión, antes de guardar, usa el desplegable del botón para
**Guardar** sin ejecutar si todavía no tienes las variables puestas. Después,
en **Editar → Variables**, agregas `MSSQL_SA_PASSWORD` donde corresponda.

Para renombrar una canalización: en la lista, menú **⋯** → **Cambiar nombre o
mover**.

---

## Paso 6 — Ejecutar y verificar

Lanza **Entrega continua** a mano la primera vez: menú **Ejecutar
canalización** → rama `main` → **Ejecutar**.

Verás las tres etapas en orden:

```
Compilación y pruebas       →  15 pruebas
Publicar las imágenes       →  ventas-web y ventas-proxy en acrventas
Desplegar en la máquina     →  descarga, levanta y verifica
```

La primera ejecución tarda más porque la máquina descarga las imágenes de
nuevo. Las siguientes son de un par de minutos.

Cuando termine, abre en el navegador:

```
http://20.106.92.227
```

### Evidencias que conviene capturar

| # | Qué | Dónde |
|---|---|---|
| 1 | Las tres conexiones de servicio | Configuración del proyecto |
| 2 | El entorno con `vm-web-01` en línea | Pipelines → Entornos |
| 3 | Las tres canalizaciones en la lista | Pipelines |
| 4 | La ejecución con sus tres etapas en verde | La ejecución |
| 5 | El resumen de pruebas | Pestaña *Pruebas* de la ejecución |
| 6 | La salida de las catorce comprobaciones | Paso *Verificar la solución desplegada* |
| 7 | Las imágenes con su etiqueta en el registro | Portal de Azure → `acrventas` → Repositorios |
| 8 | La aplicación respondiendo | Navegador en la IP pública |

---

## Retirar el agente de GitHub Actions

Ya no se usa: las canalizaciones de GitHub Actions se eliminaron del
repositorio. El agente quedaría ocioso consumiendo memoria.

En la máquina virtual:

```bash
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
```

Y para darlo de baja del repositorio, en GitHub: **Settings → Actions →
Runners** → menú del agente → **Remove runner**.

> Puedes dejarlo instalado si prefieres conservar la opción de volver atrás.
> No estorba: sin archivos en `.github/workflows`, nunca recibe trabajo.

---

## Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| `Could not find service connection 'acrventas-conexion'` | El nombre de la conexión no coincide. Debe ser exactamente ese. |
| El despliegue queda esperando indefinidamente | El recurso del entorno no está en línea. Revisa el agente en la máquina. |
| `Conflict. The container name "/ventas-proxy" is already in use` | Falta la limpieza del apartado inicial de esta guía. |
| `permission denied` sobre el socket de Docker | El usuario del agente no está en el grupo `docker`. Reinicia la máquina desde el portal. |
| `datos` queda en `unhealthy` y nada más arranca | La contraseña de `MSSQL_SA_PASSWORD` no coincide con la que quedó grabada en el volumen. Ver el apartado siguiente. |
| La verificación falla en `GET /` | El proxy aún no terminó de arrancar, o el puerto 80 está ocupado por otro proceso. |

---

## La contraseña vive en el volumen, no en la variable

Ocurrió al migrar de GitHub Actions a Azure Pipelines, y cuesta un rato
entenderlo la primera vez.

SQL Server sólo lee `MSSQL_SA_PASSWORD` **cuando inicializa una base de datos
vacía**. A partir de ahí la contraseña queda guardada dentro del volumen y la
variable se ignora por completo. Si la canalización nueva trae otra, el motor
arranca igual —el proceso no tiene nada de malo— pero su sonda de salud inicia
sesión como `sa` y esa sesión falla:

```
Login failed for user 'sa'. Reason: Password did not match that for the login provided.
```

Como `datos` nunca pasa a *healthy*, la cadena de dependencias se detiene ahí:
`migraciones` no corre, y sin migraciones no arrancan `web` ni `proxy`. La
verificación termina con cinco comprobaciones en rojo —el puerto publicado y
las cuatro respuestas HTTP— que son consecuencia y no causa. Las de
segmentación de redes y las de cuotas de memoria siguen en verde, y eso mismo
es la pista: si la orquestación estuviera mal declarada, habrían caído también.

Se diagnostica en la máquina:

```bash
docker inspect --format '{{json .State.Health}}' ventas-datos | tail -c 600
docker logs --tail 20 ventas-datos
```

Y se resuelve de dos maneras. O se recupera la contraseña original —el `.env`
del despliegue anterior la conserva— y se corrige la variable secreta, o se
descarta el volumen para que la base se reconstruya:

```bash
docker rm -f ventas-datos ventas-migraciones ventas-web ventas-proxy
docker volume rm ventas-datos-volumen
```

Lo segundo no pierde nada. Los ocho productos, las 2.008 ventas y las ocho
anomalías los genera `sql/00_base_y_datos_sinteticos.sql` sin una sola llamada
a `RAND()`, de modo que la base resultante es idéntica registro por registro.
Es, de paso, la demostración práctica de que el ambiente se reconstruye desde
el repositorio.
