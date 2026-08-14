/*==============================================================================
  PRUEBA TÉCNICA — SQL SERVER
  Archivo 1 de 2: esquema (maestro de productos) + matriz mensual de ventas
  Base de datos: Tecnica     Motor probado: SQL Server 2022 (16.0.4265.3)

  Este script es IDEMPOTENTE: se puede ejecutar tantas veces como se quiera
  sin romper nada ni duplicar datos.

  Orden de ejecución:
      01_esquema_y_matriz.sql   <-- este archivo
      02_analisis_datos.sql
==============================================================================*/

USE [Tecnica];
GO

SET NOCOUNT ON;
GO

/*==============================================================================
  1.1  MAESTRO DE PRODUCTOS
  ------------------------------------------------------------------------------
  La tabla origen dbo.Ventas guarda el producto como texto libre (nvarchar(100)),
  repetido en cada fila. Se extrae ese texto a una tabla maestra dbo.Productos.

  Estructura mínima pedida: IdProducto + NombreProducto.
  Se agregan dos columnas de apoyo:
    - Activo:        permite dar de baja un producto sin borrar su historial de
                     ventas (borrado lógico). El CRUD de la app .NET lo usa.
    - FechaCreacion: trazabilidad de cuándo entró el producto al maestro.
==============================================================================*/

-- Se elimina primero la FK para poder recrear la tabla si el script se re-ejecuta.
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Ventas_Productos')
    ALTER TABLE dbo.Ventas DROP CONSTRAINT FK_Ventas_Productos;
GO

IF OBJECT_ID('dbo.Productos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Productos
    (
        IdProducto     INT           IDENTITY(1,1) NOT NULL,
        NombreProducto NVARCHAR(100) NOT NULL,
        Activo         BIT           NOT NULL CONSTRAINT DF_Productos_Activo        DEFAULT (1),
        FechaCreacion  DATETIME2(0)  NOT NULL CONSTRAINT DF_Productos_FechaCreacion DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Productos          PRIMARY KEY CLUSTERED (IdProducto),
        CONSTRAINT UQ_Productos_Nombre   UNIQUE (NombreProducto)
    );
END
GO

/* Carga incremental: sólo inserta los productos que todavía no existen.
   Se aplica TRIM porque un nombre con espacios sobrantes generaría un producto
   fantasma duplicado. (En estos datos no hay ninguno, pero la defensa es barata.) */
INSERT INTO dbo.Productos (NombreProducto)
SELECT DISTINCT LTRIM(RTRIM(v.Producto))
FROM   dbo.Ventas AS v
WHERE  v.Producto IS NOT NULL
  AND  LTRIM(RTRIM(v.Producto)) <> ''
  AND  NOT EXISTS (SELECT 1 FROM dbo.Productos AS p
                   WHERE p.NombreProducto = LTRIM(RTRIM(v.Producto)));
GO


/*------------------------------------------------------------------------------
  Relación Ventas -> Productos
  ------------------------------------------------------------------------------
  DECISIÓN: se agrega a dbo.Ventas una columna IdProducto con FK al maestro,
  PERO se conserva intacta la columna original Producto (texto).

  ¿Por qué las dos?
    - IdProducto da integridad referencial real: ya no se puede registrar una
      venta de un producto que no existe en el maestro, y renombrar un producto
      no rompe el histórico.
    - Producto (texto) se conserva para no alterar la estructura que el
      enunciado da por sentada y para no romper consultas o reportes existentes.

  El costo de esta decisión es que ambas columnas deben mantenerse sincronizadas.
  La app .NET escribe siempre las dos desde el maestro, y el archivo
  02_analisis_datos.sql incluye una query (chequeo #6) que detecta cualquier
  desincronización.
------------------------------------------------------------------------------*/

IF COL_LENGTH('dbo.Ventas', 'IdProducto') IS NULL
    ALTER TABLE dbo.Ventas ADD IdProducto INT NULL;
GO

UPDATE  v
SET     v.IdProducto = p.IdProducto
FROM    dbo.Ventas    AS v
JOIN    dbo.Productos AS p ON p.NombreProducto = LTRIM(RTRIM(v.Producto))
WHERE   v.IdProducto IS NULL
   OR   v.IdProducto <> p.IdProducto;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Ventas_Productos')
    ALTER TABLE dbo.Ventas WITH CHECK
        ADD CONSTRAINT FK_Ventas_Productos
        FOREIGN KEY (IdProducto) REFERENCES dbo.Productos (IdProducto);
GO

/* Índices de apoyo: la matriz mensual agrupa por producto y por mes. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Ventas_IdProducto_Fecha' AND object_id = OBJECT_ID('dbo.Ventas'))
    CREATE NONCLUSTERED INDEX IX_Ventas_IdProducto_Fecha
        ON dbo.Ventas (IdProducto, Fecha) INCLUDE (Cantidad, Precio);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Ventas_Compania_Fecha' AND object_id = OBJECT_ID('dbo.Ventas'))
    CREATE NONCLUSTERED INDEX IX_Ventas_Compania_Fecha
        ON dbo.Ventas (Compania, Fecha) INCLUDE (IdProducto, Cantidad, Precio);
GO


/*==============================================================================
  1.2  MATRIZ MENSUAL DE VENTAS POR PRODUCTO
  ------------------------------------------------------------------------------
  Salida: Producto | Periodo | CantidadVentas | TotalVentas

  REGLA DEL PERÍODO
    El período es el primer día del mes de la fecha de venta.
        2024-01-07 -> 2024-01-01
        2024-05-31 -> 2024-05-01
    Se usa DATEFROMPARTS(YEAR(Fecha), MONTH(Fecha), 1), que es explícito y
    legible. Un equivalente clásico, compatible con versiones anteriores a
    SQL Server 2012, sería:  DATEADD(month, DATEDIFF(month, 0, Fecha), 0).

  MATRIZ COMPLETA (producto x período)
    El requisito es que aparezcan TODOS los productos en TODOS los períodos
    existentes, con 0 cuando no hubo ventas. Eso se consigue con:
        dbo.Productos  CROSS JOIN  (períodos existentes)  LEFT JOIN  (agregado)
    El CROSS JOIN genera la grilla completa y el LEFT JOIN + ISNULL rellena
    los huecos con 0.

  SUPUESTO SOBRE "PERÍODOS EXISTENTES"
    Se toman los períodos que realmente aparecen en dbo.Ventas (37 meses), no un
    calendario continuo. Esto importa porque los datos tienen un hueco real:
    no hay ninguna venta entre 2024-08 y 2024-12. Al leer el enunciado de forma
    literal ("todos los períodos existentes"), esos 5 meses NO se inventan.
    Si el negocio prefiriera una serie continua, basta reemplazar el CTE
    Periodos por un calendario generado; se deja la variante comentada abajo.

  SUPUESTO SOBRE "CantidadVentas"
    El nombre es ambiguo: puede ser "unidades vendidas" o "número de ventas".
    Se resuelve entregando ambas y sin obligar a elegir:
        CantidadVentas      = SUM(Cantidad)  -> unidades  (columna que pide el enunciado)
        NumeroTransacciones = COUNT(*)       -> cantidad de registros de venta
    La razón para que CantidadVentas sean unidades es el ejemplo de JSON del
    propio enunciado: cantidadVentas 10 con totalVentas 250000 implica un
    precio unitario de 25.000, coherente con Cantidad * Precio.

  SUPUESTO SOBRE FILAS SUCIAS
    Las cantidades negativas (267 filas) y los precios en 0 (300 filas) SE
    INCLUYEN en la matriz. La matriz debe reflejar lo que dice la base, no una
    versión maquillada. Esas filas se identifican y cuantifican por separado en
    02_analisis_datos.sql, que es donde corresponde decidir qué hacer con ellas.
==============================================================================*/

CREATE OR ALTER VIEW dbo.vw_MatrizVentasMensual
AS
WITH Periodos AS
(
    -- Períodos que realmente existen en los datos.
    SELECT DISTINCT DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1) AS Periodo
    FROM   dbo.Ventas AS v
    WHERE  v.Fecha IS NOT NULL

    /* --- VARIANTE: calendario continuo (rellena el hueco 2024-08 .. 2024-12) ---
    SELECT DATEADD(MONTH, n.Numero, (SELECT DATEFROMPARTS(YEAR(MIN(Fecha)), MONTH(MIN(Fecha)), 1) FROM dbo.Ventas))
    FROM (SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS Numero
          FROM sys.all_objects) AS n
    WHERE DATEADD(MONTH, n.Numero, (SELECT DATEFROMPARTS(YEAR(MIN(Fecha)), MONTH(MIN(Fecha)), 1) FROM dbo.Ventas))
          <= (SELECT DATEFROMPARTS(YEAR(MAX(Fecha)), MONTH(MAX(Fecha)), 1) FROM dbo.Ventas)
    --------------------------------------------------------------------------- */
),
Agregado AS
(
    SELECT  v.IdProducto,
            DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)          AS Periodo,
            SUM(CAST(v.Cantidad AS BIGINT))                          AS CantidadVentas,
            SUM(CAST(v.Cantidad AS DECIMAL(19,4)) * v.Precio)        AS TotalVentas,
            COUNT(*)                                                 AS NumeroTransacciones
    FROM    dbo.Ventas AS v
    WHERE   v.Fecha      IS NOT NULL
      AND   v.IdProducto IS NOT NULL
    GROUP BY v.IdProducto, DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)
)
SELECT      p.IdProducto,
            p.NombreProducto                                  AS Producto,
            per.Periodo                                       AS Periodo,
            ISNULL(a.CantidadVentas, 0)                       AS CantidadVentas,
            CAST(ISNULL(a.TotalVentas, 0) AS DECIMAL(19,2))   AS TotalVentas,
            ISNULL(a.NumeroTransacciones, 0)                  AS NumeroTransacciones
FROM        dbo.Productos AS p
CROSS JOIN  Periodos      AS per
LEFT JOIN   Agregado      AS a
       ON   a.IdProducto = p.IdProducto
      AND   a.Periodo    = per.Periodo;
GO


/*------------------------------------------------------------------------------
  Resumen mensual por COMPAÑÍA + producto + período
  ------------------------------------------------------------------------------
  Es lo que consume el endpoint GET /api/ventas/resumen-mensual.

  DECISIÓN: acá NO se hace CROSS JOIN. El enunciado exige rellenar con ceros la
  matriz producto x período (1.2); no lo exige al abrir por compañía. Y con
  363 compañías x 860 productos x 37 períodos la grilla completa serían
  11.549.460 filas, casi todas en cero: inútil de leer y caro de transferir por
  HTTP. Se devuelven sólo las combinaciones con movimiento real.
------------------------------------------------------------------------------*/

CREATE OR ALTER VIEW dbo.vw_ResumenMensualPorCompania
AS
SELECT      v.Compania                                             AS Compania,
            p.NombreProducto                                       AS Producto,
            DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)        AS Periodo,
            SUM(CAST(v.Cantidad AS BIGINT))                        AS CantidadVentas,
            CAST(SUM(CAST(v.Cantidad AS DECIMAL(19,4)) * v.Precio)
                 AS DECIMAL(19,2))                                 AS TotalVentas,
            COUNT(*)                                               AS NumeroTransacciones
FROM        dbo.Ventas    AS v
JOIN        dbo.Productos AS p ON p.IdProducto = v.IdProducto
WHERE       v.Fecha IS NOT NULL
GROUP BY    v.Compania, p.NombreProducto, DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1);
GO


/*------------------------------------------------------------------------------
  Versión materializada de la matriz
  ------------------------------------------------------------------------------
  El enunciado admite "queries y/o tablas". La vista siempre devuelve el dato
  fresco, pero recalcula el CROSS JOIN en cada consulta. Para un tablero que se
  refresca seguido (Power BI en modo Import, por ejemplo) conviene materializar.

  Se deja la tabla + un procedimiento que la reconstruye de forma atómica.
------------------------------------------------------------------------------*/

IF OBJECT_ID('dbo.VentasMensual', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.VentasMensual
    (
        IdProducto          INT            NOT NULL,
        Producto            NVARCHAR(100)  NOT NULL,
        Periodo             DATE           NOT NULL,
        CantidadVentas      BIGINT         NOT NULL,
        TotalVentas         DECIMAL(19,2)  NOT NULL,
        NumeroTransacciones INT            NOT NULL,
        FechaCalculo        DATETIME2(0)   NOT NULL CONSTRAINT DF_VentasMensual_FechaCalculo DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_VentasMensual PRIMARY KEY CLUSTERED (IdProducto, Periodo)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_RefrescarVentasMensual
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- ante cualquier error, revierte la transacción completa

    BEGIN TRY
        BEGIN TRANSACTION;

            DELETE FROM dbo.VentasMensual;

            INSERT INTO dbo.VentasMensual
                (IdProducto, Producto, Periodo, CantidadVentas, TotalVentas, NumeroTransacciones)
            SELECT IdProducto, Producto, Periodo, CantidadVentas, TotalVentas, NumeroTransacciones
            FROM   dbo.vw_MatrizVentasMensual;

        COMMIT TRANSACTION;

        SELECT CAST(COUNT(*) AS VARCHAR(20)) + ' filas recalculadas en dbo.VentasMensual'
               AS Resultado
        FROM   dbo.VentasMensual;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;   -- se propaga el error original, sin enmascararlo
    END CATCH
END
GO

EXEC dbo.usp_RefrescarVentasMensual;
GO


/*==============================================================================
  VERIFICACIÓN DEL SCRIPT
  Todo lo de abajo es control de calidad: confirma que lo construido cuadra.
==============================================================================*/

PRINT '';
PRINT '========== RESUMEN DE OBJETOS CREADOS ==========';

SELECT 'dbo.Productos (maestro)'          AS Objeto, COUNT(*) AS Filas FROM dbo.Productos
UNION ALL
SELECT 'dbo.Ventas (origen)',                        COUNT(*)          FROM dbo.Ventas
UNION ALL
SELECT 'dbo.vw_MatrizVentasMensual',                 COUNT(*)          FROM dbo.vw_MatrizVentasMensual
UNION ALL
SELECT 'dbo.VentasMensual (materializada)',          COUNT(*)          FROM dbo.VentasMensual
UNION ALL
SELECT 'dbo.vw_ResumenMensualPorCompania',           COUNT(*)          FROM dbo.vw_ResumenMensualPorCompania;

PRINT '';
PRINT '--- Control 1: la matriz debe tener exactamente Productos x Periodos filas ---';
SELECT (SELECT COUNT(*) FROM dbo.Productos)                                            AS Productos,
       (SELECT COUNT(DISTINCT DATEFROMPARTS(YEAR(Fecha),MONTH(Fecha),1)) FROM dbo.Ventas
        WHERE Fecha IS NOT NULL)                                                       AS Periodos,
       (SELECT COUNT(*) FROM dbo.Productos)
     * (SELECT COUNT(DISTINCT DATEFROMPARTS(YEAR(Fecha),MONTH(Fecha),1)) FROM dbo.Ventas
        WHERE Fecha IS NOT NULL)                                                       AS FilasEsperadas,
       (SELECT COUNT(*) FROM dbo.vw_MatrizVentasMensual)                               AS FilasReales,
       CASE WHEN (SELECT COUNT(*) FROM dbo.vw_MatrizVentasMensual)
               = (SELECT COUNT(*) FROM dbo.Productos)
               * (SELECT COUNT(DISTINCT DATEFROMPARTS(YEAR(Fecha),MONTH(Fecha),1)) FROM dbo.Ventas
                  WHERE Fecha IS NOT NULL)
            THEN 'OK' ELSE 'ERROR' END                                                 AS Veredicto;

PRINT '';
PRINT '--- Control 2: el total de la matriz debe ser igual al total crudo de Ventas ---';
SELECT CAST((SELECT SUM(CAST(Cantidad AS DECIMAL(19,4)) * Precio) FROM dbo.Ventas WHERE Fecha IS NOT NULL)
            AS DECIMAL(19,2))                                            AS TotalDirectoDesdeVentas,
       (SELECT SUM(TotalVentas) FROM dbo.vw_MatrizVentasMensual)         AS TotalDesdeLaMatriz,
       CASE WHEN CAST((SELECT SUM(CAST(Cantidad AS DECIMAL(19,4)) * Precio) FROM dbo.Ventas WHERE Fecha IS NOT NULL)
                      AS DECIMAL(19,2))
               = (SELECT SUM(TotalVentas) FROM dbo.vw_MatrizVentasMensual)
            THEN 'OK' ELSE 'ERROR' END                                   AS Veredicto;

PRINT '';
PRINT '--- Control 3: la regla del periodo aplicada a los ejemplos del enunciado ---';
SELECT      Ejemplo,
            DATEFROMPARTS(YEAR(Ejemplo), MONTH(Ejemplo), 1) AS PeriodoCalculado,
            Esperado,
            CASE WHEN DATEFROMPARTS(YEAR(Ejemplo), MONTH(Ejemplo), 1) = Esperado
                 THEN 'OK' ELSE 'ERROR' END                 AS Veredicto
FROM (VALUES (CAST('2024-01-07' AS DATE), CAST('2024-01-01' AS DATE)),
             (CAST('2024-05-31' AS DATE), CAST('2024-05-01' AS DATE))
     ) AS t(Ejemplo, Esperado);

PRINT '';
PRINT '--- Control 4: los productos sin ventas en un periodo aparecen con 0 (no faltan) ---';
SELECT COUNT(*) AS CeldasEnCero
FROM   dbo.vw_MatrizVentasMensual
WHERE  NumeroTransacciones = 0;

PRINT '';
PRINT '--- Muestra de la matriz: un producto a lo largo de todos los periodos ---';
SELECT TOP 12 Producto, Periodo, CantidadVentas, TotalVentas, NumeroTransacciones
FROM   dbo.vw_MatrizVentasMensual
WHERE  Producto = 'Notebook Lenovo'
ORDER BY Periodo;
GO
