# Clúster AKS y Azure Arc, paso a paso

Guía para crear un clúster de Azure Kubernetes Service, desplegar una
aplicación en él, registrarlo en Azure Arc y eliminarlo al terminar.

Sigue la actividad de la Semana 6 de la asignatura. Es un ejercicio
**independiente** de la solución de ventas: usa su propio grupo de recursos y
su propia región, y no toca nada de `rg-devops-001a`.

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

La guía de la asignatura insiste en **East US 2** para todo el
aprovisionamiento. Tu infraestructura de ventas está en West US 3, y eso no
importa: son recursos independientes y no se comunican entre sí.

Para el clúster usa **East US 2**.

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
- **Región:** `East US 2`

Hay que mirar **dos** filas, y las dos tienen que alcanzar:

1. **vCPU regionales totales** — el techo de toda la región
2. La familia del tamaño que vayas a usar

Con dos nodos de dos núcleos necesitas **4 o más** en ambas.

### Lo que se midió en esta suscripción

Hay que mirar **dos** cuotas, y la que manda no es la de la familia:

```
vCPU regionales totales        East US 2   0 de 6    ← el techo real
Familia DSv3 estándar vCPUs    East US 2   0 de 4
Familia DASv4 estándar vCPUs   East US 2   0 de 4
Familia Bsv2 estándar vCPUs    East US 2   0 de 10
```

El límite regional de **6 vCPU** manda sobre todos los demás: da igual que una
familia tenga 10 asignados, la suma de todo lo que se ejecute en la región no
puede pasar de 6.

Dos nodos de 2 vCPU son 4. Entra, con dos de margen.

### El tamaño que pide la actividad no está disponible

`D2s_v3` aparece en el selector bajo el encabezado **«Tamaño no disponible»**:
la suscripción tiene cuota de esa familia, pero el tamaño está restringido en
East US 2. Son dos condiciones independientes y hay que cumplir las dos.

**Se usa `D2as_v4` en su lugar**, que es el equivalente directo:

| | `D2s_v3` | `D2as_v4` |
|---|---|---|
| vCPU | 2 | 2 |
| RAM | 8 GB | 8 GB |
| Serie | D, uso general | D, uso general |
| Procesador | Intel | AMD |

Mismo tamaño y mismo propósito; cambia el fabricante del procesador, y eso no
afecta a nada porque ambos son x86 y ejecutan las mismas imágenes.

Si `D2as_v4` tampoco estuviera disponible, el siguiente candidato es
`B2s_v2` (Intel, 2 vCPU, 8 GB, cuota 10).

**Evitar los tamaños con `p`** —`D2ps_v6`, `B2pts_v2`— porque son ARM. Las
imágenes de la tienda de Microsoft y las de `acrventas` están compiladas para
x86 y fallarían con `exec format error`.

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
| Región | **East US 2** |

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
| Región | **East US 2** |
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
| Tamaño del nodo | `D2as_v4` (pulsa *Cambiar tamaño* para elegirlo) |
| Recuento mínimo de nodos | `1` |
| Recuento máximo de nodos | `2` |

**Actualizar**.

**2. Agregar un segundo grupo.** Botón **+ Agregar grupo de nodos**:

| Campo | Valor |
|---|---|
| Nombre del grupo de nodos | `nplinux` |
| Modo | `Usuario` |
| Sistema operativo | `Ubuntu Linux` |
| Tamaño del nodo | `D2as_v4` |
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
