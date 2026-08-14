# Prueba Técnica — SQL Server, .NET y Power BI

Solución para consolidar y visualizar información de ventas mensuales.

| Entregable | Ubicación |
|---|---|
| Scripts SQL | [`sql/`](sql/) |
| Proyecto .NET (MVC + Web API) | [`src/PruebaTecnica.Web/`](src/PruebaTecnica.Web/) |
| Reporte Power BI | [`powerbi/`](powerbi/) |
| Script de puesta en marcha | [`scripts/setup.ps1`](scripts/setup.ps1) |

---

## 1. Cómo ejecutar la solución

### Requisitos

- **Docker Desktop** — para SQL Server, así no hace falta instalarlo en Windows.
- **.NET SDK 9** — `winget install Microsoft.DotNet.SDK.9`
- **Power BI Desktop** (sólo para el reporte) — `winget install Microsoft.PowerBI`

### Opción A — automática (recomendada)

Desde la raíz del proyecto, en PowerShell:

```bash
.\scripts\setup.ps1
```

El script levanta SQL Server 2022 en un contenedor, restaura `Tecnica_FULL.bak`,
ejecuta los tres scripts SQL y verifica los conteos resultantes. Es idempotente:
se puede correr las veces que sea.

Si el `.bak` no está en la raíz ni en la carpeta de descargas, indicale la ruta:

```bash
.\scripts\setup.ps1 -RutaBackup "C:\ruta\a\Tecnica_FULL.bak"
```

Después, levantar la aplicación:

```bash
dotnet run --project src\PruebaTecnica.Web --urls http://localhost:5080
```

| Recurso | URL |
|---|---|
| Aplicación web | <http://localhost:5080> |
| Swagger (documentación de la API) | <http://localhost:5080/swagger> |

### Opción A-bis — todo en Docker, sin instalar .NET

La aplicación también corre en contenedor, así que basta con Docker:

```bash
docker compose up -d --build
```

Levanta SQL Server y la aplicación en la misma red, y espera a que la base
responda antes de arrancar la web (`healthcheck` + `depends_on`). Luego hay que
restaurar el backup y ejecutar los scripts, igual que en la opción A.

Esta vía sirve además cuando **Windows Smart App Control** bloquea los binarios
compilados localmente — ver la sección de problemas encontrados.

### Opción B — manual

```bash
docker run -d --name mssql-tecnica -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Tecnica#2026!Sql" -e "MSSQL_PID=Developer" -p 1433:1433 mcr.microsoft.com/mssql/server:2022-latest
```

```bash
docker cp Tecnica_FULL.bak mssql-tecnica:/var/opt/mssql/backup/Tecnica_FULL.bak
```

El backup viene de un SQL Server **de Windows**, así que sus rutas internas
(`C:\Program Files\...`) hay que redirigirlas a las de Linux con `MOVE`:

```bash
docker exec mssql-tecnica /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Tecnica#2026!Sql' -C -No -Q "RESTORE DATABASE [Tecnica] FROM DISK='/var/opt/mssql/backup/Tecnica_FULL.bak' WITH MOVE 'Tecnica' TO '/var/opt/mssql/data/Tecnica.mdf', MOVE 'Tecnica_log' TO '/var/opt/mssql/data/Tecnica_log.ldf', REPLACE, RECOVERY;"
```

Luego ejecutar, **en este orden**, los scripts de `sql/`:

1. `01_esquema_y_matriz.sql` — maestro de productos + matriz mensual (puntos 1.1 y 1.2)
2. `02_analisis_datos.sql` — análisis de calidad de datos (punto 1.3)
3. `03_vista_powerbi.sql` — vista de apoyo para el reporte

### Si SQL Server ya está instalado en Windows

Restaurar el `.bak` desde SSMS de la forma habitual (sin `MOVE`, porque las rutas
ya son de Windows) y ajustar la cadena de conexión `Tecnica` en
`src/PruebaTecnica.Web/appsettings.json`.

### Power BI

El reporte se arma siguiendo [`powerbi/GUIA-POWER-BI.md`](powerbi/GUIA-POWER-BI.md),
una guía paso a paso. Las medidas DAX listas para copiar están en
[`powerbi/medidas-dax.txt`](powerbi/medidas-dax.txt).

---

## 2. Qué se entregó, punto por punto

### 1.1 Maestro de productos

`dbo.Productos`, poblada a partir de los valores distintos de `Ventas.Producto`.

| Columna | Por qué |
|---|---|
| `IdProducto` | PK identity. Requerida por el enunciado. |
| `NombreProducto` | Requerida. Con índice **único**: sin eso no es un maestro. |
| `Activo` | Borrado lógico: permite descontinuar un producto sin destruir su historial de ventas. |
| `FechaCreacion` | Trazabilidad de cuándo entró al maestro. |

Además se agregó a `dbo.Ventas` una columna `IdProducto` con FK al maestro,
**conservando** la columna original `Producto` (texto). La justificación y su
costo están en la sección 4.

### 1.2 Matriz mensual de ventas

| Objeto | Qué es |
|---|---|
| `dbo.vw_MatrizVentasMensual` | Vista. Matriz producto × período, **31.820 filas** = 860 productos × 37 períodos. |
| `dbo.VentasMensual` | Misma información materializada en tabla, para consumo intensivo. |
| `dbo.usp_RefrescarVentasMensual` | Recalcula la tabla de forma atómica (transacción + `XACT_ABORT`). |
| `dbo.vw_ResumenMensualPorCompania` | Consolidado abierto también por compañía; lo consume la API. |

La grilla completa se obtiene con `Productos CROSS JOIN períodos LEFT JOIN agregado`,
y los huecos se rellenan con `ISNULL(..., 0)`. Así, si un producto no vendió en un
período, la fila **existe** con valores en 0 en lugar de faltar.

El período se calcula con `DATEFROMPARTS(YEAR(Fecha), MONTH(Fecha), 1)`.

### 1.3 Análisis de datos

`02_analisis_datos.sql` abre con un tablero de una fila por chequeo. Resultado
sobre los datos entregados:

| Chequeo | Filas | Severidad |
|---|---:|---|
| Ventas duplicadas exactas | 1 | Alta |
| Mismo cliente/producto/día con montos distintos | 439 | Informativa |
| Cantidades negativas | 267 | Alta |
| Precio igual a 0 | 300 | Alta |
| Fecha nula | 0 | Alta |
| Fecha fuera de rango razonable | 2.719 | Media |
| Celdas producto × período sin ventas | 30.116 | Informativa |
| `Producto` (texto) desincronizado de `IdProducto` (FK) | 0 | Alta |
| `Cantidad` o `Precio` nulos | 0 | Alta |
| `Compania` o `Producto` vacíos | 0 | Alta |

El script **sólo lee**; no corrige nada. Las sentencias de corrección quedan
escritas y comentadas al final del archivo. El razonamiento está en la sección 4.

### 2. Aplicación .NET

Un único proyecto **ASP.NET Core 9 MVC** que contiene las vistas y la API. Un
solo proyecto significa un solo comando para levantar todo.

| Pantalla | Ruta |
|---|---|
| Portada con cifras de control | `/` |
| CRUD de ventas (con filtros y paginación) | `/Ventas` |
| CRUD de productos | `/Productos` |
| Resumen mensual producto × período | `/Resumen` |
| Resumen abierto por compañía | `/Resumen/PorCompania` |

La portada y el resumen mensual incluyen **gráficos SVG generados en el
servidor**, sin librería de terceros. Ver la decisión correspondiente más abajo.

Arquitectura en tres capas:

```
Controllers  ->  Services  ->  AppDbContext (EF Core)  ->  SQL Server
   HTTP        reglas de negocio      acceso a datos          vistas SQL
```

Los controladores no tocan el `DbContext`: sólo traducen el resultado de los
servicios a HTTP o a una vista. Los servicios no saben qué es HTTP.

Requisitos técnicos exigidos:

- **`async/await`** — todo el acceso a datos es asíncrono, con `CancellationToken`
  propagado de punta a punta, así una petición abandonada por el cliente no sigue
  ocupando el servidor.
- **Validaciones** — `VentaInput`/`Producto` con Data Annotations, más
  `IValidatableObject` para las reglas que dependen del contexto. El modelo de
  entrada está separado de la entidad; ver sección 4.
- **Manejo de errores** — middleware `ManejadorDeErrores`, que responde JSON en
  `/api/*` y página de error en el resto, traduciendo cada excepción al código
  HTTP que le corresponde.
- **Código ordenado** — servicios con interfaz, inyección de dependencias,
  resultados explícitos en lugar de excepciones para el flujo esperable.

### 2.1 API para consulta externa

Documentada con Swagger en `/swagger`.

| Método | Endpoint | Respuesta |
|---|---|---|
| GET | `/api/ventas` | 200 |
| GET | `/api/ventas/{id}` | 200 / 404 |
| GET | `/api/ventas/resumen-mensual` | 200 / 400 |
| GET | `/api/ventas/matriz-mensual` | 200 |
| POST | `/api/ventas` | 201 / 400 / 409 |
| PUT | `/api/ventas/{id}` | 204 / 400 / 404 |
| DELETE | `/api/ventas/{id}` | 204 / 404 |

`resumen-mensual` acepta los filtros opcionales `compania`, `producto` y
`periodo`, combinables entre sí:

```
GET /api/ventas/resumen-mensual?compania=Northwind&periodo=2025-04-01
```

Respuesta, con exactamente los nombres de campo del enunciado:

```json
[
  {
    "compania": "Northwind",
    "producto": "Apple Watch",
    "periodo": "2025-04-01",
    "cantidadVentas": 32,
    "totalVentas": 7538704.00,
    "numeroTransacciones": 2
  }
]
```

**Paginación en cabeceras, no en el cuerpo.** Los endpoints devuelven un array
JSON plano, igual que el ejemplo del enunciado, y la metadata viaja en
`X-Total-Registros`, `X-Pagina`, `X-Total-Paginas` y `X-Tamano-Pagina`. De este
modo quien sólo quiere los datos los lee directo, sin desenvolver un objeto, y
quien necesita paginar tiene la información igual.

### 3. Power BI

- [`powerbi/GUIA-POWER-BI.md`](powerbi/GUIA-POWER-BI.md) — guía paso a paso.
- [`powerbi/medidas-dax.txt`](powerbi/medidas-dax.txt) — 9 medidas DAX listas.
- `dbo.vw_VentasPowerBI` — vista de apoyo con período, año, mes y nombre de mes
  en español ya calculados.

La medida que pide el enunciado, verbatim:

```dax
Total Ventas =
SUMX(
    Ventas,
    Ventas[Cantidad] * Ventas[Precio]
)
```

---

## 3. Supuestos realizados

**`CantidadVentas` significa unidades vendidas, no número de ventas.**
El nombre es ambiguo. Se resolvió por el propio ejemplo del enunciado:
`cantidadVentas: 10` con `totalVentas: 250000` implica un precio unitario de
25.000, lo que sólo cierra si `CantidadVentas = SUM(Cantidad)`. Para no forzar la
interpretación, la matriz entrega **las dos**: `CantidadVentas` (unidades) y
`NumeroTransacciones` (`COUNT(*)`).

**"Todos los períodos existentes" son los 37 que aparecen en los datos, no un
calendario continuo.** Esto importa porque los datos tienen un hueco real: **no
hay ninguna venta entre 2024-08 y 2024-12**. Leyendo el enunciado literalmente,
esos 5 meses no se inventan. La variante con calendario continuo está escrita y
comentada dentro de `vw_MatrizVentasMensual`, para cambiarla en un minuto si el
negocio la prefiere.

**Las filas sucias entran en la matriz.** Las 267 cantidades negativas y los 300
precios en 0 se incluyen en los totales. La matriz debe reflejar lo que dice la
base, no una versión maquillada. Su identificación y cuantificación es el punto
1.3, que es donde corresponde decidir qué hacer con ellas.

**Las ventas con fecha futura son datos legítimos, no errores.** Hay 2.719 filas
fechadas después de hoy, distribuidas de forma pareja (unas 600 por mes hasta
2026-12). Ese patrón es demasiado regular para ser un error de carga: son ventas
proyectadas o programadas. Consecuencia práctica: la app **no** rechaza fechas
futuras, porque hacerlo dejaría 2.719 filas imposibles de editar. Sí rechaza lo
absurdo (año anterior a 2000, o más de 5 años hacia adelante).

**"Fecha inválida" sólo puede significar inválida para el negocio.** La columna
es `datetime`, así que SQL Server ya rechaza de plano un valor como `2024-02-31`:
ese `INSERT` falla. Por eso el chequeo busca nulos, fechas centinela anteriores
al 2000, fechas futuras y componentes de hora inesperados.

**El importe es monetario, pero el dataset no declara la moneda.**
No existe ninguna columna de moneda: `Precio` es un `decimal(18,2)` sin más
contexto. Por las magnitudes (un notebook a 850.000, un monitor a 500.000) es
consistente con **pesos chilenos**, y así se formateó en Power BI, pero es una
inferencia, no un dato. En un sistema real la moneda debería estar explícita en
el modelo — o, si hubiera más de una, con su tipo de cambio, porque sumar
importes de monedas distintas produce un total sin significado.

**Los montos se muestran sin decimales, porque no los tienen.**
Los **15.088** precios del set son números enteros: ninguno tiene centavos, y el
total general tampoco. Es coherente con el peso chileno, que en la práctica no
se fracciona, y con el propio enunciado, que escribe su ejemplo como
`"totalVentas": 250000`.

Aun así el formato elegido es `$#,##0.##`, no "cero decimales fijos". La
diferencia importa: la columna es `decimal(18,2)`, así que los centavos **son
representables** aunque hoy no se usen. Con un formato de cero decimales, un
precio de 12.345,67 se mostraría como `$12.346` y esa diferencia quedaría
invisible. Con `##`, los decimales aparecen sólo cuando existen:

| Valor guardado | Se muestra |
|---|---|
| 200983 | `$200.983` |
| 12345,67 | `$12.345,67` |

Verificado creando una venta con centavos por la API y comprobando la pantalla.
Un formato de presentación no debe ocultar lo que la base sí guarda.

La API, en cambio, devuelve el decimal tal cual (`7538704.00`). Es el mismo
número que `7538704` para cualquier parser de JSON, y conserva la precisión del
tipo de origen: dar formato es responsabilidad de quien consume, no de la API.

**Los precios son aleatorios: no representan un negocio real.**
Vale la pena decirlo porque condiciona cómo se lee el reporte. El precio promedio
de cada producto ronda los 255.000 con un rango de 5.000 a 505.000,
**independientemente de qué producto sea**:

| Producto | Precio promedio |
|---|---:|
| Notebook Lenovo | 260.657 |
| Apple Watch | 259.738 |
| Mouse Logitech | 258.461 |
| Cable HDMI | 256.772 |
| MacBook Pro | 249.170 |

Un cable HDMI cuesta lo mismo que un MacBook Pro, y en el bloque de 2023–2024 una
manzana Fuji promedia 49.904. Es la firma de una generación uniforme con `RAND()`.

Consecuencia práctica: **los totales son correctos, pero no admiten lectura de
negocio**. Un ranking de "productos más rentables" ordenaría ruido. Por eso el
reporte se limita a mostrar magnitudes y su distribución, sin conclusiones
comerciales que los datos no sostienen.

**El maestro se puebla con los 860 nombres distintos tal como están.** No hubo
que normalizar: se verificó que no existen variantes por espacios sobrantes ni
por diferencias de mayúsculas (0 casos de ambos).

**Se ignoró la vista `dbo.Prueba` que venía en el backup.** Referencia una base
`ASTURIASCORP` que no existe; es residuo del entorno original. Ver sección 5.

---

## 4. Decisiones técnicas

### `Ventas` guarda el producto dos veces: texto + FK

Se agregó `Ventas.IdProducto` con FK a `Productos`, **sin eliminar** la columna
`Producto` (texto).

*Por qué las dos:* la FK da integridad referencial real — ya no se puede
registrar una venta de un producto inexistente, y renombrar un producto no rompe
el histórico. El texto se conserva para no alterar la estructura que el enunciado
da por sentada ni romper consultas existentes.

*El costo:* hay que mantenerlas sincronizadas. Se asumió explícitamente y se
cubrió por los dos lados:

- La app **nunca** escribe el texto de lo que teclea el usuario: lo copia del
  maestro. Así no se pueden desincronizar al crear o editar una venta.
- Renombrar un producto propaga el cambio a todas sus ventas, en una transacción.
- El chequeo 6 de `02_analisis_datos.sql` detecta cualquier desincronización.
  Debe devolver siempre 0 filas.

Alternativa descartada: eliminar `Ventas.Producto` y dejar sólo la FK. Es más
limpio en teoría, pero cambia la estructura de la tabla que el enunciado usa como
punto de partida.

### La agregación vive en SQL, no en C# ni en DAX

`vw_MatrizVentasMensual` y `vw_ResumenMensualPorCompania` son la única definición
de "total vendido". La app, la API y Power BI las consultan; ninguno recalcula.
Si el cálculo estuviera duplicado en tres lenguajes, tarde o temprano los tres
mostrarían números distintos y nadie sabría cuál creer.

### La entidad es permisiva; el modelo de entrada es estricto

`Venta` declara todas sus columnas de negocio como nullable, igual que la base.
Si fueran obligatorias, EF Core lanzaría una excepción al leer las filas sucias y
la app no podría ni listarlas — justo las filas que interesa poder ver y corregir.

Las validaciones viven en `VentaInput`, que es lo que reciben los formularios y la
API. Separar *"cómo está guardado el dato"* de *"qué acepto como dato nuevo"*
permite mostrar el historial sucio y a la vez impedir que entre más basura.

### Resultados explícitos en lugar de excepciones

Los servicios devuelven `Resultado<T>` con estado `Exito | NoEncontrado |
Invalido | Conflicto`. Situaciones como "no existe" o "no se puede borrar porque
tiene ventas" son parte del flujo normal, no fallas. Las excepciones quedan para
lo verdaderamente excepcional, que es lo que atrapa el middleware.

Cada estado tiene una única traducción a HTTP, concentrada en un método, para que
ninguna acción invente su propio código.

### No se borra un producto que tiene ventas

Se rechaza con 409 y se sugiere desactivarlo. Un borrado en cascada destruiría
historial real. La vista de confirmación avisa **antes** de que el usuario haga
clic, y el rechazo también se aplica del lado del servidor: se verificó forzando
la petición sin pasar por la interfaz.

### La matriz oculta las celdas en 0 por defecto en la pantalla

Son 30.116 de 31.820 filas. Mostrarlas todas por defecto vuelve la pantalla
ilegible. El requisito de que **existan** se cumple en la vista SQL; mostrarlas o
no es una decisión de presentación, y hay una casilla para verlas.

### El consolidado por compañía no rellena con ceros

El enunciado exige el relleno para la matriz producto × período (1.2), no al
abrir por compañía. Con 363 compañías × 860 productos × 37 períodos la grilla
completa serían **11.549.460 filas**, casi todas en cero: inútil de leer y caro
de transferir por HTTP.

### Los gráficos se dibujan en el servidor, sin librería de terceros

La app incluye tres gráficos: evolución mensual y ranking de productos en la
portada, y evolución de la serie filtrada en el resumen mensual. Son **SVG
generados en Razor**, no Chart.js ni similares.

*Por qué:* toda la solución es autocontenida — tipografía del sistema, iconos
SVG en línea, Bootstrap servido localmente. Agregar 200 KB de JavaScript para
tres gráficos rompería esa coherencia. Además el gráfico llega dibujado dentro
del HTML: no hay estado de carga, ni parpadeo, ni un lienzo vacío si el
JavaScript falla, y al imprimir la página el gráfico sale porque ya es parte del
documento.

*El costo asumido:* no hay interactividad más allá del tooltip nativo del
navegador (elementos `<title>` dentro de cada barra). Para explorar los datos
está Power BI, que es el entregable pensado para eso. Se mantuvieron
deliberadamente pocos gráficos: llenar la app de visualizaciones sería duplicar
el trabajo que el enunciado asigna a Power BI.

Dos detalles que hubo que resolver:

- **Razor reserva la etiqueta `<text>`** como construcción propia para emitir
  texto literal, y SVG también tiene un elemento `<text>`. Escribirlo directo
  falla al compilar con `RZ1023`. Los rótulos se arman con una función local y
  se emiten con `Html.Raw`, codificando el contenido.
- **Las coordenadas SVG deben usar cultura invariante.** La app corre en `es-CL`,
  donde el separador decimal es la coma, y un atributo `x="12,5"` es inválido en
  SVG: el navegador descarta el elemento y el gráfico sale roto. Es la misma
  clase de error que el de los precios en los formularios, en sentido contrario.
  Se centralizó en `Svg.N()`, y se verificó que el HTML servido no contenga
  ninguna coordenada con coma.

Las escalas arrancan siempre en cero. Recortar el eje exagera visualmente las
diferencias y es la forma más común de mentir con un gráfico sin escribir una
sola cifra falsa.

### Seguridad de la API

Hoy es pública, como permite el enunciado. En un escenario real:

- **JWT con OAuth 2.0 / OpenID Connect** contra un proveedor de identidad
  (Entra ID, Auth0, Keycloak), validando emisor, audiencia y expiración. Se
  configura con `AddAuthentication().AddJwtBearer()` y `[Authorize]` en los
  controladores. Para *machine-to-machine*, el flujo *client credentials*.
- **Autorización por rol**: los GET de consulta con un rol de lectura; POST, PUT
  y DELETE restringidos a un rol de escritura.
- **HTTPS obligatorio** con HSTS (ya está `UseHsts()` fuera de desarrollo).
- **Rate limiting** con `AddRateLimiter`, para que un cliente no sature la base.
- **CORS** con lista explícita de orígenes, nunca `AllowAnyOrigin`.
- **Secretos fuera del repositorio**: la contraseña de `appsettings.json` está en
  claro porque es un entorno de prueba desechable. En producción irían en Azure
  Key Vault o variables de entorno, y la app usaría *managed identity* en lugar
  de usuario y contraseña.
- **Sin `sa`**: un usuario de aplicación con permisos mínimos — `SELECT` en las
  vistas, `SELECT/INSERT/UPDATE/DELETE` sólo en las tablas que necesita.

---

## 5. Problemas encontrados

**El backup viene de SQL Server para Windows y se restaura en Linux.**
Sus rutas internas apuntan a `C:\Program Files\Microsoft SQL Server\MSSQL16...`,
que no existen en el contenedor. Sin `MOVE`, el `RESTORE` falla. Se resolvió
leyendo primero los nombres lógicos con `RESTORE FILELISTONLY` y redirigiéndolos.

**`EnableRetryOnFailure` es incompatible con transacciones abiertas a mano.**
Al renombrar un producto, la operación lanzaba
`InvalidOperationException: The configured execution strategy
'SqlServerRetryingExecutionStrategy' does not support user-initiated
transactions`. El motivo es sensato: si el reintento cayera a mitad de la
transacción, EF Core no sabría desde dónde reanudar. Se corrigió envolviendo el
bloque completo en `Database.CreateExecutionStrategy().ExecuteAsync(...)`, que
reintenta la unidad entera. Detectado ejecutando la operación de verdad, no
leyendo el código: el rollback funcionó y la base quedó consistente.

**Una subconsulta dentro de un agregado no compila.**
El chequeo de productos discontinuados usaba
`SUM(CASE WHEN Periodo IN (SELECT ...))`, que SQL Server rechaza con
*"Cannot perform an aggregate function on an expression containing an aggregate
or a subquery"*. Como todo el lote se compila junto, el error tumbaba también los
chequeos 5a y 5b. Se resolvió marcando la pertenencia con un `LEFT JOIN` previo.

**`DATENAME(MONTH, ...)` depende del idioma de la sesión.**
El contenedor arranca en inglés, así que la vista de Power BI devolvía
`December`. Se reemplazó por un `CASE` explícito, para que el resultado no
dependa de la configuración regional de quien ejecute la consulta.

**Hueco de 5 meses en los datos.**
No hay ninguna venta entre 2024-08 y 2024-12. Afecta directamente la
interpretación de "todos los períodos existentes" (ver Supuestos).

**Los precios enviados desde los formularios se guardaban multiplicados por 100.**
El más grave de todos, porque era silencioso. Al crear una venta de $12.345,67
la base guardaba **$1.234.567**, sin disparar ninguna validación: 1234567 es un
decimal perfectamente válido.

La causa es un choque entre dos estándares. El HTML obliga a que un
`<input type="number">` envíe siempre el valor con **punto** decimal, sea cual
sea el idioma. Pero ASP.NET Core interpreta los valores de formulario con la
**cultura actual**, que en este servidor es `es-CL`, donde el punto es separador
de **miles**. Resultado: `"12345.67"` se leía como doce millones.

Se resolvió con un *model binder* propio (`EnlaceDecimalInvariante`) registrado
para todos los tipos decimales, que intenta primero cultura invariante — el
formato real del navegador — y sólo si falla reintenta con la cultura local,
para no romper un valor tecleado a mano como `"12345,67"`.

El detalle que costó una segunda vuelta: el primer intento debe hacerse **sin**
`AllowThousands`. Con esa opción activa, `"12345,67"` sí parseaba en cultura
invariante — tomando la coma como separador de miles — y devolvía 1234567. Es
decir, el mismo error de factor 100, pero al revés. El primer arreglo pasó la
prueba del punto y falló la de la coma; sólo se detectó porque se verificaron
ambos casos contra la base.

Verificado con los cuatro formatos posibles:

| Entrada | Origen | Guardado | |
|---|---|---:|---|
| `12345.67` | formulario (navegador) | 12.345,67 | ✓ |
| `12345,67` | formulario (tecleado) | 12.345,67 | ✓ |
| `1.234.567` | formulario (con miles) | 1.234.567 | ✓ |
| `12345.67` | API JSON | 12.345,67 | ✓ |

La API nunca estuvo afectada: `System.Text.Json` deserializa números en formato
invariante por definición. El problema era exclusivo de los formularios, que es
justo donde no se había probado un decimal con parte fraccionaria.

Como consecuencia, la cultura de la aplicación se fija explícitamente a `es-CL`
en `Program.cs` en lugar de heredarse del sistema operativo: así los montos y
las fechas se ven igual en cualquier máquina.

**Windows Smart App Control bloqueó el binario compilado.**
A mitad del desarrollo, la aplicación dejó de arrancar:

```
System.IO.FileLoadException: Could not load file or assembly
'PruebaTecnica.Web.dll'. Una directiva de Control de aplicaciones
bloqueó este archivo. (0x800711C7)
```

Smart App Control estaba activo (`VerifiedAndReputablePolicyState = 1` en
`HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy`) y bloquea ejecutables sin
firma digital de reputación conocida — que es exactamente lo que produce
`dotnet build`. Ni recompilar en limpio ni invocar el DLL desde `dotnet.exe`
(firmado por Microsoft) lo evitaron: la política se aplica al ensamblado.

Se resolvió **empaquetando la aplicación en un contenedor Linux**
(`src/PruebaTecnica.Web/Dockerfile` + `docker-compose.yml`). Ahí App Control no
interviene, porque no es código ejecutándose en Windows.

Desactivar Smart App Control era la otra salida, pero se descartó: es una
decisión de seguridad del usuario y, sobre todo, **irreversible** — Windows no
permite reactivarlo sin reinstalar el sistema. Contenerizar resuelve el problema
sin pedir esa concesión, y de paso deja la solución reproducible en cualquier
máquina con Docker, sin instalar el SDK de .NET.

Detalle que hubo que atender: las imágenes oficiales de .NET vienen en modo
*globalización invariante*, donde toda cultura se comporta como la invariante.
Sin instalar el locale `es_CL` en la imagen, los montos salían con formato
inglés (`38,594,578,526`) en lugar del chileno (`38.594.578.526`).

**Windows PowerShell 5.1 no parsea archivos `.ps1` en UTF-8 sin BOM.**
`setup.ps1` fallaba con *"La palabra clave 'from' no se admite en esta versión
del idioma"*: al no reconocer la codificación, el intérprete no abría las
here-strings y leía el SQL como si fuera código PowerShell. Se resolvió guardando
el archivo en **UTF-8 con BOM y saltos de línea CRLF**. La misma conversión se
aplicó a los `.sql`, para que los acentos de los comentarios no se rompan si se
abren en SSMS.

**Los datos parecen dos conjuntos distintos pegados.**
Un bloque 2023-07 a 2024-07 con productos de alimentación (~80 filas/mes) y otro
2025-01 a 2026-12 con electrónica (~600 filas/mes). No es un problema a resolver,
pero explica por qué muchos productos tienen ventas en un solo período y por qué
la matriz está tan vacía (94,6% de celdas en 0).

**Vista huérfana `dbo.Prueba` dentro del backup.**
Referencia `[ASTURIASCORP].[DBO].[ACORP_FILERECORDSPROCESSED]`, una base que no
existe. Es residuo del entorno original y está rota. Se dejó tal cual: borrar
objetos del backup no fue parte de lo pedido.

---

## 6. Cómo validé los resultados

No alcanza con que compile: los números tienen que cuadrar. Todo lo de abajo se
ejecutó de verdad, no se revisó por lectura.

### Controles automáticos dentro del propio SQL

`01_esquema_y_matriz.sql` termina con cuatro controles que se imprimen al
ejecutarlo. Los cuatro dan **OK**:

| Control | Verifica | Resultado |
|---|---|---|
| 1 | La matriz tiene exactamente `productos × períodos` filas | 860 × 37 = 31.820 = 31.820 ✓ |
| 2 | El total de la matriz iguala el total crudo de `Ventas` | 38.594.578.526,00 en ambos ✓ |
| 3 | La regla del período con los ejemplos del enunciado | `2024-01-07 → 2024-01-01`, `2024-05-31 → 2024-05-01` ✓ |
| 4 | Los productos sin ventas aparecen en 0, no faltan | 30.116 celdas en 0 ✓ |

### El mismo total por tres caminos independientes

`03_vista_powerbi.sql` compara las tres rutas de cálculo y exige que coincidan:

```
DesdeVentas      DesdeLaMatriz    DesdeVistaPowerBI   Veredicto
38594578526.00   38594578526.00   38594578526.00      OK
```

Ese mismo número lo muestra la portada de la aplicación en `/`, y es el que tiene
que mostrar la tarjeta `Total Ventas` de Power BI.

### La API, probada endpoint por endpoint

Todos los endpoints se ejecutaron contra la base real:

| Prueba | Esperado | Obtenido |
|---|---|---|
| `GET /api/ventas` | 200, 15.088 en cabecera | ✓ |
| `GET /api/ventas/resumen-mensual` | 200, 7.156 filas | ✓ |
| `GET .../resumen-mensual?compania=Northwind&periodo=2025-04-01` | 200, 24 filas | ✓ |
| `GET /api/ventas/999999` | 404 | ✓ |
| `POST /api/ventas` válido | 201 + cabecera `Location` | ✓ |
| `POST` con cantidad −5 y precio 0 | 400 | ✓ |
| `POST` con producto inexistente | 400 | ✓ |
| `PUT /api/ventas/{id}` | 204 | ✓ |
| `DELETE /api/ventas/{id}` y luego `GET` | 204, después 404 | ✓ |
| `?desde=2026-01-01&hasta=2025-01-01` (rango invertido) | 400 | ✓ |
| `?periodo=no-es-fecha` | 400 | ✓ |

El formato JSON se comparó carácter por carácter con el ejemplo del enunciado.

**Normalización de período verificada:** `?periodo=2025-04-17` devuelve una
respuesta byte a byte idéntica a `?periodo=2025-04-01`.

### El invariante riesgoso, probado a propósito

La decisión de guardar el producto dos veces (texto + FK) crea un riesgo de
desincronización. Se probó el peor caso: renombrar un producto **con 515 ventas**
(`Tablet Samsung`, Id 803) desde el formulario.

Resultado: el maestro cambió, las **515** filas de `Ventas` se actualizaron, el
chequeo de consistencia siguió en **0 filas**, y las vistas de resumen reflejaron
el nombre nuevo. Después se revirtió el nombre.

En ese mismo ejercicio apareció el bug de `EnableRetryOnFailure` descrito en la
sección 5 — que no habría salido a la luz leyendo el código.

### El rechazo de borrado, forzado sin pasar por la interfaz

La pantalla no dibuja el botón de borrar cuando el producto tiene ventas, pero
eso no prueba nada del servidor. Se forzó el `POST` con un token válido tomado de
otro formulario: el servidor lo rechazó igual, con el mensaje explicando que hay
515 ventas asociadas y que corresponde desactivar.

### Todas las pantallas, respondiendo

Se recorrieron **24 rutas** — portada, listados con y sin filtros, formularios de
alta y edición, pantallas de confirmación de borrado, detalles, los dos
resúmenes, la UI de Swagger, el JSON de OpenAPI y los cuatro endpoints GET de la
API: **24 devolvieron 200, ninguna falló**. Además se verificó que los recursos
inexistentes devuelvan 404 y no 500 (`/Ventas/Details/999999`,
`/Productos/Edit/999999`, `/api/ventas/999999`).

Un 200 no prueba que la página se vea bien, así que se abrieron además en un
navegador. La portada muestra 15.088 ventas, 860 productos, 37 períodos y
38.594.578.526 de total: los mismos valores que devuelve SQL. Y el resumen
filtrado por `Notebook Lenovo` con la casilla de períodos sin ventas activada
devuelve las 37 filas, con los meses sin actividad en 0 — que es exactamente lo
que pide el punto 1.2, visible en pantalla.

### El script de puesta en marcha, ejecutado en limpio

`scripts/setup.ps1` se corrió de punta a punta contra una base ya existente:
cerró las conexiones activas, restauró el backup, ejecutó los tres scripts SQL y
verificó los conteos (15.088 / 860 / 31.820 / 7.156 / 15.088). Sin errores.

### Base devuelta a su estado original

Terminadas las pruebas se verificó que no quedara residuo: 15.088 ventas, 860
productos, total 38.594.578.526,00 — idénticos a los iniciales. `MaxId` de
productos de vuelta en 860, y el producto 803 con su nombre original.

### Compilación

`dotnet build`: **0 errores, 0 advertencias**.

---

## 7. Posibles mejoras

**Lo que falta y sé que falta:**

- **Pruebas automatizadas.** Es la carencia más grande. Todas las validaciones de
  la sección 6 se hicieron a mano; deberían ser un proyecto xUnit con
  `WebApplicationFactory` y una base en contenedor vía Testcontainers, corriendo
  en cada commit. Hoy nada impide que un cambio rompa un invariante en silencio.
- **Migraciones de EF Core.** El enfoque es database-first porque la base venía
  dada. Para un proyecto que evoluciona, el esquema debería estar versionado con
  migraciones o con una herramienta tipo DbUp.

**Rendimiento:**

- **Índice columnstore** en `Ventas` si el volumen creciera un orden de magnitud;
  las agregaciones mensuales son el caso de uso ideal.
- **Vista indexada** o refresco incremental de `VentasMensual` en lugar de
  `DELETE` + `INSERT` completo. Con 31.820 filas da igual; con millones, no.
- **Caché** de los catálogos que casi no cambian (períodos, compañías) con
  `IMemoryCache`.

**Funcionalidad:**

- **Exportar a Excel/CSV** desde las pantallas de resumen. Es lo primero que pide
  cualquier usuario de negocio.
- **Auditoría**: quién creó, modificó o eliminó cada venta y cuándo.
- **Importación masiva** desde Excel, con validación previa y reporte de rechazos,
  que es probablemente el origen real de las anomalías detectadas.
- **Un flujo explícito para las devoluciones**, que eliminaría la ambigüedad de la
  cantidad negativa: hoy no hay forma de distinguir una devolución legítima de un
  error de digitación.
- **Paginación por cursor** en la API en lugar de `OFFSET/FETCH`, que se degrada
  en páginas muy profundas.

**Datos:**

- **Restricciones `CHECK`** en `Cantidad > 0` y `Precio > 0` con `WITH NOCHECK`,
  para cortar el problema de raíz sin invalidar el histórico. Están escritas y
  comentadas en `02_analisis_datos.sql`.
- **Normalizar `Compania`** a su propio maestro, igual que se hizo con Productos.
  Con 363 compañías en texto libre, es cuestión de tiempo que aparezcan
  duplicados por tipeo.

---

## 8. Estructura del proyecto

```
PruebaTecnica/
├── README.md
├── PruebaTecnica.sln
├── scripts/
│   └── setup.ps1                    Levanta SQL Server, restaura y ejecuta todo
├── sql/
│   ├── 01_esquema_y_matriz.sql      Puntos 1.1 y 1.2 + controles de validación
│   ├── 02_analisis_datos.sql        Punto 1.3 (sólo lectura)
│   └── 03_vista_powerbi.sql         Vista de apoyo para el reporte
├── powerbi/
│   ├── GUIA-POWER-BI.md             Guía paso a paso
│   └── medidas-dax.txt              9 medidas DAX + tabla de calendario
└── src/PruebaTecnica.Web/
    ├── Program.cs                   Composición, Swagger, chequeo de conexión
    ├── appsettings.json             Cadena de conexión
    ├── Data/AppDbContext.cs         Mapeo a las tablas y vistas existentes
    ├── Models/
    │   ├── Venta.cs                 Entidad permisiva (refleja la base real)
    │   ├── Producto.cs              Maestro
    │   ├── VentaInput.cs            Modelo de entrada, con validaciones
    │   ├── VistasSql.cs             Entidades keyless de las vistas
    │   ├── Consultas.cs             Filtros y paginación
    │   └── Dtos.cs                  Contratos de la API
    ├── Services/                    Reglas de negocio
    ├── Controllers/
    │   ├── VentasController.cs      CRUD de ventas (MVC)
    │   ├── ProductosController.cs   CRUD de productos (MVC)
    │   ├── ResumenController.cs     Resúmenes mensuales (MVC)
    │   └── Api/VentasApiController.cs   API REST + Swagger
    ├── Middleware/
    │   └── ManejadorDeErrores.cs    Errores: JSON en /api, página en el resto
    └── Views/                       Razor
```
