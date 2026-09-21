using System.Globalization;
using System.Reflection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Localization;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using PruebaTecnica.Web.Data;
using PruebaTecnica.Web.Middleware;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Ejecución detrás de un proxy inverso
// ---------------------------------------------------------------------------
// En el despliegue contenerizado la aplicación no recibe tráfico de Internet
// directamente: lo recibe nginx, que reenvía en HTTP plano por la red interna
// de Docker. Dos consecuencias, y las dos hay que declararlas explícitamente:
//
//   1. Sin X-Forwarded-*, la aplicación vería como cliente la dirección del
//      proxy y creería que todo llega por HTTP. Los registros perderían la IP
//      real de quien consulta.
//   2. La redirección a HTTPS debe quedar en manos del proxy. Si la aplicación
//      la aplicara, devolvería un 307 hacia https://web:8080, una dirección que
//      sólo existe dentro de la red de Docker y que nadie puede alcanzar.
//
// Se activa con una variable de entorno en lugar de por omisión porque confiar
// en cabeceras que puede falsificar el cliente sólo es correcto cuando se sabe
// que hay un proxy delante.
var detrasDeProxy = builder.Configuration.GetValue("DetrasDeProxy", false);

if (detrasDeProxy)
{
    builder.Services.Configure<ForwardedHeadersOptions>(opciones =>
    {
        opciones.ForwardedHeaders =
            ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;

        // Las listas vienen pobladas con localhost por omisión, y el proxy no
        // es localhost sino otro contenedor. Se vacían porque el único origen
        // posible es la red de borde, que no está expuesta a Internet.
        opciones.KnownNetworks.Clear();
        opciones.KnownProxies.Clear();
    });
}

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

// Las cabeceras reenviadas se leen antes que nada: el resto del pipeline debe
// ver ya la dirección y el esquema reales del cliente, no los del proxy.
if (detrasDeProxy)
{
    app.UseForwardedHeaders();
}

// Va primero para que atrape también lo que fallen los middlewares siguientes.
app.UsarManejadorDeErrores();

app.UseRequestLocalization();

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

if (!detrasDeProxy)
{
    app.UseHttpsRedirection();
}

app.UseRouting();
app.UseAuthorization();

// ---------------------------------------------------------------------------
// Puntos de comprobación de estado
// ---------------------------------------------------------------------------
// Son dos y responden preguntas distintas. Confundirlas es un error caro:
//
//   /salud  (liveness)  — ¿el proceso está vivo y atendiendo? No toca la base.
//                         Si consultara la base, una caída del motor haría que
//                         Docker reiniciara la aplicación en bucle, cuando la
//                         aplicación no tiene ningún problema.
//
//   /listo  (readiness) — ¿puede además atender una petición real? Sí consulta
//                         la base, porque sin ella no hay respuesta útil que dar.
//
// Se declaran antes de las rutas MVC para que ninguna convención de ruteo las
// capture, y quedan fuera de Swagger porque no son parte de la API del negocio.
app.MapGet("/salud", () => Results.Ok(new { estado = "vivo" }))
   .ExcludeFromDescription();

app.MapGet("/listo", async (AppDbContext db, CancellationToken ct) =>
{
    try
    {
        // CanConnectAsync abre y cierra una conexión: es la comprobación más
        // barata que realmente prueba el camino completo hasta el motor.
        return await db.Database.CanConnectAsync(ct)
            ? Results.Ok(new { estado = "listo" })
            : Results.Json(new { estado = "sin-base-de-datos" }, statusCode: 503);
    }
    catch (Exception)
    {
        // El detalle ya queda en el registro del contenedor; hacia afuera no se
        // filtra la causa, que podría incluir el nombre del servidor o el usuario.
        return Results.Json(new { estado = "sin-base-de-datos" }, statusCode: 503);
    }
}).ExcludeFromDescription();

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
