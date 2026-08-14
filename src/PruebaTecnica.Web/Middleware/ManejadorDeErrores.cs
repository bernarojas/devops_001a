using System.Text.Json;
using Microsoft.Data.SqlClient;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Web.Middleware;

/// <summary>
/// Red de seguridad para las excepciones no controladas.
///
/// Distingue el destino de la respuesta: si la petición era a /api/* devuelve
/// JSON con el mismo formato de error que el resto de la API; si venía del
/// navegador, delega en la página de error de MVC.
///
/// Nunca expone el detalle interno en producción: el stack trace y el mensaje
/// original van al log, no al cliente. Filtrar una excepción de base de datos
/// hacia afuera es regalar información sobre el esquema.
/// </summary>
public class ManejadorDeErrores
{
    private readonly RequestDelegate _siguiente;
    private readonly ILogger<ManejadorDeErrores> _log;
    private readonly IHostEnvironment _entorno;

    public ManejadorDeErrores(RequestDelegate siguiente, ILogger<ManejadorDeErrores> log,
                              IHostEnvironment entorno)
    {
        _siguiente = siguiente;
        _log = log;
        _entorno = entorno;
    }

    public async Task InvokeAsync(HttpContext contexto)
    {
        try
        {
            await _siguiente(contexto);
        }
        catch (OperationCanceledException) when (contexto.RequestAborted.IsCancellationRequested)
        {
            // El cliente cortó la conexión. No es un error del servidor: se
            // registra como información y no se intenta escribir una respuesta.
            _log.LogInformation("Petición cancelada por el cliente: {Ruta}", contexto.Request.Path);
        }
        catch (Exception ex)
        {
            _log.LogError(ex, "Error no controlado en {Metodo} {Ruta}",
                          contexto.Request.Method, contexto.Request.Path);

            if (contexto.Response.HasStarted)
            {
                // Ya se empezó a enviar la respuesta: cambiar el código de estado
                // ahora rompería el protocolo. Sólo queda dejarlo registrado.
                _log.LogWarning("La respuesta ya había comenzado; no se pudo enviar el error formateado.");
                throw;
            }

            var (estado, mensaje) = Clasificar(ex);

            if (EsPeticionDeApi(contexto))
            {
                await EscribirJsonAsync(contexto, estado, mensaje, ex);
            }
            else
            {
                contexto.Response.StatusCode = estado;
                contexto.Response.Redirect($"/Home/Error?codigo={estado}");
            }
        }
    }

    /// <summary>
    /// Traduce la excepción al código HTTP que mejor la describe. Lo que no se
    /// reconoce es 500: inventar un 400 para un error del servidor le miente al
    /// cliente sobre de quién es la culpa.
    /// </summary>
    private static (int Estado, string Mensaje) Clasificar(Exception ex) => ex switch
    {
        SqlException { Number: -2 } =>
            (StatusCodes.Status504GatewayTimeout,
             "La consulta a la base de datos tardó demasiado. Intente acotar los filtros."),

        SqlException =>
            (StatusCodes.Status503ServiceUnavailable,
             "No se pudo comunicar con la base de datos. Verifique que SQL Server esté disponible."),

        ArgumentException or FormatException =>
            (StatusCodes.Status400BadRequest,
             "Alguno de los datos enviados tiene un formato inválido."),

        _ => (StatusCodes.Status500InternalServerError,
              "Ocurrió un error inesperado procesando la solicitud.")
    };

    private static bool EsPeticionDeApi(HttpContext contexto) =>
        contexto.Request.Path.StartsWithSegments("/api", StringComparison.OrdinalIgnoreCase);

    private async Task EscribirJsonAsync(HttpContext contexto, int estado, string mensaje, Exception ex)
    {
        contexto.Response.Clear();
        contexto.Response.StatusCode = estado;
        contexto.Response.ContentType = "application/json; charset=utf-8";

        // El detalle técnico sólo se revela en desarrollo.
        var detalle = _entorno.IsDevelopment() ? ex.Message : null;
        var error = new ErrorDto(estado, mensaje, detalle);

        await contexto.Response.WriteAsync(JsonSerializer.Serialize(error, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        }));
    }
}

public static class ManejadorDeErroresExtensions
{
    public static IApplicationBuilder UsarManejadorDeErrores(this IApplicationBuilder app) =>
        app.UseMiddleware<ManejadorDeErrores>();
}
