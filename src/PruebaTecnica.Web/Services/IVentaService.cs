using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Web.Services;

public interface IVentaService
{
    Task<PaginaDe<Venta>> ListarAsync(FiltroVentas filtro, CancellationToken ct = default);
    Task<Venta?> ObtenerAsync(int id, CancellationToken ct = default);
    Task<Resultado<Venta>> CrearAsync(VentaInput input, CancellationToken ct = default);
    Task<Resultado> ActualizarAsync(int id, VentaInput input, CancellationToken ct = default);
    Task<Resultado> EliminarAsync(int id, CancellationToken ct = default);

    /// <summary>Compañías distintas, para poblar los combos de filtro.</summary>
    Task<IReadOnlyList<string>> ListarCompaniasAsync(CancellationToken ct = default);
}

public interface IProductoService
{
    Task<PaginaDe<Producto>> ListarAsync(string? busqueda, int pagina, int tamanoPagina,
                                         CancellationToken ct = default);
    Task<IReadOnlyList<Producto>> ListarActivosAsync(CancellationToken ct = default);
    Task<Producto?> ObtenerAsync(int id, CancellationToken ct = default);
    Task<Resultado<Producto>> CrearAsync(Producto producto, CancellationToken ct = default);
    Task<Resultado> ActualizarAsync(int id, Producto producto, CancellationToken ct = default);
    Task<Resultado> EliminarAsync(int id, CancellationToken ct = default);

    /// <summary>Cuántas ventas cuelgan de un producto. Se usa para explicar por qué no se puede borrar.</summary>
    Task<int> ContarVentasAsync(int idProducto, CancellationToken ct = default);
}

public interface IResumenService
{
    /// <summary>Matriz producto x período del punto 1.2 (incluye los ceros).</summary>
    Task<PaginaDe<MatrizVentaMensual>> ObtenerMatrizAsync(
        string? producto, DateOnly? periodo, bool incluirSinVentas,
        int pagina, int tamanoPagina, CancellationToken ct = default);

    /// <summary>Consolidado compañía + producto + período que consume la API.</summary>
    Task<PaginaDe<ResumenMensualCompania>> ObtenerResumenAsync(
        FiltroResumen filtro, CancellationToken ct = default);

    Task<IReadOnlyList<DateOnly>> ListarPeriodosAsync(CancellationToken ct = default);
    Task<IReadOnlyList<string>> ListarCompaniasAsync(CancellationToken ct = default);

    /// <summary>
    /// Total vendido por período, para el gráfico de evolución mensual.
    /// Opcionalmente acotado a un producto.
    /// </summary>
    Task<IReadOnlyList<PuntoGrafico>> SerieMensualAsync(
        string? producto = null, CancellationToken ct = default);

    /// <summary>Productos con mayor total vendido, para el gráfico de ranking.</summary>
    Task<IReadOnlyList<PuntoGrafico>> TopProductosAsync(
        int cantidad = 10, CancellationToken ct = default);
}
