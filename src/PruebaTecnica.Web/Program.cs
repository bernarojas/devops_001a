using System.Globalization;
using System.Reflection;
using Microsoft.AspNetCore.Localization;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using PruebaTecnica.Web.Data;
using PruebaTecnica.Web.Middleware;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Base de datos
// ---------------------------------------------------------------------------
var cadenaConexion = builder.Configuration.GetConnectionString("Tecnica")
    ?? throw new InvalidOperationException(
        "Falta la cadena de conexión 'Tecnica' en appsettings.json.");

builder.Services.AddDbContext<AppDbContext>(opciones =>
{
    opciones.UseSqlServer(cadenaConexion, sql =>
    {
        // Reintentos ante fallas transitorias de red o de arranque del contenedor.
        sql.EnableRetryOnFailure(maxRetryCount: 3,
                                 maxRetryDelay: TimeSpan.FromSeconds(5),
                                 errorNumbersToAdd: null);
        sql.CommandTimeout(60);
    });

    if (builder.Environment.IsDevelopment())
    {
        // Muestra los valores de los parámetros en el log de SQL. Sólo en
        // desarrollo: en producción eso sería una fuga de datos.
        opciones.EnableSensitiveDataLogging();
        opciones.EnableDetailedErrors();
    }
});

// ---------------------------------------------------------------------------
// Servicios de aplicación
// ---------------------------------------------------------------------------
builder.Services.AddScoped<IVentaService, VentaService>();
builder.Services.AddScoped<IProductoService, ProductoService>();
builder.Services.AddScoped<IResumenService, ResumenService>();

builder.Services.AddControllersWithViews(opciones =>
{
    // Se inserta al principio para que gane sobre el enlazador de decimales
    // por defecto. Sin esto, un precio "12345.67" enviado por un formulario se
    // guarda como 1234567 en un servidor con cultura es-CL. Ver la clase para
    // la explicación completa.
    opciones.ModelBinderProviders.Insert(0, new ProveedorEnlaceDecimalInvariante());
});

builder.Services.AddEndpointsApiExplorer();

// ---------------------------------------------------------------------------
// Cultura
// ---------------------------------------------------------------------------
// Se fija explícitamente en lugar de heredar la del sistema operativo: así los
// montos y las fechas se ven igual en cualquier máquina donde se ejecute, y no
// dependen de la configuración regional de quien evalúe.
//
// Los datos no declaran moneda; se asume peso chileno por las magnitudes
// (ver la sección de supuestos del README). El símbolo "$" de es-CL es a la vez
// el de varias monedas, así que comunica "esto es dinero" sin afirmar de más.
//
// Esto SÓLO afecta a la presentación. La lectura de los decimales que llegan
// por formulario está cubierta por ProveedorEnlaceDecimalInvariante.
var culturaAplicacion = new CultureInfo("es-CL");

builder.Services.Configure<RequestLocalizationOptions>(opciones =>
{
    opciones.DefaultRequestCulture = new RequestCulture(culturaAplicacion);
    opciones.SupportedCultures = [culturaAplicacion];
    opciones.SupportedUICultures = [culturaAplicacion];
});

// ---------------------------------------------------------------------------
// Swagger
// ---------------------------------------------------------------------------
builder.Services.AddSwaggerGen(opciones =>
{
    opciones.SwaggerDoc("v1", new OpenApiInfo
    {
        Version = "v1",
        Title = "API de Ventas — Prueba Técnica",
        Description =
            "Expone la información de ventas y su consolidado mensual por compañía, " +
            "producto y período.\n\n" +
            "**Paginación:** los endpoints de consulta devuelven un array JSON plano. " +
            "El total de registros y la página actual viajan en las cabeceras " +
            "`X-Total-Registros`, `X-Pagina`, `X-Total-Paginas` y `X-Tamano-Pagina`.\n\n" +
            "**Períodos:** siempre el primer día del mes (formato `yyyy-MM-dd`). " +
            "Si se envía otro día del mes, se normaliza automáticamente.\n\n" +
            "**Seguridad:** esta versión es pública a propósito, según el enunciado. " +
            "Ver la sección correspondiente del README para el esquema que se usaría " +
            "en un escenario real."
    });

    // Incorpora los comentarios /// del código a la documentación.
    var archivoXml = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var rutaXml = Path.Combine(AppContext.BaseDirectory, archivoXml);
    if (File.Exists(rutaXml))
    {
        opciones.IncludeXmlComments(rutaXml);
    }
});

var app = builder.Build();

// ---------------------------------------------------------------------------
// Pipeline HTTP
// ---------------------------------------------------------------------------

// Va primero para que atrape también lo que fallen los middlewares siguientes.
app.UsarManejadorDeErrores();

app.UseRequestLocalization();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseRouting();
app.UseAuthorization();

// Swagger queda disponible siempre para que el evaluador pueda abrirlo
// sin tener que cambiar el entorno de ejecución.
app.UseSwagger();
app.UseSwaggerUI(opciones =>
{
    opciones.SwaggerEndpoint("/swagger/v1/swagger.json", "API de Ventas v1");
    opciones.DocumentTitle = "API de Ventas — Prueba Técnica";
    opciones.RoutePrefix = "swagger";
});

app.MapStaticAssets();

app.MapControllerRoute(
        name: "default",
        pattern: "{controller=Home}/{action=Index}/{id?}")
   .WithStaticAssets();

// ---------------------------------------------------------------------------
// Chequeo de conectividad al arrancar
// ---------------------------------------------------------------------------
// Un fallo de conexión reportado acá, con un mensaje claro, ahorra mucho tiempo
// comparado con descubrirlo recién al abrir la primera pantalla.
using (var alcance = app.Services.CreateScope())
{
    var log = alcance.ServiceProvider.GetRequiredService<ILogger<Program>>();
    var db = alcance.ServiceProvider.GetRequiredService<AppDbContext>();

    try
    {
        if (await db.Database.CanConnectAsync())
        {
            var ventas = await db.Ventas.CountAsync();
            var productos = await db.Productos.CountAsync();
            log.LogInformation(
                "Conexión a SQL Server correcta. {Ventas} ventas y {Productos} productos en la base.",
                ventas, productos);
        }
        else
        {
            log.LogError("No se pudo conectar a SQL Server. Revise la cadena de conexión 'Tecnica'.");
        }
    }
    catch (Exception ex)
    {
        log.LogError(ex,
            "Fallo al verificar la base de datos. ¿Está corriendo el contenedor mssql-tecnica " +
            "y se ejecutaron los scripts de la carpeta sql?");
    }
}

app.Run();
