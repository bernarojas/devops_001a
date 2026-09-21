/*==============================================================================
  EXPERIENCIA 2 — DevOps (ISY2201)
  Archivo 0 de 4: creación de la base y carga de datos sintéticos

  POR QUÉ EXISTE ESTE ARCHIVO
  ------------------------------------------------------------------------------
  La prueba técnica original partía de un respaldo (Tecnica_FULL.bak) con datos
  comerciales. Ese respaldo pesa 6,8 MB, no se versiona y, sobre todo, contiene
  información de terceros que no corresponde publicar en un repositorio ni
  cargar en un servidor con dirección pública.

  Para que el ambiente se reconstruya entero desde el repositorio, este script
  crea la tabla de origen y la puebla con datos SINTÉTICOS generados de forma
  determinista. "Determinista" acá es la propiedad importante: no se usa RAND(),
  así que cualquiera que lo ejecute obtiene exactamente las mismas 2.008 filas y
  los mismos totales. Las cifras del informe son, por lo tanto, reproducibles.

  Se incluyen a propósito ocho filas anómalas. No son un descuido: el archivo
  02_analisis_datos.sql existe justamente para detectarlas, y sin ellas ese
  análisis no tendría nada que reportar.

  Este script es IDEMPOTENTE: si la tabla ya tiene filas, no vuelve a cargar.

  Orden de ejecución:
      00_base_y_datos_sinteticos.sql   <-- este archivo
      01_esquema_y_matriz.sql
      02_analisis_datos.sql
      03_vista_powerbi.sql
==============================================================================*/

SET NOCOUNT ON;
GO

/*------------------------------------------------------------------------------
  0.1  La base de datos
------------------------------------------------------------------------------*/
IF DB_ID('Tecnica') IS NULL
BEGIN
    PRINT 'Creando la base de datos Tecnica...';
    CREATE DATABASE [Tecnica];
END
ELSE
BEGIN
    PRINT 'La base de datos Tecnica ya existe.';
END
GO

USE [Tecnica];
GO

/*------------------------------------------------------------------------------
  0.2  Tabla de origen
  ------------------------------------------------------------------------------
  Reproduce la estructura de la tabla del respaldo original, incluida su
  nulabilidad. Las columnas de negocio admiten NULL porque los datos reales
  venían así, y porque el análisis del archivo 02 necesita poder encontrarse
  con filas incompletas.

  La columna IdProducto NO se crea acá: la agrega 01_esquema_y_matriz.sql junto
  con el maestro de productos y su clave foránea. Mantener esa separación deja
  este archivo como "el origen tal cual llega" y el 01 como "lo que el equipo
  construyó encima".
------------------------------------------------------------------------------*/
IF OBJECT_ID('dbo.Ventas', 'U') IS NULL
BEGIN
    PRINT 'Creando la tabla dbo.Ventas...';
    CREATE TABLE dbo.Ventas
    (
        ID        INT            IDENTITY(1,1) NOT NULL,
        Compania  NVARCHAR(100)  NULL,
        Producto  NVARCHAR(100)  NULL,
        Fecha     DATETIME       NULL,
        Cantidad  INT            NULL,
        Precio    DECIMAL(18,2)  NULL,

        CONSTRAINT PK_Ventas PRIMARY KEY CLUSTERED (ID)
    );
END
GO

/*------------------------------------------------------------------------------
  0.3  Carga de datos
------------------------------------------------------------------------------*/
IF EXISTS (SELECT 1 FROM dbo.Ventas)
BEGIN
    PRINT 'La tabla dbo.Ventas ya tiene datos: no se vuelve a cargar.';
END
ELSE
BEGIN
    PRINT 'Cargando 2.000 ventas regulares...';

    /* El generador de números produce 0..1999 a partir del catálogo del sistema.
       Es la forma estándar de generar una serie en SQL Server sin una tabla de
       apoyo: el CROSS JOIN garantiza filas de sobra para el TOP. */
    WITH Numeros AS
    (
        SELECT TOP (2000)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM   sys.all_objects AS a
        CROSS JOIN sys.all_objects AS b
    ),
    Catalogo AS
    (
        SELECT * FROM (VALUES
            (0, N'Notebook Pro 14',        899990.00),
            (1, N'Monitor UltraWide 34',   449990.00),
            (2, N'Teclado Mecánico RGB',    79990.00),
            (3, N'Mouse Ergonómico',        39990.00),
            (4, N'Docking Station USB-C',  159990.00),
            (5, N'Audífonos con Cancelación', 129990.00),
            (6, N'Cámara Web 4K',           99990.00),
            (7, N'Disco SSD 2 TB',         189990.00)
        ) AS t (Indice, Nombre, Precio)
    ),
    Companias AS
    (
        SELECT * FROM (VALUES
            (0, N'Comercial Andes'),
            (1, N'Distribuidora Pacífico'),
            (2, N'Importadora Sur'),
            (3, N'Tecnología Austral'),
            (4, N'Suministros Cordillera'),
            (5, N'Redes del Maipo')
        ) AS t (Indice, Nombre)
    )
    INSERT INTO dbo.Ventas (Compania, Producto, Fecha, Cantidad, Precio)
    SELECT  c.Nombre,
            p.Nombre,
            /* 36 meses desde enero de 2024, con el día derivado del mismo
               número. Parte del rango cae en el futuro respecto de la fecha de
               entrega: son ventas proyectadas, y existen a propósito para
               ejercitar la ventana de fechas que valida VentaInput. */
            DATEADD(DAY, num.n % 27,
                DATEADD(MONTH, num.n % 36, CAST('2024-01-01' AS DATE))),
            (num.n % 20) + 1,
            p.Precio
    FROM        Numeros   AS num
    INNER JOIN  Catalogo  AS p ON p.Indice = num.n % 8
    INNER JOIN  Companias AS c ON c.Indice = num.n % 6;

    PRINT 'Cargando 8 filas anómalas deliberadas...';

    /* Cada una reproduce una de las anomalías que el análisis del archivo 02
       cuantifica. Se insertan por separado y comentadas para que quede claro
       que son parte del diseño del conjunto de datos y no un defecto. */
    INSERT INTO dbo.Ventas (Compania, Producto, Fecha, Cantidad, Precio) VALUES
        -- Cantidades negativas: devoluciones mal registradas.
        (N'Comercial Andes',        N'Notebook Pro 14',      '2024-03-11',  -3,  899990.00),
        (N'Distribuidora Pacífico', N'Mouse Ergonómico',     '2024-05-22',  -1,   39990.00),
        (N'Importadora Sur',        N'Cámara Web 4K',        '2025-02-14',  -7,   99990.00),
        (N'Redes del Maipo',        N'Disco SSD 2 TB',       '2025-09-03', -12,  189990.00),

        -- Precio en cero: carga incompleta desde el sistema de origen.
        (N'Tecnología Austral',     N'Monitor UltraWide 34', '2024-07-19',   4,       0.00),
        (N'Suministros Cordillera', N'Teclado Mecánico RGB', '2025-04-08',   9,       0.00),

        -- Fecha ausente: el registro llegó sin fecha de emisión.
        (N'Comercial Andes',        N'Docking Station USB-C', NULL,          2,  159990.00),
        (N'Importadora Sur',        N'Audífonos con Cancelación', NULL,      6,  129990.00);

    PRINT 'Carga completada.';
END
GO

/*------------------------------------------------------------------------------
  0.4  Resumen de lo cargado
  ------------------------------------------------------------------------------
  Queda en la salida del contenedor de inicialización, de modo que el registro
  del despliegue muestre con cuántas filas arrancó el ambiente.
------------------------------------------------------------------------------*/
SELECT  COUNT(*)                                              AS TotalVentas,
        COUNT(DISTINCT Producto)                              AS ProductosDistintos,
        SUM(CASE WHEN Cantidad < 0 THEN 1 ELSE 0 END)         AS ConCantidadNegativa,
        SUM(CASE WHEN Precio = 0 THEN 1 ELSE 0 END)           AS ConPrecioEnCero,
        SUM(CASE WHEN Fecha IS NULL THEN 1 ELSE 0 END)        AS SinFecha
FROM    dbo.Ventas;
GO
