using Microsoft.AspNetCore.Mvc;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

namespace PruebaTecnica.Web.Controllers.Api;

/// <summary>
/// API de consulta externa de ventas (punto 2.1 del enunciado).
///
/// FORMA DE LA RESPUESTA
/// Los endpoints de consulta devuelven un array JSON plano, tal cual el ejemplo
/// del enunciado. La paginación existe igual, pero viaja en cabeceras HTTP
/// (X-Total-Registros, X-Pagina, X-Total-Paginas) en lugar de envolver el array
/// en un objeto. Así el consumidor que sólo quiere los datos los lee directo, y
/// el que necesita paginar tiene la información disponible sin que el contrato
/// cambie de forma.
/// </summary>
[ApiController]
[Route("api/ventas")]
[Produces("application/json")]
[ProducesResponseType(typeof(ErrorDto), StatusCodes.Status500InternalServerError)]
public class VentasApiController : ControllerBase
{
    private readonly IVentaService _ventas;
    private readonly IResumenService _resumen;

    public VentasApiController(IVentaService ventas, IResumenService resumen)
    {
        _ventas = ventas;
        _resumen = resumen;
    }

    /// <summary>Lista las ventas registradas, con filtros y paginación opcionales.</summary>
    /// <param name="compania">Filtro parcial por nombre de compañía.</param>
    /// <param name="producto">Filtro parcial por nombre de producto.</param>
    /// <param name="desde">Fecha mínima de venta (inclusive), formato yyyy-MM-dd.</param>
    /// <param name="hasta">Fecha máxima de venta (inclusive), formato yyyy-MM-dd.</param>
    /// <param name="pagina">Número de página, comienza en 1.</param>
    /// <param name="tamanoPagina">Registros por página. Máximo 200.</param>
    /// <response code="200">Listado de ventas. El total va en la cabecera X-Total-Registros.</response>
    /// <response code="400">Alguno de los parámetros es inválido.</response>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<VentaDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorDto), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IEnumerable<VentaDto>>> ListarVentas(
        [FromQuery] string? compania,
        [FromQuery] string? producto,
        [FromQuery] DateTime? desde,
        [FromQuery] DateTime? hasta,
        [FromQuery] int pagina = 1,
        [FromQuery] int tamanoPagina = 100,
        CancellationToken ct = default)
    {
        if (desde.HasValue && hasta.HasValue && desde > hasta)
        {
            return BadRequest(new ErrorDto(
                StatusCodes.Status400BadRequest,
                "El rango de fechas es inválido.",
                "'desde' no puede ser posterior a 'hasta'."));
        }

        var filtro = new FiltroVentas
        {
            Compania = compania,
            Producto = producto,
            Desde = desde,
            Hasta = hasta,
            Pagina = pagina,
            TamanoPagina = tamanoPagina
        };

        var resultado = await _ventas.ListarAsync(filtro, ct);
        AgregarCabecerasDePaginacion(resultado.TotalRegistros, resultado.PaginaActual,
                                     resultado.TotalPaginas, resultado.TamanoPagina);

        var datos = resultado.Items.Select(v => new VentaDto(
            v.Id,
            v.Compania,
            v.NombreProducto,
            v.Fecha.HasValue ? DateOnly.FromDateTime(v.Fecha.Value) : null,
            v.Cantidad,
            v.Precio,
            v.Total));

        return Ok(datos);
    }

    /// <summary>Obtiene una venta puntual por su Id.</summary>
    /// <response code="200">La venta solicitada.</response>
    /// <response code="404">No existe una venta con ese Id.</response>
    [HttpGet("{id:int}")]
    [ProducesResponseType(typeof(VentaDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorDto), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<VentaDto>> ObtenerVenta(int id, CancellationToken ct)
    {
        var venta = await _ventas.ObtenerAsync(id, ct);
        if (venta is null)
        {
            return NotFound(new ErrorDto(StatusCodes.Status404NotFound,
                                         $"No existe la venta con Id {id}."));
        }

        return Ok(new VentaDto(
            venta.Id, venta.Compania, venta.NombreProducto,
            venta.Fecha.HasValue ? DateOnly.FromDateTime(venta.Fecha.Value) : null,
            venta.Cantidad, venta.Precio, venta.Total));
    }

    /// <summary>
    /// Información consolidada de ventas mensuales por compañía, producto y período.
    /// </summary>
    /// <remarks>
    /// El período es siempre el primer día del mes. Si se envía cualquier otro día
    /// (por ejemplo 2024-01-15), se normaliza automáticamente a 2024-01-01.
    ///
    /// Ejemplos:
    ///
    ///     GET /api/ventas/resumen-mensual
    ///     GET /api/ventas/resumen-mensual?compania=Northwind
    ///     GET /api/ventas/resumen-mensual?compania=Northwind&amp;periodo=2025-04-01
    ///     GET /api/ventas/resumen-mensual?producto=Notebook%20Lenovo
    /// </remarks>
    /// <param name="compania">Compañía exacta. Opcional.</param>
    /// <param name="producto">Producto exacto. Opcional.</param>
    /// <param name="periodo">Período en formato yyyy-MM-dd. Opcional.</param>
    /// <param name="pagina">Número de página, comienza en 1.</param>
    /// <param name="tamanoPagina">Registros por página. Máximo 1000.</param>
    /// <response code="200">Resumen consolidado. El total va en la cabecera X-Total-Registros.</response>
    /// <response code="400">Alguno de los parámetros es inválido.</response>
    [HttpGet("resumen-mensual")]
    [ProducesResponseType(typeof(IEnumerable<ResumenMensualDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorDto), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IEnumerable<ResumenMensualDto>>> ResumenMensual(
        [FromQuery] string? compania,
        [FromQuery] string? producto,
        [FromQuery] DateOnly? periodo,
        [FromQuery] int pagina = 1,
        [FromQuery] int tamanoPagina = 1000,
        CancellationToken ct = default)
    {
        if (compania is { Length: > 100 })
        {
            return BadRequest(new ErrorDto(StatusCodes.Status400BadRequest,
                "El parámetro 'compania' no puede superar los 100 caracteres."));
        }

        if (producto is { Length: > 100 })
        {
            return BadRequest(new ErrorDto(StatusCodes.Status400BadRequest,
                "El parámetro 'producto' no puede superar los 100 caracteres."));
        }

        var filtro = new FiltroResumen
        {
            Compania = compania,
            Producto = producto,
            Periodo = periodo,
            Pagina = pagina,
            TamanoPagina = tamanoPagina
        };

        var resultado = await _resumen.ObtenerResumenAsync(filtro, ct);
        AgregarCabecerasDePaginacion(resultado.TotalRegistros, resultado.PaginaActual,
                                     resultado.TotalPaginas, resultado.TamanoPagina);

        var datos = resultado.Items.Select(r => new ResumenMensualDto(
            r.Compania, r.Producto, r.Periodo,
            r.CantidadVentas, r.TotalVentas, r.NumeroTransacciones));

        return Ok(datos);
    }

    /// <summary>
    /// Matriz mensual producto x período del punto 1.2, incluidos los períodos
    /// sin ventas (que salen en 0).
    /// </summary>
    /// <param name="producto">Filtro parcial por producto. Opcional.</param>
    /// <param name="periodo">Período en formato yyyy-MM-dd. Opcional.</param>
    /// <param name="incluirSinVentas">Si es true, incluye las celdas en 0. Por defecto false.</param>
    /// <param name="pagina">Número de página, comienza en 1.</param>
    /// <param name="tamanoPagina">Registros por página. Máximo 500.</param>
    /// <response code="200">Filas de la matriz mensual.</response>
    [HttpGet("matriz-mensual")]
    [ProducesResponseType(typeof(IEnumerable<MatrizVentaMensual>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IEnumerable<MatrizVentaMensual>>> MatrizMensual(
        [FromQuery] string? producto,
        [FromQuery] DateOnly? periodo,
        [FromQuery] bool incluirSinVentas = false,
        [FromQuery] int pagina = 1,
        [FromQuery] int tamanoPagina = 200,
        CancellationToken ct = default)
    {
        var resultado = await _resumen.ObtenerMatrizAsync(
            producto, periodo, incluirSinVentas, pagina, tamanoPagina, ct);

        AgregarCabecerasDePaginacion(resultado.TotalRegistros, resultado.PaginaActual,
                                     resultado.TotalPaginas, resultado.TamanoPagina);

        return Ok(resultado.Items);
    }

    /// <summary>Registra una venta nueva.</summary>
    /// <response code="201">Venta creada. La cabecera Location apunta al recurso nuevo.</response>
    /// <response code="400">Los datos enviados no pasan las validaciones.</response>
    /// <response code="409">El producto existe pero está inactivo.</response>
    [HttpPost]
    [ProducesResponseType(typeof(VentaDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorDto), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<VentaDto>> CrearVenta([FromBody] VentaInput input, CancellationToken ct)
    {
        // [ApiController] ya devuelve 400 automáticamente si el modelo es inválido;
        // acá sólo quedan las reglas que dependen de la base.
        var resultado = await _ventas.CrearAsync(input, ct);

        if (!resultado.EsExito)
        {
            return TraducirError(resultado.Estado, resultado.Mensaje!);
        }

        var venta = resultado.Valor!;
        var dto = new VentaDto(
            venta.Id, venta.Compania, venta.NombreProducto,
            venta.Fecha.HasValue ? DateOnly.FromDateTime(venta.Fecha.Value) : null,
            venta.Cantidad, venta.Precio, venta.Total);

        return CreatedAtAction(nameof(ObtenerVenta), new { id = venta.Id }, dto);
    }

    /// <summary>Actualiza una venta existente.</summary>
    /// <response code="204">Actualizada correctamente.</response>
    /// <response code="400">Los datos enviados no pasan las validaciones.</response>
    /// <response code="404">No existe una venta con ese Id.</response>
    [HttpPut("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorDto), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ActualizarVenta(int id, [FromBody] VentaInput input, CancellationToken ct)
    {
        var resultado = await _ventas.ActualizarAsync(id, input, ct);

        return resultado.EsExito
            ? NoContent()
            : TraducirError(resultado.Estado, resultado.Mensaje!);
    }

    /// <summary>Elimina una venta.</summary>
    /// <response code="204">Eliminada correctamente.</response>
    /// <response code="404">No existe una venta con ese Id.</response>
    [HttpDelete("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ErrorDto), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> EliminarVenta(int id, CancellationToken ct)
    {
        var resultado = await _ventas.EliminarAsync(id, ct);

        return resultado.EsExito
            ? NoContent()
            : TraducirError(resultado.Estado, resultado.Mensaje!);
    }

    /// <summary>
    /// Traduce el estado de la capa de servicios al código HTTP que le corresponde.
    /// Concentrarlo en un solo lugar evita que cada acción invente el suyo.
    /// </summary>
    private ObjectResult TraducirError(EstadoResultado estado, string mensaje) => estado switch
    {
        EstadoResultado.NoEncontrado => NotFound(new ErrorDto(StatusCodes.Status404NotFound, mensaje)),
        EstadoResultado.Conflicto    => Conflict(new ErrorDto(StatusCodes.Status409Conflict, mensaje)),
        _                            => BadRequest(new ErrorDto(StatusCodes.Status400BadRequest, mensaje))
    };

    private void AgregarCabecerasDePaginacion(int total, int pagina, int totalPaginas, int tamanoPagina)
    {
        Response.Headers["X-Total-Registros"] = total.ToString();
        Response.Headers["X-Pagina"] = pagina.ToString();
        Response.Headers["X-Total-Paginas"] = totalPaginas.ToString();
        Response.Headers["X-Tamano-Pagina"] = tamanoPagina.ToString();
    }
}
