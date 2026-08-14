/*==============================================================================
  PRUEBA TÉCNICA — SQL SERVER
  Archivo 3 de 3: vista de apoyo para Power BI
  Requiere haber ejecutado antes 01_esquema_y_matriz.sql

  ¿Por qué una vista aparte y no conectar Power BI directo a dbo.Ventas?

  Porque hacer el trabajo pesado en SQL y no en Power BI tiene tres ventajas
  concretas:
    1. El período ya viene calculado igual que en el punto 1.2. Si se calculara
       de nuevo en DAX, existirían dos definiciones del mismo concepto y
       tarde o temprano dejarían de coincidir.
    2. Las columnas de calendario (año, trimestre, nombre del mes) ya vienen
       listas y con un orden numérico correcto, lo que evita el clásico
       problema de los meses ordenados alfabéticamente en los gráficos.
    3. El nombre del producto viene del maestro vía FK, no del texto libre,
       así el reporte no se rompe si alguien renombra un producto.

  Se conservan los nombres de columna Cantidad y Precio para que la medida DAX
  del enunciado funcione tal cual está escrita:
      Total Ventas = SUMX(Ventas, Ventas[Cantidad] * Ventas[Precio])
==============================================================================*/

USE [Tecnica];
GO

CREATE OR ALTER VIEW dbo.vw_VentasPowerBI
AS
SELECT      v.ID                                                    AS IdVenta,
            v.Compania                                              AS Compania,
            ISNULL(p.NombreProducto, v.Producto)                    AS Producto,
            v.Fecha                                                 AS Fecha,

            -- Período: primer día del mes, misma regla que el punto 1.2.
            DATEFROMPARTS(YEAR(v.Fecha), MONTH(v.Fecha), 1)         AS Periodo,

            YEAR(v.Fecha)                                           AS Anio,
            MONTH(v.Fecha)                                          AS NumeroMes,

            -- Etiqueta legible para los ejes. 'AnioMes' se ordena bien de forma
            -- natural por ser texto de ancho fijo (2025-01 < 2025-02 < ...),
            -- así que sirve de eje sin configurar nada extra en Power BI.
            CONVERT(CHAR(7), v.Fecha, 126)                          AS AnioMes,

            -- Nombre del mes en español, escrito explícitamente en lugar de con
            -- DATENAME(MONTH, ...). DATENAME devuelve el nombre en el idioma de
            -- la sesión: en el contenedor de SQL Server, que arranca en inglés,
            -- devolvía "December". Con un CASE el resultado no depende de la
            -- configuración regional de quien ejecute la consulta.
            CASE MONTH(v.Fecha)
                 WHEN  1 THEN 'Enero'      WHEN  2 THEN 'Febrero'
                 WHEN  3 THEN 'Marzo'      WHEN  4 THEN 'Abril'
                 WHEN  5 THEN 'Mayo'       WHEN  6 THEN 'Junio'
                 WHEN  7 THEN 'Julio'      WHEN  8 THEN 'Agosto'
                 WHEN  9 THEN 'Septiembre' WHEN 10 THEN 'Octubre'
                 WHEN 11 THEN 'Noviembre'  WHEN 12 THEN 'Diciembre'
            END                                                     AS NombreMes,

            'T' + CAST(DATEPART(QUARTER, v.Fecha) AS VARCHAR(1))    AS Trimestre,

            v.Cantidad                                              AS Cantidad,
            v.Precio                                                AS Precio,

            -- Total precalculado. La medida DAX del enunciado usa SUMX sobre
            -- Cantidad * Precio; esta columna permite contrastar los dos
            -- caminos y confirmar que dan el mismo número.
            CAST(CAST(v.Cantidad AS DECIMAL(19,4)) * v.Precio AS DECIMAL(19,2)) AS TotalLinea,

            -- Marca de calidad, para poder aislar las filas problemáticas
            -- directamente desde un filtro del reporte.
            CASE WHEN v.Cantidad IS NULL OR v.Cantidad <= 0
                   OR v.Precio   IS NULL OR v.Precio   <= 0
                   OR v.Fecha    IS NULL
                 THEN 1 ELSE 0 END                                  AS TieneAnomalia

FROM        dbo.Ventas    AS v
LEFT JOIN   dbo.Productos AS p ON p.IdProducto = v.IdProducto
WHERE       v.Fecha IS NOT NULL;
GO


/*------------------------------------------------------------------------------
  Verificación: el total de esta vista debe coincidir con el de la matriz del
  punto 1.2 y con el de la tabla origen. Los tres caminos, un solo número.
------------------------------------------------------------------------------*/

PRINT '';
PRINT '--- Los tres totales deben ser identicos ---';

SELECT  CAST((SELECT SUM(CAST(Cantidad AS DECIMAL(19,4)) * Precio)
              FROM dbo.Ventas WHERE Fecha IS NOT NULL) AS DECIMAL(19,2)) AS DesdeVentas,
        (SELECT SUM(TotalVentas) FROM dbo.vw_MatrizVentasMensual)        AS DesdeLaMatriz,
        (SELECT SUM(TotalLinea)  FROM dbo.vw_VentasPowerBI)              AS DesdeVistaPowerBI,
        CASE WHEN CAST((SELECT SUM(CAST(Cantidad AS DECIMAL(19,4)) * Precio)
                        FROM dbo.Ventas WHERE Fecha IS NOT NULL) AS DECIMAL(19,2))
                = (SELECT SUM(TotalVentas) FROM dbo.vw_MatrizVentasMensual)
              AND (SELECT SUM(TotalVentas) FROM dbo.vw_MatrizVentasMensual)
                = (SELECT SUM(TotalLinea)  FROM dbo.vw_VentasPowerBI)
             THEN 'OK' ELSE 'ERROR' END                                  AS Veredicto;

PRINT '';
PRINT '--- Muestra de la vista ---';
SELECT TOP 5 IdVenta, Compania, Producto, Fecha, Periodo, AnioMes, NombreMes,
             Trimestre, Cantidad, Precio, TotalLinea, TieneAnomalia
FROM   dbo.vw_VentasPowerBI
ORDER BY Fecha DESC;
GO
