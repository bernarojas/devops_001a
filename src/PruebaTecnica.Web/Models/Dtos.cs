namespace PruebaTecnica.Web.Models;

/// <summary>
/// Venta tal como la expone la API.
///
/// Se usa un DTO en vez de devolver la entidad Venta directamente para no
/// filtrar detalles internos del modelo (propiedades de navegación, ciclos de
/// serialización) y para poder cambiar la base sin romper a quien ya consume
/// la API.
/// </summary>
public record VentaDto(
    int Id,
    string? Compania,
    string? Producto,
    DateOnly? Fecha,
    int? Cantidad,
    decimal? Precio,
    decimal Total);

/// <summary>
/// Fila del resumen mensual consolidado.
/// Los nombres coinciden exactamente con el JSON de ejemplo del enunciado:
/// compania, producto, periodo, cantidadVentas, totalVentas
/// (camelCase aplicado automáticamente por System.Text.Json).
/// </summary>
public record ResumenMensualDto(
    string Compania,
    string Producto,
    DateOnly Periodo,
    long CantidadVentas,
    decimal TotalVentas,
    int NumeroTransacciones);

/// <summary>Envoltorio de respuesta paginada para la API.</summary>
public record RespuestaPaginada<T>(
    IReadOnlyList<T> Datos,
    int Pagina,
    int TamanoPagina,
    int TotalRegistros,
    int TotalPaginas);

/// <summary>
/// Formato único de error de la API. Que todos los errores tengan la misma
/// forma le simplifica la vida a quien la consume.
/// </summary>
public record ErrorDto(int Estado, string Mensaje, string? Detalle = null);
