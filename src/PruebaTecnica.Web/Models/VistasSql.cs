using Microsoft.EntityFrameworkCore;

namespace PruebaTecnica.Web.Models;

/// <summary>
/// Fila de dbo.vw_MatrizVentasMensual: la matriz producto x período del punto 1.2,
/// ya rellenada con ceros donde no hubo ventas.
///
/// Se mapea como entidad sin clave (Keyless) porque es una vista de sólo lectura:
/// EF Core no debe intentar rastrear cambios ni escribir sobre ella.
/// </summary>
[Keyless]
public class MatrizVentaMensual
{
    public int IdProducto { get; set; }
    public string Producto { get; set; } = string.Empty;
    public DateOnly Periodo { get; set; }
    public long CantidadVentas { get; set; }
    public decimal TotalVentas { get; set; }
    public int NumeroTransacciones { get; set; }
}

/// <summary>
/// Fila de dbo.vw_ResumenMensualPorCompania: consolidado compañía + producto +
/// período que consume el endpoint GET /api/ventas/resumen-mensual.
/// </summary>
[Keyless]
public class ResumenMensualCompania
{
    public string Compania { get; set; } = string.Empty;
    public string Producto { get; set; } = string.Empty;
    public DateOnly Periodo { get; set; }
    public long CantidadVentas { get; set; }
    public decimal TotalVentas { get; set; }
    public int NumeroTransacciones { get; set; }
}
