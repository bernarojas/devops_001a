# Puesta en marcha, paso a paso

Guía para crear la infraestructura en Microsoft Azure y dejar el despliegue
automático funcionando, partiendo de cero.

**Todos los comandos se ejecutan en Git Bash**, no en PowerShell ni en CMD.
En Windows: clic derecho en la carpeta del proyecto → *Git Bash Here*. Si no
aparece, abre Git Bash desde el menú Inicio y ve a la carpeta con:

```bash
cd /c/Users/Dev/Desktop/devops_001a
```

> **Antes de empezar, lee esto sobre el dinero.** Una suscripción Azure for
> Students trae 100 dólares de crédito. Lo que crea esta guía consume
> aproximadamente **35 dólares al mes si lo dejas encendido todo el tiempo**:
> unos 30 la máquina virtual y unos 5 el registro de imágenes. El paso 9
> explica cómo apagar la máquina cuando no la uses, que baja el gasto a casi
> nada. No apagues nada antes de grabar la presentación.

---

## Paso 1 — Instalar la CLI de Azure

Es el programa que permite crear recursos en Azure desde la línea de comandos.
No lo tienes instalado.

Abre **PowerShell como administrador** (solo para este paso) y ejecuta:

```
winget install -e --id Microsoft.AzureCLI
```

Si `winget` no existe en tu equipo, descarga el instalador desde
<https://aka.ms/installazurecliwindows> y ejecútalo.

**Después de instalar, cierra todas las ventanas de Git Bash y abre una
nueva.** Si no lo haces, el comando `az` no aparecerá.

Comprueba que quedó bien:

```bash
az version
```

Debe imprimir un bloque con números de versión. Si dice *command not found*,
la ventana es vieja: ciérrala y abre otra.

---

## Paso 2 — Iniciar sesión en Azure

```bash
az login
```

Se abre el navegador. Entra con tu **cuenta Duoc**. Al volver a la terminal
verás la lista de tus suscripciones.

Confirma cuál quedó activa:

```bash
az account show --output table
```

Si tienes más de una y la activa no es la de estudiante, cámbiala:

```bash
az account list --output table
az account set --subscription "NOMBRE DE LA SUSCRIPCION"
```

---

## Paso 3 — Comprobar que hay cuota de máquinas virtuales

Este es el paso que más problemas da en cuentas de estudiante, y conviene
mirarlo **antes** de intentar crear nada.

```bash
az vm list-usage --location westus3 --output table | grep -i "Standard BS"
```

Mira las columnas *CurrentValue* y *Limit*. Si el límite es **0**, esa región
no te sirve y hay que probar otra. Prueba en este orden:

```bash
az vm list-usage --location eastus2   --output table | grep -i "Standard BS"
az vm list-usage --location brazilsouth --output table | grep -i "Standard BS"
```

Anota la primera región donde el límite sea **2 o más**. La vas a usar en el
paso siguiente.

---

## Paso 4 — Crear toda la infraestructura

Un solo comando crea: el grupo de recursos, la red virtual con sus dos
subredes, los dos grupos de seguridad con sus reglas, la dirección IP pública
estática, el registro de contenedores y la máquina virtual.

Si la región del paso 3 fue `westus3` (la que viene por omisión):

```bash
bash scripts/infraestructura/aprovisionar.sh
```

Si fue otra, indícala así:

```bash
REGION=eastus2 bash scripts/infraestructura/aprovisionar.sh
```

Tarda entre 3 y 6 minutos. Vas a ver mensajes con `[ OK ]` a medida que
avanza.

**El nombre del registro debe ser único en todo Azure.** Si el script dice que
`acrventasdevops001a` no está disponible, elige otro (solo minúsculas y
números):

```bash
REGISTRO_NOMBRE=acrventasbberna bash scripts/infraestructura/aprovisionar.sh
```

### Al terminar, copia estos cuatro datos

El script los imprime. Guárdalos en un bloc de notas, los necesitas en el paso
siguiente:

| Dato | De dónde sale |
|---|---|
| Servidor del registro | línea `REGISTRO_SERVIDOR = ...` |
| Usuario del registro | línea `REGISTRO_USUARIO = ...` |
| Clave del registro | línea `REGISTRO_CLAVE = ...` |
| Dirección pública | línea `Direccion : ...` |

> La clave del registro es una **credencial real**. No la pegues en el
> informe, no la subas a GitHub y no la muestres en la grabación.

### Si falla la creación de la máquina

El script te dice qué hacer. El caso más común es cuota en cero, y la salida
es usar prioridad baja con otro tamaño:

```bash
PRIORIDAD=Spot TAMANO_MAQUINA=Standard_D2s_v3 bash scripts/infraestructura/30-maquina-virtual.sh
```

Ojo: esa máquina tiene **8 GB en lugar de 4**, y el informe menciona 4 GB en
varios lugares. Si terminas usándola, avísame y ajusto el texto.

---

## Paso 5 — Cargar los secretos en GitHub

Ve a tu repositorio en el navegador:

**Settings → Secrets and variables → Actions**

En la pestaña **Secrets**, botón *New repository secret*, crea estos cuatro.
Los nombres tienen que escribirse **exactamente así**:

| Nombre | Valor |
|---|---|
| `REGISTRO_SERVIDOR` | el servidor del registro del paso 4 |
| `REGISTRO_USUARIO` | el usuario del registro del paso 4 |
| `REGISTRO_CLAVE` | la clave del registro del paso 4 |
| `MSSQL_SA_PASSWORD` | una contraseña que inventes tú (ver abajo) |

La contraseña de la base de datos debe tener **al menos 8 caracteres, con
mayúsculas, minúsculas, números y algún símbolo**. Por ejemplo
`Ventas#2026!Duoc`. Anótala, la vas a necesitar si algún día entras a la base
a mano.

Después cambia a la pestaña **Variables**, botón *New repository variable*:

| Nombre | Valor |
|---|---|
| `DIRECCION_PUBLICA` | la dirección IP del paso 4 |

---

## Paso 6 — Instalar el agente en la máquina virtual

El agente es un programa que corre dentro de la máquina y se queda esperando
órdenes de GitHub. Es lo que permite desplegar sin abrir puertos.

Primero consigue el token, que **caduca en una hora**:

**Settings → Actions → Runners → New self-hosted runner**

Elige **Linux**. En la página aparece un comando largo con `--token` seguido
de un código. Copia solo ese código (empieza con una A y son unos 29
caracteres).

Ahora, en Git Bash:

```bash
bash scripts/infraestructura/40-preparar-maquina.sh \
     --repo bernarojas/devops_001a \
     --token PEGA_AQUI_EL_TOKEN
```

La primera vez te va a preguntar si confías en la máquina; responde `yes`.

Tarda unos 3 minutos: instala Docker, ajusta los límites que SQL Server
necesita y registra el agente como servicio.

Comprueba que quedó: vuelve a **Settings → Actions → Runners**. Debe aparecer
`vm-ventas` con un punto verde y la palabra **Idle**.

---

## Paso 7 — Subir el código a GitHub

Este es el momento en que todo se pone en marcha.

```bash
git push origin main
```

Ve a la pestaña **Actions** de tu repositorio. Vas a ver una ejecución
llamada *Entrega continua* que hace, en orden:

1. Compila el proyecto y ejecuta las 15 pruebas.
2. Construye las dos imágenes y las publica en el registro de Azure.
3. Le pide al agente de la máquina que las descargue y las levante.
4. Ejecuta las 14 comprobaciones.

La primera vez tarda entre 8 y 12 minutos, porque la máquina tiene que
descargar la imagen de SQL Server, que pesa 2,3 GB.

---

## Paso 8 — Comprobar que funciona

Abre en el navegador la dirección pública del paso 4:

```
http://LA-DIRECCION-IP
```

Deberías ver la misma aplicación que ya viste en local, pero ahora servida
desde Azure.

Para ver las comprobaciones, entra a la ejecución en **Actions**, abre el
trabajo *Desplegar en la máquina virtual* y busca el paso *Verificar la
solución desplegada*. Ahí está el resultado de las catorce.

Si quieres verlo desde dentro de la máquina:

```bash
ssh azureuser@LA-DIRECCION-IP
cd ~/actions-runner/_trabajo/devops_001a/devops_001a
docker compose -f docker-compose.prod.yml ps
bash scripts/despliegue/verificar-stack.sh
```

---

## Paso 9 — Cuidar el crédito

Mientras no estés trabajando ni grabando, apaga la máquina:

```bash
az vm deallocate --resource-group rg-devops-001a --name vm-web-02
```

*Deallocate* deja de cobrar el cómputo. El disco y la dirección IP se
conservan, así que al encenderla todo vuelve igual:

```bash
az vm start --resource-group rg-devops-001a --name vm-web-02
```

> Usa `deallocate` y no `stop`: apagar la máquina desde dentro con `stop` la
> deja reservada y **se sigue cobrando**.

Para ver cuánto crédito te queda: <https://portal.azure.com> → buscar
*Subscriptions* → tu suscripción → *Overview*.

---

## Paso 10 — Dar acceso al profesor

La actividad lo pide explícitamente.

**En GitHub:** Settings → Collaborators → *Add people* → el correo
institucional del docente.

**En Azure:** portal.azure.com → grupo de recursos `rg-devops-001a` →
*Control de acceso (IAM)* → *Agregar asignación de roles* → rol **Lector** →
el correo del docente.

Y en el informe, anexo E, escribe las dos direcciones:

- El repositorio: `https://github.com/bernarojas/devops_001a`
- El grupo de recursos en el portal de Azure

---

## Borrar todo cuando termine el semestre

Un solo comando elimina el grupo de recursos con absolutamente todo dentro.
**No se puede deshacer.**

```bash
az group delete --name rg-devops-001a --yes --no-wait
```

No lo ejecutes hasta tener la nota.

---

## Si algo falla

| Síntoma | Causa probable |
|---|---|
| `az: command not found` | La ventana de Git Bash es anterior a la instalación. Ábrela de nuevo. |
| El script dice que el nombre del registro no está disponible | Ya lo tomó otra persona en Azure. Usa `REGISTRO_NOMBRE=otro`. |
| No se puede crear la máquina, error de cuota | Prueba otra región, o prioridad baja. Ver paso 4. |
| El trabajo de despliegue queda en *Queued* para siempre | El agente no está registrado o está caído. Revisa el paso 6. |
| El despliegue falla con *permission denied* en el socket de Docker | La pertenencia al grupo docker no se aplicó. Reinicia la máquina: `az vm restart -g rg-devops-001a -n vm-web-02`. |
| La página no carga en el navegador | La máquina puede estar apagada. `az vm start` (paso 9). |
