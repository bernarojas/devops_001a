/*==============================================================================
  PRUEBA TÉCNICA — SQL SERVER
  Archivo 2 de 2: análisis de calidad de datos (punto 1.3)
  Requiere haber ejecutado antes 01_esquema_y_matriz.sql

  Este script sólo LEE. No modifica ni corrige nada.
  Detectar y corregir son decisiones distintas: la corrección depende de reglas
  de negocio que el enunciado no define (¿una cantidad negativa es una
  devolución legítima o un error de carga?). Al final del archivo se dejan las
  sentencias de corrección propuestas, comentadas y sin ejecutar.
==============================================================================*/

USE [Tecnica];
GO

SET NOCOUNT ON;
GO

/*==============================================================================
  TABLERO RESUMEN
  Una fila por chequeo, para ver el estado general de un vistazo.
==============================================================================*/

PRINT '';
PRINT '=================== TABLERO DE CALIDAD DE DATOS ===================';

SELECT Chequeo, FilasAfectadas, Severidad
FROM (
    SELECT 1 AS Orden,
           '1a. Ventas duplicadas exactas (todos los campos iguales)' AS Chequeo,
           (SELECT ISNULL(SUM(Repeticiones - 1), 0)
            FROM (SELECT COUNT(*) AS Repeticiones FROM dbo.Ventas
                  GROUP BY Compania, Producto, Fecha, Cantidad, Precio
                  HAVING COUNT(*) > 1) AS d)                          AS FilasAfectadas,
           'Alta'                                                     AS Severidad
    UNION ALL
    SELECT 2, '1b. Mismo cliente/producto/dia, montos distintos (revisar)',
           (SELECT ISNULL(SUM(Repeticiones - 1), 0)
            FROM (SELECT COUNT(*) AS Repeticiones FROM dbo.Ventas
                  GROUP BY Compania, Producto, CAST(Fecha AS DATE)
                  HAVING COUNT(*) > 1) AS d),
           'Informativa'
    UNION ALL
    SELECT 3, '2. Cantidades negativas',
           (SELECT COUNT(*) FROM dbo.Ventas WHERE Cantidad < 0), 'Alta'
    UNION ALL
    SELECT 4, '3. Precio igual a 0',
           (SELECT COUNT(*) FROM dbo.Ventas WHERE Precio = 0), 'Alta'
    UNION ALL
    SELECT 5, '4a. Fecha nula',
           (SELECT COUNT(*) FROM dbo.Ventas WHERE Fecha IS NULL), 'Alta'
    UNION ALL
    SELECT 6, '4b. Fecha fuera de rango razonable (anterior a 2000 o futura)',
           (SELECT COUNT(*) FROM dbo.Ventas
            WHERE Fecha < '2000-01-01' OR Fecha > DATEADD(DAY, 1, GETDATE())), 'Media'
    UNION ALL
    SELECT 7, '5. Celdas producto x periodo sin ventas',
           (SELECT COUNT(*) FROM dbo.vw_MatrizVentasMensual WHERE NumeroTransacciones = 0), 'Informativa'
    UNION ALL
    SELECT 8, '6. Producto (texto) desincronizado de IdProducto (FK)',
           (SELECT COUNT(*) FROM dbo.Ventas v
            LEFT JOIN dbo.Productos p ON p.IdProducto = v.IdProducto
            WHERE v.IdProducto IS NULL OR p.NombreProducto <> LTRIM(RTRIM(v.Producto))), 'Alta'
    UNION ALL
    SELECT 9, '7. Cantidad o Precio nulos',
           (SELECT COUNT(*) FROM dbo.Ventas WHERE Cantidad IS NULL OR Precio IS NULL), 'Alta'
    UNION ALL
    SELECT 10, '8. Compania o Producto vacios',
           (SELECT COUNT(*) FROM dbo.Ventas
            WHERE Compania IS NULL OR LTRIM(RTRIM(Compania)) = ''
               OR Producto IS NULL OR LTRIM(RTRIM(Producto)) = ''), 'Alta'
) AS t
ORDER BY Orden;
GO


/*==============================================================================
  CHEQUEO 1 — POSIBLES VENTAS DUPLICADAS
  ------------------------------------------------------------------------------
  Se separa en dos niveles porque "duplicado" tiene dos lecturas muy distintas:

  1a) DUPLICADO EXACTO: misma compañía, producto, fecha, cantidad y precio.
      Es casi con certeza un error de carga (doble INSERT). Alta confianza.

  1b) MISMA CLAVE DE NEGOCIO: misma compañía, producto y día, pero cantidad o
      precio distintos. NO es necesariamente un error: una empresa puede
      comprarle dos veces al mismo proveedor en un mismo día. Se reporta como
      informativo, para revisión humana, no para borrado automático.

  ROW_NUMBER() marca cuál fila conservar (la de menor ID) y cuáles sobran.
==============================================================================*/

PRINT '';
PRINT '--- 1a. DUPLICADOS EXACTOS (candidatos a eliminar) ---';

WITH Duplicados AS
(
    SELECT  v.ID, v.Compania, v.Producto, v.Fecha, v.Cantidad, v.Precio,
            ROW_NUMBER() OVER (PARTITION BY v.Compania, v.Producto, v.Fecha, v.Cantidad, v.Precio
                               ORDER BY v.ID)                            AS NumeroCopia,
            COUNT(*)   OVER (PARTITION BY v.Compania, v.Producto, v.Fecha, v.Cantidad, v.Precio)
                                                                         AS TotalCopias
    FROM    dbo.Ventas AS v
)
SELECT      ID, Compania, Producto, Fecha, Cantidad, Precio, NumeroCopia, TotalCopias,
            CASE WHEN NumeroCopia = 1 THEN 'CONSERVAR' ELSE 'ELIMINAR' END AS Accion
FROM        Duplicados
WHERE       TotalCopias > 1
ORDER BY    Compania, Producto, Fecha, NumeroCopia;

PRINT '';
PRINT '--- 1b. MISMA COMPANIA + PRODUCTO + DIA, con montos distintos (solo revisar) ---';

SELECT TOP 20
            v.Compania,
            v.Producto,
            CAST(v.Fecha AS DATE)                AS Dia,
            COUNT(*)                             AS Registros,
            COUNT(DISTINCT v.Precio)             AS PreciosDistintos,
            MIN(v.Precio)                        AS PrecioMin,
            MAX(v.Precio)                        AS PrecioMax,
            SUM(v.Cantidad)                      AS CantidadTotal
FROM        dbo.Ventas AS v
GROUP BY    v.Compania, v.Producto, CAST(v.Fecha AS DATE)
HAVING      COUNT(*) > 1
ORDER BY    COUNT(*) DESC, v.Compania, v.Producto;
GO


/*==============================================================================
  CHEQUEO 2 — CANTIDADES NEGATIVAS
  ------------------------------------------------------------------------------
  Una cantidad negativa puede ser legítima (nota de crédito / devolución) o un
  error de digitación. El dato por sí solo no lo distingue, así que se reporta
  el impacto en dinero para dimensionar el problema antes de decidir.
==============================================================================*/

PRINT '';
PRINT '--- 2. CANTIDADES NEGATIVAS: impacto agregado ---';

SELECT  COUNT(*)                                                    AS FilasAfectadas,
        MIN(v.Cantidad)                                             AS CantidadMasNegativa,
        SUM(v.Cantidad)                                             AS SumaDeCantidades,
        CAST(SUM(CAST(v.Cantidad AS DECIMAL(19,4)) * v.Precio)
             AS DECIMAL(19,2))                                      AS ImpactoEnTotalVentas,
        COUNT(DISTINCT v.Producto)                                  AS ProductosInvolucrados,
        COUNT(DISTINCT v.Compania)                                  AS CompaniasInvolucradas
FROM    dbo.Ventas AS v
WHERE   v.Cantidad < 0;

PRINT '';
PRINT '--- 2. CANTIDADES NEGATIVAS: detalle (primeras 20) ---';

SELECT TOP 20
        v.ID, v.Compania, v.Producto, v.Fecha, v.Cantidad, v.Precio,
        CAST(CAST(v.Cantidad AS DECIMAL(19,4)) * v.Precio AS DECIMAL(19,2)) AS TotalLinea
FROM    dbo.Ventas AS v
WHERE   v.Cantidad < 0
ORDER BY v.Cantidad ASC, v.ID;
GO


/*==============================================================================
  CHEQUEO 3 — PRECIOS IGUALES A 0
  ------------------------------------------------------------------------------
  Precio 0 hace que la venta aporte 0 al total aunque tenga cantidad > 0.
  Es la falla más silenciosa de las tres: no rompe nada, sólo subestima los
  ingresos sin dejar rastro visible en el reporte.

  Se compara contra el precio habitual del mismo producto para mostrar cuánto
  se está perdiendo, lo que además da una vía de corrección razonable.
==============================================================================*/

PRINT '';
PRINT '--- 3. PRECIOS EN 0: impacto y precio de referencia del producto ---';

WITH PrecioReferencia AS
(
    -- Precio mediano de cada producto, ignorando los ceros.
    SELECT DISTINCT
           v.Producto,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.Precio)
               OVER (PARTITION BY v.Producto)                AS PrecioMediano
    FROM   dbo.Ventas AS v
    WHERE  v.Precio > 0
)
SELECT TOP 20
        v.ID, v.Compania, v.Producto, v.Fecha, v.Cantidad,
        v.Precio                                                       AS PrecioRegistrado,
        CAST(r.PrecioMediano AS DECIMAL(19,2))                         AS PrecioMedianoDelProducto,
        CAST(v.Cantidad * ISNULL(r.PrecioMediano, 0) AS DECIMAL(19,2)) AS IngresoNoContabilizado
FROM    dbo.Ventas       AS v
LEFT JOIN PrecioReferencia AS r ON r.Producto = v.Producto
WHERE   v.Precio = 0
ORDER BY IngresoNoContabilizado DESC;

PRINT '';
PRINT '--- 3. PRECIOS EN 0: total dejado de facturar (estimado con precio mediano) ---';

WITH PrecioReferencia AS
(
    SELECT DISTINCT
           v.Producto,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY v.Precio)
               OVER (PARTITION BY v.Producto)                AS PrecioMediano
    FROM   dbo.Ventas AS v
    WHERE  v.Precio > 0
)
SELECT  COUNT(*)                                                          AS FilasConPrecioCero,
        SUM(v.Cantidad)                                                   AS UnidadesAfectadas,
        COUNT(CASE WHEN r.PrecioMediano IS NULL THEN 1 END)               AS SinPrecioDeReferencia,
        CAST(SUM(v.Cantidad * ISNULL(r.PrecioMediano, 0)) AS DECIMAL(19,2)) AS IngresoEstimadoNoRegistrado
FROM    dbo.Ventas       AS v
LEFT JOIN PrecioReferencia AS r ON r.Producto = v.Producto
WHERE   v.Precio = 0;
GO


/*==============================================================================
  CHEQUEO 4 — FECHAS NULAS O INVÁLIDAS
  ------------------------------------------------------------------------------
  La columna Fecha es DATETIME, así que SQL Server ya impide guardar un valor
  sintácticamente inválido como '2024-02-31': ese INSERT falla. Por lo tanto
  "inválida" acá sólo puede significar inválida PARA EL NEGOCIO. Se revisan:

    - NULL
    - anteriores al 2000 (probable fecha centinela tipo 1900-01-01)
    - posteriores a hoy (una venta no puede estar registrada en el futuro)
    - con componente de hora, que rompería un GROUP BY por día mal escrito
==============================================================================*/

PRINT '';
PRINT '--- 4. DIAGNOSTICO DE FECHAS ---';

SELECT  COUNT(*)                                                          AS TotalFilas,
        SUM(CASE WHEN v.Fecha IS NULL             THEN 1 ELSE 0 END)      AS Nulas,
        SUM(CASE WHEN v.Fecha < '2000-01-01'      THEN 1 ELSE 0 END)      AS AnterioresA2000,
        SUM(CASE WHEN v.Fecha > DATEADD(DAY, 1, GETDATE()) THEN 1 ELSE 0 END) AS Futuras,
        SUM(CASE WHEN v.Fecha <> CAST(v.Fecha AS DATE) THEN 1 ELSE 0 END) AS ConComponenteDeHora,
        MIN(v.Fecha)                                                      AS FechaMinima,
        MAX(v.Fecha)                                                      AS FechaMaxima
FROM    dbo.Ventas AS v;

PRINT '';
PRINT '--- 4. FECHAS FUTURAS: distribucion por periodo ---';
/* En este set hay ventas con fecha posterior a hoy. No se asume que sean un
   error: podrian ser proyecciones o datos de prueba cargados a futuro. Se
   cuantifican para que el negocio decida si entran o no en los reportes. */

SELECT      DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)  AS Periodo,
            COUNT(*)                                         AS Filas,
            CAST(SUM(CAST(v.Cantidad AS DECIMAL(19,4)) * v.Precio)
                 AS DECIMAL(19,2))                           AS TotalVentas
FROM        dbo.Ventas AS v
WHERE       v.Fecha > DATEADD(DAY, 1, GETDATE())
GROUP BY    DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)
ORDER BY    Periodo;

PRINT '';
PRINT '--- 4. HUECOS EN EL CALENDARIO: meses sin ninguna venta ---';
/* Distinto de "producto sin ventas": aca no hay NINGUNA venta en todo el mes.
   Suele indicar una carga de datos incompleta. */

WITH Calendario AS
(
    SELECT  DATEADD(MONTH, n.Numero, (SELECT DATEFROMPARTS(YEAR(MIN(Fecha)), MONTH(MIN(Fecha)), 1)
                                      FROM dbo.Ventas)) AS Periodo
    FROM   (SELECT TOP (600) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS Numero
            FROM sys.all_objects) AS n
),
Existentes AS
(
    SELECT DISTINCT DATEFROMPARTS(YEAR(Fecha), MONTH(Fecha), 1) AS Periodo
    FROM   dbo.Ventas WHERE Fecha IS NOT NULL
)
SELECT      c.Periodo AS MesSinNingunaVenta
FROM        Calendario AS c
WHERE       c.Periodo <= (SELECT MAX(Periodo) FROM Existentes)
  AND       NOT EXISTS (SELECT 1 FROM Existentes AS e WHERE e.Periodo = c.Periodo)
ORDER BY    c.Periodo;
GO


/*==============================================================================
  CHEQUEO 5 — PRODUCTOS SIN VENTAS EN DETERMINADOS PERÍODOS
  ------------------------------------------------------------------------------
  Sale directo de la matriz del punto 1.2: son exactamente las celdas donde el
  CROSS JOIN generó la combinación pero el LEFT JOIN no encontró ventas.
==============================================================================*/

PRINT '';
PRINT '--- 5a. PRODUCTOS QUE NUNCA TUVIERON UNA VENTA EN NINGUN PERIODO ---';

SELECT      p.IdProducto, p.NombreProducto
FROM        dbo.Productos AS p
WHERE       NOT EXISTS (SELECT 1 FROM dbo.Ventas AS v WHERE v.IdProducto = p.IdProducto)
ORDER BY    p.NombreProducto;

PRINT '';
PRINT '--- 5b. RANKING: productos con mas periodos sin ventas ---';

SELECT TOP 20
            m.Producto,
            COUNT(*)                                                        AS PeriodosTotales,
            SUM(CASE WHEN m.NumeroTransacciones = 0 THEN 1 ELSE 0 END)      AS PeriodosSinVentas,
            SUM(CASE WHEN m.NumeroTransacciones > 0 THEN 1 ELSE 0 END)      AS PeriodosConVentas,
            CAST(100.0 * SUM(CASE WHEN m.NumeroTransacciones = 0 THEN 1 ELSE 0 END)
                 / COUNT(*) AS DECIMAL(5,1))                                AS PorcentajeSinVentas
FROM        dbo.vw_MatrizVentasMensual AS m
GROUP BY    m.Producto
ORDER BY    PeriodosSinVentas DESC, m.Producto;

PRINT '';
PRINT '--- 5c. PRODUCTOS QUE DEJARON DE VENDERSE (sin ventas en los ultimos 3 periodos) ---';
/* Caso de negocio concreto: producto que se vendia y se apago. Mas accionable
   que la lista cruda de celdas en cero. */

WITH UltimosPeriodos AS
(
    SELECT TOP 3 Periodo
    FROM  (SELECT DISTINCT Periodo FROM dbo.vw_MatrizVentasMensual) AS p
    ORDER BY Periodo DESC
),
Marcado AS
(
    /* Se marca cada celda como reciente o no ANTES de agrupar. SQL Server no
       permite una subconsulta dentro de un agregado (SUM(CASE WHEN x IN (SELECT ...))),
       asi que la pertenencia se resuelve con un LEFT JOIN previo. */
    SELECT      m.Producto,
                m.Periodo,
                m.NumeroTransacciones,
                m.CantidadVentas,
                CASE WHEN u.Periodo IS NOT NULL THEN 1 ELSE 0 END AS EsPeriodoReciente
    FROM        dbo.vw_MatrizVentasMensual AS m
    LEFT JOIN   UltimosPeriodos            AS u ON u.Periodo = m.Periodo
)
SELECT      Producto,
            MAX(CASE WHEN NumeroTransacciones > 0 THEN Periodo END)  AS UltimoPeriodoConVenta,
            SUM(CantidadVentas)                                      AS UnidadesHistoricas
FROM        Marcado
GROUP BY    Producto
HAVING      SUM(CASE WHEN EsPeriodoReciente = 1 THEN NumeroTransacciones ELSE 0 END) = 0
       AND  SUM(NumeroTransacciones) > 0
ORDER BY    UltimoPeriodoConVenta DESC, Producto;
GO


/*==============================================================================
  CHEQUEO 6 — CONSISTENCIA INTERNA DE LA SOLUCIÓN
  ------------------------------------------------------------------------------
  Verifica la decisión tomada en 01: Ventas guarda el producto dos veces
  (texto + FK). Si alguna vez se desincronizan, este chequeo lo delata.
  Debe devolver siempre 0 filas.
==============================================================================*/

PRINT '';
PRINT '--- 6. VENTAS CON Producto (texto) DISTINTO DE SU FK IdProducto ---';

SELECT      v.ID, v.Producto AS ProductoTexto, v.IdProducto, p.NombreProducto AS ProductoSegunFK
FROM        dbo.Ventas    AS v
LEFT JOIN   dbo.Productos AS p ON p.IdProducto = v.IdProducto
WHERE       v.IdProducto IS NULL
   OR       p.NombreProducto <> LTRIM(RTRIM(v.Producto));
GO


/*==============================================================================
  CORRECCIONES PROPUESTAS — NO SE EJECUTAN
  ------------------------------------------------------------------------------
  Se dejan escritas y comentadas a propósito. Aplicarlas es una decisión de
  negocio, y en una prueba técnica borrar filas del set original sin que nadie
  lo pida es un error, no una virtud.

  Antes de aplicar cualquiera de estas: respaldar la tabla.
==============================================================================*/

/*
-- A) Eliminar duplicados exactos, conservando la fila de menor ID.
;WITH Duplicados AS
(
    SELECT ROW_NUMBER() OVER (PARTITION BY Compania, Producto, Fecha, Cantidad, Precio
                              ORDER BY ID) AS NumeroCopia
    FROM   dbo.Ventas
)
DELETE FROM Duplicados WHERE NumeroCopia > 1;


-- B) Marcar en lugar de borrar: mucho más seguro que A, y reversible.
ALTER TABLE dbo.Ventas ADD EsSospechosa BIT NOT NULL DEFAULT (0);
GO
UPDATE dbo.Ventas SET EsSospechosa = 1 WHERE Cantidad < 0 OR Precio = 0 OR Fecha IS NULL;


-- C) Impedir que entren datos malos de ahora en adelante (la corrección de raíz).
ALTER TABLE dbo.Ventas WITH NOCHECK   -- NOCHECK: no valida el historial, sí lo nuevo
    ADD CONSTRAINT CK_Ventas_Cantidad CHECK (Cantidad > 0),
        CONSTRAINT CK_Ventas_Precio   CHECK (Precio  > 0),
        CONSTRAINT CK_Ventas_Fecha    CHECK (Fecha  >= '2000-01-01');


-- D) Imputar el precio faltante con la mediana del producto.
;WITH PrecioReferencia AS
(
    SELECT DISTINCT Producto,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Precio)
               OVER (PARTITION BY Producto) AS PrecioMediano
    FROM   dbo.Ventas WHERE Precio > 0
)
UPDATE  v
SET     v.Precio = CAST(r.PrecioMediano AS DECIMAL(18,2))
FROM    dbo.Ventas AS v
JOIN    PrecioReferencia AS r ON r.Producto = v.Producto
WHERE   v.Precio = 0;
*/
GO
