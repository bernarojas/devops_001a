using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PruebaTecnica.Web.Data;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

namespace PruebaTecnica.Web.Controllers;

public class HomeController : Controller
{
    private readonly ILogger<HomeController> _logger;
    private readonly AppDbContext _db;
    private readonly IResumenService _resumen;

    public HomeController(ILogger<HomeController> logger, AppDbContext db, IResumenService resumen)
    {
        _logger = logger;
        _db = db;
        _resumen = resumen;
    }

    /// <summary>
    /// Portada con las cifras clave. Sirve además de verificación rápida: si
    /// estos números no cuadran con los que devuelve el script SQL, algo está mal.
    /// </summary>
    public async Task<IActionResult> Index(CancellationToken ct)
    {
        try
        {
            ViewBag.TotalVentas = await _db.Ventas.CountAsync(ct);
            ViewBag.TotalProductos = await _db.Productos.CountAsync(ct);

            ViewBag.MontoTotal = await _db.Ventas
                .Where(v => v.Fecha != null)
                .SumAsync(v => (decimal?)((v.Cantidad ?? 0) * (v.Precio ?? 0m)), ct) ?? 0m;

            ViewBag.TotalPeriodos = await _db.MatrizVentasMensual
                .Select(m => m.Periodo).Distinct().CountAsync(ct);

            ViewBag.Anomalias = await _db.Ventas.CountAsync(v =>
                v.Cantidad == null || v.Cantidad <= 0 ||
                v.Precio == null || v.Precio <= 0 ||
                v.Fecha == null || v.IdProducto == null, ct);

            ViewBag.SerieMensual = await _resumen.SerieMensualAsync(ct: ct);
            ViewBag.TopProductos = await _resumen.TopProductosAsync(10, ct);

            ViewBag.BaseDisponible = true;
        }
        catch (Exception ex)
        {
            // La portada tiene que abrir igual aunque la base no responda: el
            // usuario necesita ver el mensaje que le explica qué falta levantar.
            _logger.LogError(ex, "No se pudieron obtener las cifras de la portada.");
            ViewBag.BaseDisponible = false;
        }

        return View();
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error(int? codigo)
    {
        ViewBag.Codigo = codigo;
        return View(new ErrorViewModel
        {
            RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier
        });
    }
}
