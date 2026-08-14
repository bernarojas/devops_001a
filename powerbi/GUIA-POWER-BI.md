# Guía paso a paso — Reporte en Power BI Desktop

Guía para armar el reporte desde cero, asumiendo que nunca usaste Power BI.
Toma unos 20 minutos. Al final tenés que guardar el archivo como
`powerbi/ReporteVentas.pbix`, que es uno de los entregables.

**Requisito previo:** el contenedor `mssql-tecnica` corriendo y los tres scripts
de la carpeta `sql/` ejecutados. Verificalo con:

```bash
docker ps
```

Tiene que aparecer `mssql-tecnica` con estado `Up`.

---

## Qué es Power BI, en una frase

Es una herramienta que se conecta a una fuente de datos, arma un modelo en
memoria y te deja dibujar gráficos arrastrando campos. No escribís SQL: el SQL
ya está hecho en las vistas. Lo único que se escribe acá es **DAX**, un lenguaje
de fórmulas parecido al de Excel, para los cálculos que no vienen precalculados.

---

## Paso 1 — Abrir Power BI y conectar a SQL Server

1. Abrí **Power BI Desktop** (menú Inicio de Windows).
2. Si aparece una pantalla de bienvenida o te pide iniciar sesión, cerrala con la
   **X**. No hace falta cuenta de Microsoft para trabajar en local ni para
   guardar el `.pbix`.
3. En la cinta superior: **Inicio → Obtener datos → SQL Server**.
4. Completá:

   | Campo | Valor |
   |---|---|
   | Servidor | `localhost,1433` |
   | Base de datos | `Tecnica` |
   | Modo de conectividad de datos | **Importar** |

   > **Importar** trae los datos a memoria; el reporte queda rápido y
   > autocontenido. La alternativa, *DirectQuery*, consulta SQL Server en cada
   > clic: sirve para datos que cambian a cada segundo, no para este caso.

5. Click en **Aceptar**.
6. Te va a pedir credenciales. Elegí la pestaña **Base de datos** (no Windows) y
   completá:

   - Nombre de usuario: `sa`
   - Contraseña: `Tecnica#2026!Sql`

7. Click en **Conectar**.
8. Si aparece un aviso de que no se pudo verificar la identidad del servidor por
   el certificado, elegí **Aceptar** / **Sí**. Es esperado: el contenedor usa un
   certificado autofirmado.

---

## Paso 2 — Elegir las tablas

En el **Navegador** que se abre, marcá estas dos casillas:

- ☑ `dbo.vw_VentasPowerBI`
- ☑ `dbo.vw_MatrizVentasMensual`

Click en **Cargar** y esperá (son unas 15.000 filas más 31.820 de la matriz;
tarda pocos segundos).

> No cargues `dbo.Ventas` directamente: la vista `vw_VentasPowerBI` ya trae el
> período calculado con la misma regla del punto 1.2 y los nombres de mes en
> español, así no hay que recalcular nada en DAX.

---

## Paso 3 — Renombrar tablas y columnas

Esto importa, porque la medida DAX del enunciado se escribe literalmente
`SUMX(Ventas, Ventas[Cantidad] * Ventas[Precio])`.

1. En el panel **Datos** (derecha), buscá `vw_VentasPowerBI`.
2. Click derecho → **Cambiar nombre**.
3. Escribí `Ventas` y presioná Enter.

Hacé lo mismo con `vw_MatrizVentasMensual` → renombrala a `MatrizMensual`.

### Renombrar también las columnas

Los nombres de la base de datos no deberían llegar a la pantalla. Power BI usa
el nombre del campo como título del visual y como rótulo del eje, así que un
`AnioMes` sin tocar produce un gráfico titulado *"Total Ventas por AnioMes"*.

Renombrar la columna en el modelo lo arregla en todos lados a la vez —título,
eje, tooltips y la matriz— en lugar de tener que editar cada visual. El cambio
vive en el modelo, no toca la vista SQL, y se conserva al actualizar los datos.

Doble click sobre cada nombre en el panel Datos:

| Nombre original | Renombrar a |
|---|---|
| `AnioMes` | `Mes` |
| `Compania` | `Compañía` |
| `TotalLinea` | `Total línea` |
| `TieneAnomalia` | `Tiene anomalía` |

> No renombres `AnioMes` a "Período": ya existe la columna `Periodo` —la fecha
> `2025-04-01` que alimenta el filtro— y dos campos con el mismo nombre visible
> confunden a quien lea el modelo.

### Ocultar lo que nadie va a usar

Estas columnas sólo sirven internamente y ensucian el panel. Click derecho →
**Ocultar en la vista de informes**:

`IdVenta` · `Anio` · `NumeroMes` · `Trimestre` · `NombreMes`

Un modelo donde sólo se ven los campos que alguien usaría de verdad se lee
mucho más profesional que uno con quince columnas crudas.

---

## Paso 4 — Crear las medidas DAX

Abrí el archivo `powerbi/medidas-dax.txt` que está en esta misma carpeta.

Para cada medida:

1. **Inicio → Nueva medida**.
2. Se abre una barra de fórmulas arriba. Borrá lo que dice (`Medida = `).
3. Pegá el bloque completo del archivo, **incluyendo el nombre y el signo `=`**.
4. Presioná Enter.

Empezá por las tres primeras, que son las que cubren el requisito:

- `Total Ventas` ← **la medida DAX que pide el enunciado**
- `Cantidad Vendida`
- `Numero de Ventas`

Las medidas 4 a 9 son opcionales y suman puntos. Las medidas 6 y 7
(comparación con el mes anterior) requieren además el Paso 6.

### Darles formato de número

Con la medida seleccionada en el panel Datos, andá a la pestaña
**Herramientas de medidas** (arriba) y configurá:

- `Total Ventas`, `Ticket Promedio`, `Precio Promedio Ponderado` → **Formato:** Moneda, **Posiciones decimales:** 0
- `Cantidad Vendida`, `Numero de Ventas` → **Formato:** Número entero, **separador de miles** activado
- `Variacion vs Mes Anterior %` → **Formato:** Porcentaje, 1 decimal

---

## Paso 5 — Armar los visuales

Trabajás en el lienzo blanco del centro. Para cada visual: primero click en el
ícono del tipo de gráfico en el panel **Visualizaciones**, después arrastrás los
campos desde el panel **Datos** a los huecos que aparecen.

El enunciado pide 6 cosas. Acá va cada una:

### 5.1 — Total vendido (tarjeta)

- Visual: **Tarjeta** (ícono `123`)
- Campo → hueco *Campos*: medida `Total Ventas`

Agregá dos tarjetas más al lado con `Cantidad Vendida` y `Numero de Ventas`.
Poné las tres arriba, en fila.

### 5.2 — Ventas por mes (gráfico de columnas)

- Visual: **Gráfico de columnas agrupadas**
- *Eje X*: `Ventas[Mes]`  (la columna que renombraste en el paso 3)
- *Eje Y*: medida `Total Ventas`

> Se usa esa columna (texto `2025-01`) y no `NombreMes`, porque `NombreMes` se
> ordenaría alfabéticamente — Abril antes que Enero — mientras que el formato
> `AAAA-MM`, al ser texto de ancho fijo, se ordena correctamente solo.

Para que quede ordenado: click en los **⋯** arriba a la derecha del visual →
**Ordenar eje** → `Mes` → **Orden ascendente**.

### 5.3 — Ventas por producto (gráfico de barras)

- Visual: **Gráfico de barras agrupadas**
- *Eje Y*: `Ventas[Producto]`
- *Eje X*: medida `Total Ventas`

Con 860 productos el gráfico es ilegible, así que limitalo a los mejores:

- Panel **Filtros** → arrastrá `Ventas[Producto]` al área *Filtros de este visual*
- Tipo de filtro: **N superior**
- Mostrar elementos: **Superior** `15`
- Por valor: arrastrá la medida `Total Ventas`
- **Aplicar filtro**

### 5.4 — Filtro por compañía (segmentación)

- Visual: **Segmentación de datos** (ícono con forma de embudo/filtro)
- *Campo*: `Ventas[Compania]`

Con 363 compañías, cambiale el estilo a lista desplegable con búsqueda:
seleccioná el visual → panel **Formato** (ícono del pincel) → **Configuración de
segmentación → Estilo** → **Lista desplegable**.

### 5.5 — Filtro por período (segmentación)

- Visual: **Segmentación de datos**
- *Campo*: `Ventas[Periodo]`

Power BI lo va a mostrar como control de rango de fechas, que es cómodo.
Si preferís una lista, usá `Ventas[Mes]` en su lugar.

### 5.6 — Detalle (matriz)

Este es el visual que muestra la matriz del punto 1.2:

- Visual: **Matriz**
- *Filas*: `Ventas[Producto]`
- *Columnas*: `Ventas[Mes]`
- *Valores*: medida `Total Ventas`

---

## Paso 6 — (Opcional) Tabla de calendario

Sólo si querés las medidas de comparación mensual.

1. **Modelado → Nueva tabla**.
2. Pegá el bloque `Calendario = ...` del final de `medidas-dax.txt`.
3. Enter.
4. En el panel Datos, expandí `Calendario`, click derecho en la columna `Date` →
   **Cambiar nombre** → `Fecha`.
5. Seleccioná la tabla `Calendario` → pestaña **Herramientas de tablas** →
   **Marcar como tabla de fechas** → columna `Fecha` → Aceptar.
6. Andá a la vista **Modelo** (ícono de tablas conectadas, barra izquierda) y
   arrastrá `Calendario[Fecha]` sobre `Ventas[Fecha]`.
7. Ahora sí creá las medidas 6 y 7.

---

## Paso 7 — Guardar

**Archivo → Guardar como** → la carpeta `powerbi/` de este proyecto, con el
nombre `ReporteVentas.pbix`.

---

## Paso 8 — Validar que los números están bien

Esto es lo que el enunciado llama *"cómo validó los resultados obtenidos"*, y es
la parte que más conviene no saltarse.

Con **todos los filtros limpios**, la tarjeta `Total Ventas` tiene que mostrar:

```
38.594.578.526
```

Ese número es el mismo que devuelven, por tres caminos independientes:

```sql
-- 1. Directo desde la tabla origen
SELECT SUM(CAST(Cantidad AS DECIMAL(19,4)) * Precio) FROM dbo.Ventas WHERE Fecha IS NOT NULL;

-- 2. Desde la matriz mensual del punto 1.2
SELECT SUM(TotalVentas) FROM dbo.vw_MatrizVentasMensual;

-- 3. Desde la vista que consume Power BI
SELECT SUM(TotalLinea) FROM dbo.vw_VentasPowerBI;
```

Y también coincide con el que muestra la portada de la aplicación .NET en
`http://localhost:5080`.

Otros números de control:

| Qué | Valor esperado |
|---|---|
| Cantidad Vendida (sin filtros) | 194.413 |
| Numero de Ventas (sin filtros) | 15.088 |
| Productos con Venta | 860 |
| Ventas con Anomalia | 562 |

> Sobre las 562 anomalías: son 267 filas con cantidad negativa más 300 con
> precio 0, menos 5 que tienen **las dos cosas a la vez** y por lo tanto se
> contarían dos veces si se sumaran los grupos por separado.

Si `Total Ventas` no coincide, el error casi siempre es uno de estos dos:

- Se cargó `dbo.Ventas` en lugar de `dbo.vw_VentasPowerBI`. La vista excluye las
  filas con fecha nula; la tabla no.
- La medida se escribió con `SUM(Cantidad) * SUM(Precio)` en lugar de `SUMX`.
  Eso multiplica totales y da un número enormemente mayor.

---

## Paso 9 — Capturas

El enunciado acepta `.pbix` **o** capturas. Conviene entregar las dos cosas.
Guardá las imágenes en esta carpeta como `captura-01.png`, `captura-02.png`, etc.

Recomendado capturar:

1. El reporte completo con todos los visuales y sin filtros.
2. El mismo reporte filtrado por una compañía concreta (por ejemplo `Northwind`),
   para mostrar que los filtros funcionan.
3. La barra de fórmulas con la medida `Total Ventas` visible.
