<#
.SYNOPSIS
    Deja el entorno listo: levanta SQL Server en Docker, restaura el backup y
    ejecuta los scripts SQL de la solución.

.DESCRIPTION
    Pensado para poder reproducir la solución en una máquina limpia que sólo
    tenga Docker Desktop y el SDK de .NET 9.

    El script es idempotente: si el contenedor ya existe lo reutiliza, y los
    scripts SQL se pueden correr las veces que sea sin duplicar datos.

.PARAMETER RutaBackup
    Ruta al archivo Tecnica_FULL.bak. Por defecto lo busca en la raíz del
    repositorio y en la carpeta de descargas del usuario.

.PARAMETER Password
    Contraseña del usuario sa. Debe coincidir con la cadena de conexión de
    src/PruebaTecnica.Web/appsettings.json.

.EXAMPLE
    .\scripts\setup.ps1
    .\scripts\setup.ps1 -RutaBackup "D:\descargas\Tecnica_FULL.bak"
#>
[CmdletBinding()]
param(
    [string]$RutaBackup,
    [string]$Password  = 'Tecnica#2026!Sql',
    [string]$Contenedor = 'mssql-tecnica',
    [int]$Puerto = 1433
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot

function Escribir($texto, $color = 'White') { Write-Host $texto -ForegroundColor $color }
function Paso($n, $texto) { Write-Host ""; Escribir "[$n] $texto" 'Cyan' }

# --- Ejecuta un comando sqlcmd dentro del contenedor -------------------------
# La imagen de Linux trae sqlcmd en /opt/mssql-tools18. La opción -C confía en
# el certificado autofirmado del contenedor y -No evita exigir cifrado, que no
# hace falta contra localhost.
function Sql($consulta, $baseDatos = 'master') {
    docker exec $Contenedor /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U sa -P $Password -C -No -d $baseDatos -Q $consulta
}

function SqlArchivo($rutaLocal, $baseDatos = 'Tecnica') {
    $nombre = Split-Path -Leaf $rutaLocal
    docker cp $rutaLocal "${Contenedor}:/tmp/$nombre" | Out-Null
    docker exec $Contenedor /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U sa -P $Password -C -No -d $baseDatos `
        -i "/tmp/$nombre" -f 65001 -W -s '|' -w 250
}

Escribir "=== Preparacion del entorno — Prueba Tecnica ===" 'Green'

# ---------------------------------------------------------------------------
Paso 1 "Verificando Docker"
# ---------------------------------------------------------------------------
try {
    $version = docker version --format '{{.Server.Version}}' 2>$null
    if (-not $version) { throw }
    Escribir "    Docker $version en ejecucion." 'Gray'
}
catch {
    Escribir "    ERROR: Docker no responde. Abra Docker Desktop y vuelva a intentar." 'Red'
    exit 1
}

# ---------------------------------------------------------------------------
Paso 2 "Ubicando el backup"
# ---------------------------------------------------------------------------
if (-not $RutaBackup) {
    $candidatos = @(
        (Join-Path $raiz 'Tecnica_FULL.bak'),
        (Join-Path $raiz 'sql\Tecnica_FULL.bak'),
        (Join-Path $HOME 'Downloads\Prueba Tecnica V2\Tecnica_FULL.bak'),
        (Join-Path $HOME 'Downloads\Tecnica_FULL.bak')
    )
    $RutaBackup = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $RutaBackup -or -not (Test-Path $RutaBackup)) {
    Escribir "    ERROR: no se encontro Tecnica_FULL.bak." 'Red'
    Escribir "    Indique la ruta:  .\scripts\setup.ps1 -RutaBackup 'C:\ruta\Tecnica_FULL.bak'" 'Yellow'
    exit 1
}
Escribir "    $RutaBackup" 'Gray'

# ---------------------------------------------------------------------------
Paso 3 "Levantando SQL Server 2022"
# ---------------------------------------------------------------------------
$existente = docker ps -a --filter "name=^/$Contenedor$" --format '{{.Names}}'

if ($existente -eq $Contenedor) {
    Escribir "    El contenedor '$Contenedor' ya existe; se reutiliza." 'Gray'
    $enMarcha = docker ps --filter "name=^/$Contenedor$" --format '{{.Names}}'
    if ($enMarcha -ne $Contenedor) {
        Escribir "    Estaba detenido: iniciando..." 'Gray'
        docker start $Contenedor | Out-Null
    }
}
else {
    Escribir "    Descargando la imagen (la primera vez tarda varios minutos)..." 'Gray'
    docker pull mcr.microsoft.com/mssql/server:2022-latest

    Escribir "    Creando el contenedor..." 'Gray'
    docker run -d --name $Contenedor --restart unless-stopped `
        -e "ACCEPT_EULA=Y" `
        -e "MSSQL_SA_PASSWORD=$Password" `
        -e "MSSQL_PID=Developer" `
        -p "${Puerto}:1433" `
        mcr.microsoft.com/mssql/server:2022-latest | Out-Null
}

# ---------------------------------------------------------------------------
Paso 4 "Esperando que SQL Server acepte conexiones"
# ---------------------------------------------------------------------------
# SQL Server tarda unos segundos en inicializar. Se sondea en vez de dormir un
# tiempo fijo: es mas rapido cuando ya esta listo y mas confiable cuando tarda.
$listo = $false
for ($i = 1; $i -le 40; $i++) {
    Sql "SELECT 1" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $listo = $true; Escribir "    Listo (intento $i)." 'Gray'; break }
    Start-Sleep -Seconds 3
}
if (-not $listo) {
    Escribir "    ERROR: SQL Server no respondio tras 120 segundos." 'Red'
    Escribir "    Revise los logs con:  docker logs $Contenedor" 'Yellow'
    exit 1
}

# ---------------------------------------------------------------------------
Paso 5 "Restaurando la base Tecnica"
# ---------------------------------------------------------------------------
docker exec $Contenedor mkdir -p /var/opt/mssql/backup
docker cp $RutaBackup "${Contenedor}:/var/opt/mssql/backup/Tecnica_FULL.bak" | Out-Null

# RESTORE necesita acceso EXCLUSIVO a la base. Si la aplicacion .NET (o SSMS, o
# Power BI) tiene una conexion abierta, el RESTORE falla con
# "Exclusive access could not be obtained because the database is in use".
# SINGLE_USER WITH ROLLBACK IMMEDIATE corta esas conexiones antes de empezar.
$existeBase = Sql "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = 'Tecnica'" 2>$null
if ($LASTEXITCODE -eq 0 -and ($existeBase -join '') -match '\b1\b') {
    Escribir "    La base ya existe: cerrando conexiones activas..." 'Gray'
    Sql "ALTER DATABASE [Tecnica] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;" 2>&1 | Out-Null
}

# El backup viene de un SQL Server de Windows: sus rutas internas son del tipo
# C:\Program Files\... y hay que redirigirlas a las rutas de Linux con MOVE.
Sql @"
RESTORE DATABASE [Tecnica]
FROM DISK = '/var/opt/mssql/backup/Tecnica_FULL.bak'
WITH MOVE 'Tecnica'     TO '/var/opt/mssql/data/Tecnica.mdf',
     MOVE 'Tecnica_log' TO '/var/opt/mssql/data/Tecnica_log.ldf',
     REPLACE, RECOVERY;
"@

if ($LASTEXITCODE -ne 0) {
    Escribir "    ERROR al restaurar el backup." 'Red'
    Escribir "    Si dice que la base esta en uso, cierre la aplicacion .NET, SSMS y Power BI." 'Yellow'
    exit 1
}

# RESTORE deja la base en el modo que tenia antes; se devuelve a multiusuario
# explicitamente para que la aplicacion pueda conectarse.
Sql "ALTER DATABASE [Tecnica] SET MULTI_USER;" 2>&1 | Out-Null

# ---------------------------------------------------------------------------
Paso 6 "Ejecutando los scripts de la solucion"
# ---------------------------------------------------------------------------
foreach ($archivo in @('01_esquema_y_matriz.sql', '02_analisis_datos.sql', '03_vista_powerbi.sql')) {
    $ruta = Join-Path $raiz "sql\$archivo"
    if (-not (Test-Path $ruta)) {
        Escribir "    ADVERTENCIA: falta $archivo" 'Yellow'
        continue
    }
    Escribir "    -> $archivo" 'Gray'
    SqlArchivo $ruta | Out-Null
    if ($LASTEXITCODE -ne 0) { Escribir "       (termino con errores; revise ejecutandolo a mano)" 'Yellow' }
}

# ---------------------------------------------------------------------------
Paso 7 "Verificacion final"
# ---------------------------------------------------------------------------
docker exec $Contenedor /opt/mssql-tools18/bin/sqlcmd `
    -S localhost -U sa -P $Password -C -No -d Tecnica -W -s '|' -Q @"
SET NOCOUNT ON;
SELECT 'Ventas' AS Objeto, COUNT(*) AS Filas FROM dbo.Ventas
UNION ALL SELECT 'Productos',                 COUNT(*) FROM dbo.Productos
UNION ALL SELECT 'Matriz mensual',            COUNT(*) FROM dbo.vw_MatrizVentasMensual
UNION ALL SELECT 'Resumen por compania',      COUNT(*) FROM dbo.vw_ResumenMensualPorCompania
UNION ALL SELECT 'Vista Power BI',            COUNT(*) FROM dbo.vw_VentasPowerBI;
"@

Write-Host ""
Escribir "=== Entorno listo ===" 'Green'
Escribir "  SQL Server:  localhost,$Puerto   (usuario sa)" 'Gray'
Escribir "  Base:        Tecnica" 'Gray'
Write-Host ""
Escribir "Siguiente paso — levantar la aplicacion:" 'Cyan'
Escribir "  dotnet run --project src\PruebaTecnica.Web --urls http://localhost:5080" 'White'
Write-Host ""
Escribir "  Aplicacion:  http://localhost:5080" 'Gray'
Escribir "  Swagger:     http://localhost:5080/swagger" 'Gray'
