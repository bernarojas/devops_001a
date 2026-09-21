# Puesta en marcha, paso a paso

Guía para crear la infraestructura en Microsoft Azure **desde el portal**, con
clics, y dejar el despliegue automático funcionando.

El repositorio incluye además scripts que crean exactamente lo mismo con un
comando (`scripts/infraestructura/`). Si en algún momento prefieres ese
camino, están documentados al final.

> **Antes de empezar, lee esto sobre el dinero.** Una suscripción Azure for
> Students trae 100 dólares de crédito. Lo que crea esta guía consume
> aproximadamente **35 dólares al mes si lo dejas encendido todo el tiempo**:
> unos 30 la máquina virtual y unos 5 el registro de imágenes. El apartado
> *Cuidar el crédito*, al final, explica cómo apagar la máquina cuando no la
> uses. No apagues nada antes de grabar la presentación.

### Lo que vas a crear

| Recurso | Nombre | Para qué |
|---|---|---|
| Grupo de recursos | `rg-devops-001a` | Contiene todo lo demás |
| Red virtual | `vnet-devops` | `10.10.0.0/16` |
| Subred de presentación | `snet-web` | `10.10.1.0/24` |
| Subred de datos | `snet-data` | `10.10.2.0/24` |
| Grupo de seguridad | `nsg-web` | Reglas de la capa web |
| Grupo de seguridad | `nsg-data` | Reglas de la capa de datos |
| Registro de contenedores | lo eliges tú | Guarda las imágenes |
| Dirección IP pública | `ip-web-publica` | Estática |
| Máquina virtual | `vm-web-02` | Ubuntu 22.04, 2 núcleos, 4 GB |

---

## Paso 0 — Comprobar qué hay y si alcanza la cuota

### 0.1 ¿Hay algo creado ya?

Portal → menú lateral → **Todos los recursos**.

- Si la lista sale vacía, perfecto: empieza en el paso 1.
- Si aparece `vm-web-01` o cualquier otra cosa, **avísame antes de seguir**.
  Puede que convenga reutilizarlo o borrarlo, y borrar sin mirar es mala idea.

### 0.2 ¿Hay cuota para crear una máquina?

Este es el paso que más problemas da en cuentas de estudiante y conviene
mirarlo **antes** de crear nada.

Portal → busca **Cuotas** en la barra de búsqueda → **Proceso**.

Arriba filtra por:

- **Suscripción:** la tuya
- **Región:** `Oeste de EE. UU. 3` (West US 3)
- En el buscador de la tabla escribe: `Standard BS`

Mira la fila **Standard BS Family vCPUs**. Necesitas que el **límite sea 2 o
más**.

Si el límite es 0, repite el filtro cambiando la región a `Este de EE. UU. 2`
y después a `Sur de Brasil`. **Anota la primera región donde haya cuota**: la
vas a usar en todos los pasos siguientes, y tiene que ser la misma en todos.

> De aquí en adelante, donde diga **«tu región»**, pon esa.

### 0.3 Averigua tu dirección IP

La vas a necesitar en el paso 3, para que solo tú puedas entrar por SSH.

Abre <https://ifconfig.me> en el navegador. Copia el número que salga, algo
como `190.44.12.87`. Anótalo.

---

## Paso 1 — Grupo de recursos

Es una carpeta que contiene todo lo demás. Sirve para borrarlo todo de una vez
cuando termine el semestre.

Portal → **Grupos de recursos** → **+ Crear**

| Campo | Valor |
|---|---|
| Suscripción | la tuya (Azure for Students) |
| Nombre del grupo de recursos | `rg-devops-001a` |
| Región | **tu región** |

**Revisar y crear** → **Crear**.

---

## Paso 2 — Red virtual con sus dos subredes

Portal → busca **Redes virtuales** → **+ Crear**

### Pestaña «Datos básicos»

| Campo | Valor |
|---|---|
| Grupo de recursos | `rg-devops-001a` |
| Nombre | `vnet-devops` |
| Región | **tu región** |

### Pestaña «Seguridad»

Déjalo todo desactivado. Azure Bastion, Firewall y Protección contra DDoS
cuestan dinero y no hacen falta acá.

### Pestaña «Direcciones IP»

Aquí está lo importante, y es donde más se equivoca la gente.

**1.** En **Espacio de direcciones IPv4**, si hay algo distinto de
`10.10.0.0/16`, bórralo y escribe `10.10.0.0/16`.

**2.** Abajo hay una tabla de subredes con una llamada `default`. Haz clic
sobre el nombre `default` para editarla:

| Campo | Valor |
|---|---|
| Nombre | `snet-web` |
| Intervalo de direcciones de subred | `10.10.1.0/24` |

Guardar.

**3.** Ahora **+ Agregar una subred**:

| Campo | Valor |
|---|---|
| Nombre | `snet-data` |
| Intervalo de direcciones de subred | `10.10.2.0/24` |

Agregar.

Deben quedar las dos en la tabla. **Revisar y crear** → **Crear**.

---

## Paso 3 — Grupo de seguridad de la capa web

Un grupo de seguridad de red es una lista de reglas que dice qué tráfico entra
y cuál no.

Portal → busca **Grupos de seguridad de red** → **+ Crear**

| Campo | Valor |
|---|---|
| Grupo de recursos | `rg-devops-001a` |
| Nombre | `nsg-web` |
| Región | **tu región** |

**Revisar y crear** → **Crear** → **Ir al recurso**.

Ahora, en el menú lateral del recurso: **Configuración → Reglas de seguridad
de entrada**. Vas a agregar cuatro reglas con **+ Agregar**.

### Regla 1 — permitir tráfico web

| Campo | Valor |
|---|---|
| Origen | `Service Tag` |
| Etiqueta de servicio de origen | `Internet` |
| Intervalos de puertos de origen | `*` |
| Destino | `Any` |
| Servicio | `Custom` |
| Intervalos de puertos de destino | `80` |
| Protocolo | `TCP` |
| Acción | `Permitir` |
| Prioridad | `100` |
| Nombre | `permitir-http` |

### Regla 2 — reservar HTTPS

Igual que la anterior, cambiando:

| Campo | Valor |
|---|---|
| Intervalos de puertos de destino | `443` |
| Prioridad | `110` |
| Nombre | `permitir-https` |

### Regla 3 — SSH solo desde tu casa

| Campo | Valor |
|---|---|
| Origen | `Direcciones IP` |
| Direcciones IP/CIDR de origen | **tu IP del paso 0.3**, así: `190.44.12.87/32` |
| Intervalos de puertos de origen | `*` |
| Destino | `Any` |
| Servicio | `SSH` |
| Protocolo | `TCP` |
| Acción | `Permitir` |
| Prioridad | `120` |
| Nombre | `permitir-ssh-administracion` |

> No pongas `Any` en el origen. Abrir el puerto 22 a todo Internet en una
> máquina con dirección pública significa recibir intentos de acceso por
> fuerza bruta a los pocos minutos. Esto es exactamente lo que el informe
> describe como mínimo privilegio.

### Regla 4 — denegar el resto, explícitamente

| Campo | Valor |
|---|---|
| Origen | `Service Tag` |
| Etiqueta de servicio de origen | `Internet` |
| Intervalos de puertos de origen | `*` |
| Destino | `Any` |
| Servicio | `Custom` |
| Intervalos de puertos de destino | `*` |
| Protocolo | `Any` |
| Acción | `Denegar` |
| Prioridad | `4096` |
| Nombre | `denegar-todo-lo-demas` |

> Azure ya deniega por omisión lo que no está permitido, así que esta regla no
> cambia el comportamiento. Se escribe igual, y es a propósito: una decisión de
> seguridad que no está escrita no se puede auditar. Quien revise esto en seis
> meses ve la intención declarada en vez de tener que deducirla. Si te lo
> preguntan en la presentación, esa es la respuesta.

---

## Paso 4 — Grupo de seguridad de la capa de datos

Portal → **Grupos de seguridad de red** → **+ Crear**

| Campo | Valor |
|---|---|
| Grupo de recursos | `rg-devops-001a` |
| Nombre | `nsg-data` |
| Región | **tu región** |

Crear → Ir al recurso → **Reglas de seguridad de entrada** → tres reglas:

### Regla 1 — SQL Server solo desde la capa web

| Campo | Valor |
|---|---|
| Origen | `Direcciones IP` |
| Direcciones IP/CIDR de origen | `10.10.1.0/24` |
| Intervalos de puertos de origen | `*` |
| Destino | `Any` |
| Servicio | `MS SQL` |
| Protocolo | `TCP` |
| Acción | `Permitir` |
| Prioridad | `100` |
| Nombre | `permitir-sql-desde-web` |

Fíjate en el origen: **no es Internet, es el rango de la subred web**. La base
solo acepta conexiones de la capa que efectivamente la consulta.

### Regla 2 — SSH solo desde la capa web

| Campo | Valor |
|---|---|
| Origen | `Direcciones IP` |
| Direcciones IP/CIDR de origen | `10.10.1.0/24` |
| Servicio | `SSH` |
| Protocolo | `TCP` |
| Acción | `Permitir` |
| Prioridad | `110` |
| Nombre | `permitir-ssh-desde-web` |

### Regla 3 — Internet no entra nunca

| Campo | Valor |
|---|---|
| Origen | `Service Tag` |
| Etiqueta de servicio de origen | `Internet` |
| Intervalos de puertos de destino | `*` |
| Protocolo | `Any` |
| Acción | `Denegar` |
| Prioridad | `4096` |
| Nombre | `denegar-internet` |

---

## Paso 5 — Conectar cada grupo de seguridad con su subred

Los grupos existen pero todavía no protegen nada. Hay que asociarlos.

Portal → **Redes virtuales** → `vnet-devops` → menú lateral **Subredes**.

**1.** Clic en `snet-web`. En el panel que se abre, busca **Grupo de seguridad
de red** y elige `nsg-web`. **Guardar**.

**2.** Clic en `snet-data`. Elige `nsg-data`. **Guardar**.

Comprueba que la tabla de subredes ahora muestre el grupo de seguridad en cada
fila. Si una queda vacía, el tráfico de esa subred no está filtrado.

---

## Paso 6 — Registro de contenedores

Aquí se guardan las imágenes que construye GitHub y que descarga la máquina.

Portal → busca **Registros de contenedor** → **+ Crear**

| Campo | Valor |
|---|---|
| Grupo de recursos | `rg-devops-001a` |
| Nombre del registro | ver abajo |
| Ubicación | **tu región** |
| Plan de tarifa (SKU) | `Básico` |

**El nombre debe ser único en todo Azure** y admite solo minúsculas y números,
sin guiones. Prueba con `acrventasbberna`. Si el portal dice que ya está
tomado, agrégale números hasta que te acepte.

**Revisar y crear** → **Crear** → **Ir al recurso**.

### Habilitar el usuario administrador

Menú lateral → **Configuración → Claves de acceso**.

Activa el interruptor **Usuario administrador**.

Aparecen tres datos. **Cópialos a un bloc de notas**, los necesitas en el paso
8:

| Lo que ves en el portal | Cómo lo llamaremos |
|---|---|
| Servidor de inicio de sesión | `REGISTRO_SERVIDOR` |
| Nombre de usuario | `REGISTRO_USUARIO` |
| Contraseña | `REGISTRO_CLAVE` |

> La contraseña es una **credencial real**. No la pegues en el informe, no la
> subas a GitHub y no la muestres en la grabación de la presentación.

---

## Paso 7 — Máquina virtual

Portal → **Máquinas virtuales** → **+ Crear** → **Máquina virtual de Azure**

### Pestaña «Datos básicos»

| Campo | Valor |
|---|---|
| Grupo de recursos | `rg-devops-001a` |
| Nombre de la máquina virtual | `vm-web-02` |
| Región | **tu región** |
| Opciones de disponibilidad | `No se requiere redundancia de infraestructura` |
| Imagen | `Ubuntu Server 22.04 LTS - x64 Gen2` |
| Arquitectura de VM | `x64` |
| Tamaño | **`Standard_B2s`** — 2 vCPU, 4 GiB |
| Tipo de autenticación | `Clave pública SSH` |
| Nombre de usuario | `azureuser` |
| Origen de la clave pública SSH | `Generar nuevo par de claves` |
| Nombre del par de claves | `vm-web-02_key` |
| **Puertos de entrada públicos** | **`Ninguno`** |

Para elegir el tamaño hay que pulsar **Ver todos los tamaños** y buscar
`B2s`. Son exactamente dos núcleos y 4 GB, que es el tamaño que describe el
informe.

**«Puertos de entrada públicos» en Ninguno es deliberado.** Los puertos ya los
controla `nsg-web` a nivel de subred. Si además los abres acá, quedan dos
juegos de reglas que mantener sincronizados y averiguar por qué no pasa un
tráfico se vuelve el doble de difícil.

### Pestaña «Discos»

| Campo | Valor |
|---|---|
| Tipo de disco del SO | `SSD estándar` (más barato que Premium) |

El resto por omisión.

### Pestaña «Redes»

| Campo | Valor |
|---|---|
| Red virtual | `vnet-devops` |
| Subred | `snet-web (10.10.1.0/24)` |
| Dirección IP pública | **Crear nuevo** (ver abajo) |
| Grupo de seguridad de red de NIC | **`Ninguno`** |

Al pulsar *Crear nuevo* en la dirección IP:

| Campo | Valor |
|---|---|
| Nombre | `ip-web-publica` |
| SKU | `Estándar` |
| Asignación | **`Estática`** |

> **Estática y no dinámica.** Una dirección dinámica se libera cada vez que la
> máquina se detiene, así que el sitio dejaría de responder en la misma
> dirección después de cada apagado. Como vas a apagar la máquina para no
> gastar crédito, con una dinámica tendrías que corregir el enlace del informe
> cada vez.

### Crear

**Revisar y crear** → **Crear**.

Aparece una ventana: **Descargar clave privada y crear recurso**. Púlsala. Se
descarga `vm-web-02_key.pem`.

**Ese archivo es la única forma de entrar a la máquina y no se puede volver a
descargar.** Muévelo a un lugar seguro, por ejemplo:

```
C:\Users\Dev\.ssh\vm-web-02_key.pem
```

Cuando termine, entra al recurso y **anota la dirección IP pública** que
aparece en la pantalla de información general.

---

## Paso 8 — Secretos y variable en GitHub

Ve a tu repositorio en el navegador:
**Settings → Secrets and variables → Actions**

En la pestaña **Secrets**, botón **New repository secret**, crea estos cuatro.
Los nombres se escriben **exactamente así**:

| Nombre | Valor |
|---|---|
| `REGISTRO_SERVIDOR` | del paso 6 |
| `REGISTRO_USUARIO` | del paso 6 |
| `REGISTRO_CLAVE` | del paso 6 |
| `MSSQL_SA_PASSWORD` | una contraseña que inventes (ver abajo) |

La contraseña de la base de datos necesita **al menos 8 caracteres, con
mayúsculas, minúsculas, números y algún símbolo**. Por ejemplo
`Ventas#2026!Duoc`. Anótala.

Cambia a la pestaña **Variables** → **New repository variable**:

| Nombre | Valor |
|---|---|
| `DIRECCION_PUBLICA` | la dirección IP del paso 7 |

---

## Paso 9 — Subir el código a GitHub

En Git Bash, desde la carpeta del proyecto:

```bash
git push origin main
```

Ve a la pestaña **Actions** del repositorio. Vas a ver la ejecución *Entrega
continua*:

- **Compilación y pruebas** — pasa en unos 2 minutos.
- **Publicar las imágenes en el registro** — unos 4 minutos.
- **Desplegar en la máquina virtual** — se queda en **Queued**.

Que se quede en cola es lo esperado: todavía no existe el agente que la
ejecute. Eso es el paso siguiente, y cuando termines, este trabajo arranca
solo.

---

## Paso 10 — Preparar la máquina virtual

Esta parte no se puede hacer con clics: instalar software dentro de la máquina
necesita una terminal.

### 10.1 Consigue el token del agente

En GitHub: **Settings → Actions → Runners → New self-hosted runner** → elige
**Linux**.

En la página aparece un comando largo con `--token` seguido de un código.
Copia **solo ese código** (empieza con A, unos 29 caracteres).

**Caduca en una hora**, así que hazlo justo antes del paso siguiente.

### 10.2 Entra por SSH

En Git Bash:

```bash
chmod 600 /c/Users/Dev/.ssh/vm-web-02_key.pem
ssh -i /c/Users/Dev/.ssh/vm-web-02_key.pem azureuser@LA-DIRECCION-IP
```

La primera vez pregunta si confías en la máquina: escribe `yes`.

Si se queda colgado sin conectar, la regla de SSH del paso 3 tiene tu IP mal,
o tu IP cambió. Vuelve a <https://ifconfig.me> y corrige la regla.

### 10.3 Ejecuta la preparación

Ya **dentro** de la máquina (el prompt dice `azureuser@vm-web-02`):

```bash
git clone https://github.com/bernarojas/devops_001a.git
cd devops_001a
bash scripts/infraestructura/preparar-maquina-desde-dentro.sh \
     --repo bernarojas/devops_001a \
     --token PEGA_AQUI_EL_TOKEN
```

Tarda unos 3 minutos. Instala Docker, ajusta los límites que SQL Server
necesita y registra el agente como servicio.

### 10.4 Sal y vuelve a entrar

Es necesario: el permiso para usar Docker solo se aplica al abrir sesión de
nuevo.

```bash
exit
```

Comprueba en **Settings → Actions → Runners** que aparece `vm-ventas` con un
punto verde y la palabra **Idle**.

---

## Paso 11 — El despliegue arranca solo

En cuanto el agente queda en *Idle*, el trabajo que estaba en cola empieza a
ejecutarse. Ve a **Actions** y míralo.

La primera vez tarda entre 8 y 12 minutos, porque la máquina descarga la
imagen de SQL Server, que pesa 2,3 GB.

Cuando termine en verde, abre en el navegador:

```
http://LA-DIRECCION-IP
```

Deberías ver la misma aplicación que ya viste en local, ahora servida desde
Azure.

Para ver las catorce comprobaciones: entra a la ejecución en **Actions** →
trabajo *Desplegar en la máquina virtual* → paso *Verificar la solución
desplegada*. **Esa pantalla es una buena captura para el anexo B del
informe.**

### Si el despliegue falla por permisos de Docker

Es el fallo más común y se arregla reiniciando la máquina: portal →
`vm-web-02` → **Reiniciar**. Después, en Actions, pulsa **Re-run jobs**.

---

## Paso 12 — Dar acceso al profesor

La actividad lo pide explícitamente.

**En GitHub:** Settings → Collaborators → **Add people** → el correo
institucional del docente.

**En Azure:** portal → `rg-devops-001a` → **Control de acceso (IAM)** →
**Agregar** → *Agregar asignación de roles* → rol **Lector** → el correo del
docente.

Y en el informe, anexo E, escribe:

- El repositorio: `https://github.com/bernarojas/devops_001a`
- El grupo de recursos `rg-devops-001a` en <https://portal.azure.com>

---

## Cuidar el crédito

Mientras no estés trabajando ni grabando, apaga la máquina.

Portal → `vm-web-02` → botón **Detener** (arriba). Azure pregunta si quieres
conservar la dirección IP: como es estática, se conserva igual.

Para volver: botón **Iniciar**. Tarda un minuto y todo vuelve como estaba.

> El botón *Detener* del portal libera el cómputo y deja de cobrarlo. Apagar la
> máquina desde dentro con `sudo poweroff` **no**: la deja reservada y se
> sigue cobrando.

Para ver cuánto crédito queda: portal → **Suscripciones** → la tuya →
**Información general**.

---

## Borrar todo al terminar el semestre

Portal → **Grupos de recursos** → `rg-devops-001a` → **Eliminar grupo de
recursos**. Pide escribir el nombre para confirmar.

Elimina absolutamente todo lo de esta guía y **no se puede deshacer**. No lo
hagas hasta tener la nota.

---

## Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| No aparece `Standard_B2s` entre los tamaños | Esa región no lo ofrece o no hay cuota. Vuelve al paso 0.2. |
| El nombre del registro no está disponible | Ya lo tomó alguien en Azure. Agrégale números. |
| `Permission denied (publickey)` al entrar por SSH | Falta `chmod 600` sobre el `.pem`, o la ruta al archivo está mal. |
| El SSH se queda colgado sin responder | Tu IP cambió. Actualiza la regla `permitir-ssh-administracion` del paso 3. |
| El trabajo de despliegue sigue en *Queued* | El agente no quedó registrado o está caído. Revisa el paso 10. |
| El despliegue falla con *permission denied* en el socket de Docker | Reinicia la máquina desde el portal y vuelve a lanzar el trabajo. |
| La página no carga | La máquina está detenida, o falta la regla `permitir-http` del paso 3. |

---

## Apéndice — El mismo resultado con un comando

Todo lo de los pasos 1 a 7 está escrito también como scripts, en
`scripts/infraestructura/`. Si alguna vez quieres reconstruir el ambiente
completo, o crear un segundo ambiente de pruebas, basta con:

```bash
az login
bash scripts/infraestructura/aprovisionar.sh
```

Son idempotentes: si un recurso ya existe, no lo recrean. Se pueden ejecutar
sobre un ambiente creado a mano y solo completarán lo que falte.

Se puede hacer sin instalar nada, desde **Azure Cloud Shell**: el icono `>_`
de la barra superior del portal abre una terminal en el navegador con la CLI
ya instalada y la sesión ya iniciada.
