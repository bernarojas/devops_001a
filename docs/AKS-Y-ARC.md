# Clúster AKS y Azure Arc, paso a paso

Guía para crear un clúster de Azure Kubernetes Service, desplegar una
aplicación en él, registrarlo en Azure Arc y eliminarlo al terminar.

Sigue la actividad de la Semana 6 de la asignatura. Es un ejercicio
**independiente** de la solución de ventas: usa su propio grupo de recursos y
su propia región, y no toca nada de `rg-devops-001a`.

---

> ## ⛔ Estado: no se pudo ejecutar en esta suscripción
>
> **La suscripción Azure for Students del proyecto no permite crear el
> clúster.** El diagnóstico completo está en el apartado *Por qué no fue
> posible*, al final de este documento, y resumido en la sección 3.10 del
> informe.
>
> En una palabra: de los siete tamaños de dos núcleos disponibles en la única
> región elegible, los siete tienen cuota cero, y las once solicitudes de
> aumento fueron rechazadas.
>
> **El resto de la guía se conserva y es correcta** para cualquier suscripción
> sin esas restricciones. Si la cuota llega a otorgarse, o se dispone de otra
> suscripción, los pasos funcionan tal como están escritos.

---

> ## ⚠️ Lo primero: esto cuesta dinero mientras exista
>
> Los dos grupos de nodos son máquinas de 2 núcleos a unos **70 USD al mes
> cada una**. Con un nodo por grupo son unos **0,19 USD por hora**.
>
> Una sesión de tres horas cuesta menos de **0,60 USD**. Dejarlo encendido una
> semana se lleva **32 USD** de tus 100 de crédito.
>
> **La regla: crear → demostrar → capturar → eliminar el mismo día.** El último
> apartado de esta guía es justamente cómo eliminarlo, y no es opcional.

### La región

La actividad indica **East US 2**. Antes de darla por buena hay que comprobar
que la suscripción la admita: el desplegable de regiones del formulario de AKS
marca como «No apto» las que no puede usar.

En la suscripción de este proyecto la única elegible resultó ser West US 3. El
apartado del final lo detalla.

---

## Paso 0 — Comprobar que hay cuota

Dos nodos de 2 núcleos son 4 vCPU. Conviene mirarlo antes de empezar, porque
el error de cuota aparece recién al final de la creación, después de diez
minutos de espera.

Portal → busca **Cuotas** → primera tarjeta, **Compute**.

> El portal mezcla idiomas: el menú lateral está en español pero estas
> tarjetas aparecen en inglés. Busca **Compute**, no «Proceso».
>
> Tampoco entres por la tarjeta *Azure Kubernetes Service*: esa muestra cuotas
> propias del servicio, como cuántos clústeres puedes tener. Los núcleos de
> los nodos se cuentan en **Compute**, porque los nodos son máquinas
> virtuales.

Dentro, filtra por:

- **Suscripción:** Azure for Students
- **Región:** la que vayas a usar

Hay que mirar **dos** filas, y las dos tienen que alcanzar:

1. **vCPU regionales totales** — el techo de toda la región
2. La familia del tamaño que vayas a usar

Con dos nodos de dos núcleos necesitas **4 o más** en ambas.

> El límite regional manda sobre el de cada familia: da igual que una familia
> tenga 10 núcleos asignados si el techo de la región es 6, porque ese techo
> cuenta todo lo que se ejecute allí.

Lo medido en la suscripción de este proyecto está en el apartado *Por qué no
fue posible*, al final.

### Cómo elegir el tamaño

Un tamaño sirve sólo si cumple **tres** condiciones a la vez, y el portal
informa de cada una en un lugar distinto:

| Condición | Dónde se comprueba |
|---|---|
| La región es elegible para AKS | Desplegable *Región* del formulario |
| El tamaño está habilitado para la suscripción | Selector de tamaños: fuera del grupo «Tamaño no disponible» |
| Hay cuota en su familia | Pantalla de *Cuotas*, y el aviso de «núcleos restantes» del formulario |

El camino rápido para verlas juntas: en el selector de tamaños, aplica el
filtro **vCPU : 2**. Quedan a la vista todos los candidatos posibles de la
región, agrupados por disponibilidad. Después se cruza cada uno con la cuota
de su familia.

**Evitar los tamaños con `p` en el nombre** —`D2ps_v6`, `B2pts_v2`— porque son
ARM. Las imágenes de la tienda de Microsoft y las de `acrventas` están
compiladas para x86 y fallarían con `exec format error`.

### Sobre el escalado

Con 6 vCPU regionales, el máximo absoluto son **3 nodos** de 2 vCPU. La
configuración de la actividad —máximo 2 nodos en cada uno de los dos grupos—
permitiría llegar a 4 nodos, es decir 8 vCPU.

Sin carga el clúster nunca escala, así que no ocurre. Pero si alguna vez
apareciera un error de cuota al escalar, viene de ahí.

> Vale la pena decirlo en la presentación, porque refuerza el argumento de
> proporcionalidad: *«el clúster cabe en la cuota disponible con muy poco
> margen, de modo que escalar —la razón principal para adoptar Kubernetes— es
> justamente lo que esta suscripción no permite demostrar»*.

La máquina `vm-web-01` no consume esta cuota: es de otra familia (`D2ls_v7`) y
está en otra región.

---

## Paso 1 — Grupo de recursos para el clúster

Separado del de ventas, para poder borrarlo entero sin miedo.

Portal → **Grupos de recursos** → **+ Crear**

| Campo | Valor |
|---|---|
| Suscripción | Azure for Students |
| Nombre | `rg-aks-devops` |
| Región | la región elegible (ver el diagnóstico del final) |

**Revisar y crear** → **Crear**.

---

## Paso 2 — Crear el clúster

Portal → busca **Servicios de Kubernetes** → **+ Crear** → **Clúster de
Kubernetes**

> No elijas *«Clúster de Kubernetes automático»*. Esa variante administra las
> decisiones por ti y no te deja configurar los grupos de nodos, que es
> precisamente lo que la actividad pide mostrar.

### Pestaña «Datos básicos»

| Campo | Valor |
|---|---|
| Suscripción | Azure for Students |
| Grupo de recursos | `rg-aks-devops` |
| Configuración preestablecida del clúster | `Desarrollo/pruebas` |
| Nombre del clúster de Kubernetes | `aks-devops` |
| Región | la región elegible (ver el diagnóstico del final) |
| Plan de tarifa | `Gratis` |

El resto por omisión.

> *Desarrollo/pruebas* y plan *Gratis* van juntos: el plano de control no se
> cobra y solo pagas los nodos. Para producción se usaría *Estándar*, que
> añade acuerdo de nivel de servicio sobre el plano de control. Es una
> distinción que conviene mencionar si te preguntan.

### Pestaña «Grupos de nodos»

Aquí hay dos cosas que hacer.

**1. Ajustar el grupo que viene por omisión.** Haz clic en **`agentpool`**:

| Campo | Valor |
|---|---|
| Tamaño del nodo | uno que cumpla las tres condiciones de arriba |
| Recuento mínimo de nodos | `1` |
| Recuento máximo de nodos | `2` |

**Actualizar**.

**2. Agregar un segundo grupo.** Botón **+ Agregar grupo de nodos**:

| Campo | Valor |
|---|---|
| Nombre del grupo de nodos | `nplinux` |
| Modo | `Usuario` |
| Sistema operativo | `Ubuntu Linux` |
| Tamaño del nodo | el mismo que el otro grupo |
| Recuento mínimo de nodos | `1` |
| Recuento máximo de nodos | `2` |

**Agregar**.

> **Por qué dos grupos, que es lo que hay que saber explicar.** El grupo
> `agentpool` está en modo *sistema*: aloja los componentes internos de
> Kubernetes (DNS del clúster, métricas, el proxy de red). El grupo `nplinux`
> está en modo *usuario*: aloja tus aplicaciones.
>
> Separarlos evita que una aplicación que consume toda la memoria de un nodo
> tumbe con ella los servicios internos del clúster. **Es el mismo principio
> que las cuotas por contenedor de tu `docker-compose.prod.yml`**, aplicado un
> nivel más arriba: aislar para que un problema no se propague.

### Crear

**Revisar y crear** → **Crear**. Tarda entre 5 y 10 minutos.

📸 **Evidencia:** la pantalla de *Información general* del clúster cuando
termine, mostrando *Estado: Succeeded (Running)*, los dos grupos de nodos y la
versión de Kubernetes.

---

## Paso 3 — Conectarse al clúster

No hace falta instalar nada: se hace desde **Cloud Shell**, el icono `>_` de
la barra superior del portal.

La primera vez pide crear una cuenta de almacenamiento; acepta. Cuesta
céntimos y persiste tus archivos entre sesiones.

Cuando aparezca el prompt, elige **Bash** si te lo pregunta, y ejecuta:

```bash
az aks get-credentials --resource-group rg-aks-devops --name aks-devops
```

Eso descarga las credenciales y configura `kubectl` para hablar con tu
clúster. Ahora comprueba la conexión:

```bash
kubectl get nodes
```

Deben aparecer **dos nodos** en estado `Ready`, uno de cada grupo:

```
NAME                                 STATUS   ROLES   AGE   VERSION
aks-agentpool-xxxxxxxx-vmss000000    Ready    <none>  5m    v1.3x.x
aks-nplinux-xxxxxxxx-vmss000000      Ready    <none>  4m    v1.3x.x
```

📸 **Evidencia:** esta salida de `kubectl get nodes`.

---

## Paso 4 — Desplegar la aplicación

El manifiesto está versionado en tu repositorio, así que no hace falta
subirlo a mano. En Cloud Shell:

```bash
curl -sO https://raw.githubusercontent.com/bernarojas/devops_001a/main/k8s/aks-store-quickstart.yaml
```

Aplícalo:

```bash
kubectl apply -f aks-store-quickstart.yaml
```

Verás una línea `created` por cada objeto: los *deployments*, los *services*,
el *configmap*. Nueve objetos en total.

Espera a que los pods arranquen:

```bash
kubectl get pods
```

Repite el comando hasta que los cuatro estén `Running` con `1/1` en READY.
Tarda uno o dos minutos.

📸 **Evidencia:** la salida de `kubectl apply` con los objetos creados, y la
de `kubectl get pods` con los cuatro corriendo.

### Qué es cada cosa que acabas de desplegar

| Componente | Qué hace |
|---|---|
| `store-front` | La tienda que ve el cliente |
| `product-service` | Devuelve la información de los productos |
| `order-service` | Registra los pedidos |
| `rabbitmq` | Cola de mensajes entre el pedido y su procesamiento |

Fíjate en un detalle que ya conoces: `order-service` tiene un
**`initContainer`** llamado `wait-for-rabbitmq`, que espera a que la cola esté
disponible antes de arrancar el servicio.

**Es exactamente tu `ventas-migraciones`**: un contenedor de vida corta que
prepara el terreno y termina, y sin el cual el principal no arranca. El mismo
patrón, resuelto por Kubernetes en vez de por Docker Compose.

---

## Paso 5 — Probar la aplicación

El servicio `store-front` es de tipo `LoadBalancer`: Kubernetes le pide a
Azure una dirección IP pública. Tarda un par de minutos en asignarse.

```bash
kubectl get service store-front --watch
```

Al principio `EXTERNAL-IP` dice `<pending>`. Cuando aparezca la dirección,
**pulsa Ctrl+C** para salir del modo de vigilancia.

```
NAME          TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
store-front   LoadBalancer   10.0.35.248    20.7.228.39     80:31912/TCP
```

Abre esa `EXTERNAL-IP` en el navegador. Verás la tienda funcionando.

📸 **Evidencia:** la salida con la IP externa, y la tienda abierta en el
navegador con esa dirección en la barra.

> **Diferencia que vale la pena notar.** En tu máquina virtual, para exponer
> la aplicación tuviste que publicar el puerto 80 a mano y abrirlo en el grupo
> de seguridad de red. Acá pediste `type: LoadBalancer` y Kubernetes creó el
> balanceador, pidió la IP pública y configuró el enrutamiento solo.
>
> Eso es lo que compras con un orquestador de clúster, y también lo que
> cuesta: la infraestructura que lo hace posible son esos dos nodos a 70
> dólares al mes. **Para cuatro contenedores sobre una sola máquina, no
> compensa.** Ese es, en una frase, el argumento de la sección 3.6 de tu
> informe, ahora comprobado en los dos lados.

---

## Paso 6 — Registrar el clúster en Azure Arc

Azure Arc permite administrar desde el portal de Azure clústeres de Kubernetes
que **no están en Azure**: en otra nube, o en un servidor propio.

> Conectar un clúster de AKS a Arc es redundante —AKS ya es nativo de Azure y
> se ve en el portal sin Arc— y aquí se hace como ejercicio, para conocer el
> mecanismo. En un caso real, Arc se usaría con un clúster de Kubernetes
> instalado en un servidor de la propia institución. Conviene decirlo así si
> te preguntan: demuestra que entiendes para qué existe la herramienta.

### 6.1 Registrar los proveedores

En Cloud Shell:

```bash
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation
```

El registro tarda unos minutos. Comprueba cuándo termina:

```bash
az provider show --namespace Microsoft.Kubernetes --query "registrationState" -o tsv
```

Espera a que diga `Registered` antes de continuar. Repite el comando cada
minuto si hace falta.

### 6.2 Conectar el clúster

```bash
az connectedk8s connect --name aks-devops --resource-group rg-aks-devops
```

La primera vez, `az` pide instalar la extensión `connectedk8s`. Responde `Y`.

Tarda entre 5 y 10 minutos: instala agentes dentro del clúster. Puede mostrar
un aviso indicando que el clúster ya es de Azure; es esperable y no impide que
funcione.

📸 **Evidencia:** la salida del comando al terminar, y el recurso *Kubernetes:
Azure Arc* que aparece en el grupo `rg-aks-devops`.

### 6.3 Crear el token para ver los recursos desde el portal

Para que la vista de Arc muestre lo que hay dentro del clúster, hay que darle
una identidad con permiso de lectura.

```bash
kubectl create serviceaccount demo-user -n default
```

```bash
kubectl create clusterrolebinding demo-user-binding \
  --clusterrole cluster-admin --serviceaccount default:demo-user
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: demo-user-secret
  annotations:
    kubernetes.io/service-account.name: demo-user
type: kubernetes.io/service-account-token
EOF
```

Y obtén el token:

```bash
TOKEN=$(kubectl get secret demo-user-secret -o jsonpath='{$.data.token}' | base64 -d | sed 's/$/\n/g')
echo $TOKEN
```

Copia esa cadena larga. En el portal: **Kubernetes: Azure Arc** → tu clúster →
menú lateral **Recursos de Kubernetes** → te pedirá iniciar sesión → elige
**Token de cuenta de servicio** → pega el token.

Ahora puedes ver los *deployments*, *pods* y *services* del clúster desde el
portal.

📸 **Evidencia:** la vista de recursos de Kubernetes en el portal, mostrando
los pods de la tienda.

> ⚠️ **Ese token es una credencial de administrador del clúster.** No lo
> pegues en el informe ni lo muestres en la grabación. Si aparece en pantalla,
> se ve completo y cualquiera que pause el video lo tiene.
>
> `cluster-admin` es además el rol más amplio que existe en Kubernetes. Para
> el ejercicio sirve; en un caso real se daría un rol de solo lectura. Vale la
> pena decirlo: es la misma clase de compromiso que documentaste con el
> usuario administrador del registro de contenedores.

---

## Paso 7 — Eliminar el clúster

**Este paso no es opcional.** Mientras el clúster exista, consume crédito.

Lo más seguro es borrar el grupo de recursos completo, porque AKS crea además
un segundo grupo automático (`MC_rg-aks-devops_aks-devops_eastus2`) con los
nodos, el balanceador y las direcciones IP.

En Cloud Shell:

```bash
az group delete --name rg-aks-devops --yes --no-wait
```

El grupo `MC_...` se elimina solo al eliminarse el clúster. Compruébalo unos
minutos después:

```bash
az group list --query "[?starts_with(name,'MC_') || name=='rg-aks-devops'].name" -o tsv
```

Si no devuelve nada, está todo borrado.

También puedes hacerlo desde el portal: **Grupos de recursos** →
`rg-aks-devops` → **Eliminar grupo de recursos**.

> Antes de borrar, **asegúrate de tener todas las capturas**. El clúster se
> puede volver a crear, pero son otros 10 minutos y otro rato de cobro.

---

## Resumen de evidencias

| # | Qué capturar | En qué paso |
|---|---|---|
| 1 | Clúster creado, *Succeeded (Running)*, dos grupos de nodos | 2 |
| 2 | `kubectl get nodes` con los dos nodos `Ready` | 3 |
| 3 | `kubectl apply` con los objetos creados | 4 |
| 4 | `kubectl get pods` con los cuatro `Running` | 4 |
| 5 | `kubectl get service store-front` con la IP externa | 5 |
| 6 | La tienda abierta en el navegador | 5 |
| 7 | El recurso de Azure Arc en el grupo de recursos | 6.2 |
| 8 | La vista de recursos de Kubernetes en el portal | 6.3 |
| 9 | El grupo de recursos eliminado | 7 |

Van al **anexo B** del informe, después de las siete que ya tienes.

---

## Para qué sirve esto en tu informe

No es un ejercicio suelto: es lo que cierra el **criterio 3** de la pauta.

Tu informe clasifica siete herramientas de orquestación y elige Docker Compose
por proporcionalidad, no por potencia. Hasta ahora esa era una afirmación
sostenida en argumentos. Después de esto, es una **elección informada**: has
operado las dos, y puedes decir con precisión qué te da cada una y qué cuesta.

Eso conviene que quede escrito en el informe y dicho en la presentación, con
esta estructura:

1. *«Clasificamos las siete herramientas del ecosistema.»*
2. *«Elegimos Docker Compose porque hay una sola máquina virtual y cuatro
   contenedores.»*
3. *«Para verificar que la elección era informada y no una limitación,
   desplegamos también en AKS.»*
4. *«Confirmamos lo que anticipaba el análisis: AKS resuelve solo el
   balanceador y la IP pública, y cuesta 140 dólares al mes en nodos. Para
   este caso no compensa; para veinte servicios y tres equipos, sí.»*

Esa secuencia es criterio técnico demostrado, que es exactamente lo que la
pauta puntúa.

---

## Por qué no fue posible en esta suscripción

Se deja registrado porque el diagnóstico tiene valor propio, y porque distingue
tres controles que se confunden con facilidad.

### Elegibilidad regional

El desplegable de regiones del formulario de AKS marca **todas las regiones
como «No apto» salvo West US 3**. East US 2, la región que indica la actividad,
no es elegible para este servicio en esta suscripción.

### Disponibilidad del tamaño

Filtrando el selector por **vCPU : 2** en West US 3 quedan siete tamaños
disponibles:

| Tamaño | RAM | Familia |
|---|---|---|
| `D2ds_v7` | 8 GB | Ddsv7 |
| `D2lds_v7` | 4 GB | Dldsv7 |
| `D2ls_v7` | 4 GB | Dlsv7 |
| `D2s_v7` | 8 GB | Dsv7 |
| `E2ds_v7` | 16 GB | Edsv7 |
| `E2s_v7` | 16 GB | Esv7 |
| `M8-2ms` | 218 GB | MS |

En East US 2 no hay ninguno: se comprobaron `D2s_v3`, `D2as_v4`, `DS2_v2`,
`D2_v2` y toda la familia B, y todos devuelven `NotAvailableForSubscription`
—incluido el que el propio formulario propone por omisión.

### Cuota

**Las siete familias de la tabla anterior tienen cuota cero.** El formulario lo
confirma con el aviso «núcleos restantes: 0», que persiste incluso fijando el
máximo de nodos en 1.

El caso inverso también se da: `Standard_DS2_v2`, el tamaño que usa el material
del curso, **sí tiene cuota** —cuatro núcleos en West US 3— pero el tamaño está
deshabilitado. Cuota y disponibilidad son controles independientes.

### Solicitud de aumento

Se solicitó aumento a 8 vCPU para las once familias ajustables de la región.
**Las once solicitudes fueron rechazadas** por el mecanismo de autoservicio:
`Correcto: 0 · Incorrecto: 11`. La suscripción remite a un caso de soporte
técnico, que Azure for Students no tramita.

### Conclusión

No existe ninguna combinación de región, tamaño y cuota que permita crear un
clúster de AKS en esta suscripción. No es un problema de configuración.

La clasificación de herramientas de orquestación del informe se sostiene sobre
el análisis comparativo y sobre la experiencia práctica con Docker Compose,
que sí está desplegado y verificado.
