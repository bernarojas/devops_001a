using Microsoft.AspNetCore.Mvc;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

namespace PruebaTecnica.Web.Controllers;

/// <summary>
/// Resumen mensual: ventas agrupadas por producto y período, con total y
/// cantidad vendida (punto 2, "Resumen mensual").
/// </summary>
public class ResumenController : Controller
{
    private readonly IResumenService _resumen;

    public ResumenController(IResumenService resumen)
    {
        _resumen = resumen;
    }

    /// <summary>Matriz producto x período.</summary>
    public async Task<IActionResult> Index(
        string? producto, DateOnly? periodo, bool incluirSinVentas = false,
        int pagina = 1, int tamanoPagina = 50, CancellationToken ct = default)
    {
        ViewBag.Producto = producto;
        ViewBag.Periodo = periodo;
        ViewBag.IncluirSinVentas = incluirSinVentas;
        ViewBag.Periodos = await _resumen.ListarPeriodosAsync(ct);

        // La serie respeta el filtro de producto pero NO el de período: un
        // gráfico de evolución con un solo mes no muestra ninguna evolución.
        ViewBag.Serie = await _resumen.SerieMensualAsync(producto, ct);

        var pagina_ = await _resumen.ObtenerMatrizAsync(
            producto, periodo, incluirSinVentas, pagina, tamanoPagina, ct);

        return View(pagina_);
    }

    /// <summary>Consolidado abierto también por compañía.</summary>
    public async Task<IActionResult> PorCompania(FiltroResumen filtro, CancellationToken ct)
    {
        ViewBag.Filtro = filtro;
        ViewBag.Periodos = await _resumen.ListarPeriodosAsync(ct);
        ViewBag.Companias = await _resumen.ListarCompaniasAsync(ct);

        return View(await _resumen.ObtenerResumenAsync(filtro, ct));
    }
}
