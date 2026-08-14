using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

namespace PruebaTecnica.Web.Controllers;

/// <summary>CRUD de ventas sobre vistas Razor.</summary>
public class VentasController : Controller
{
    private readonly IVentaService _ventas;
    private readonly IProductoService _productos;

    public VentasController(IVentaService ventas, IProductoService productos)
    {
        _ventas = ventas;
        _productos = productos;
    }

    // GET /Ventas
    public async Task<IActionResult> Index(FiltroVentas filtro, CancellationToken ct)
    {
        ViewBag.Filtro = filtro;
        return View(await _ventas.ListarAsync(filtro, ct));
    }

    // GET /Ventas/Details/5
    public async Task<IActionResult> Details(int id, CancellationToken ct)
    {
        var venta = await _ventas.ObtenerAsync(id, ct);
        return venta is null ? VistaNoEncontrado(id) : View(venta);
    }

    // GET /Ventas/Create
    public async Task<IActionResult> Create(CancellationToken ct)
    {
        await CargarProductosAsync(ct);
        return View(new VentaInput { Fecha = DateTime.Today });
    }

    // POST /Ventas/Create
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(VentaInput input, CancellationToken ct)
    {
        if (!ModelState.IsValid)
        {
            await CargarProductosAsync(ct);
            return View(input);
        }

        var resultado = await _ventas.CrearAsync(input, ct);
        if (!resultado.EsExito)
        {
            // El error viene de una regla de negocio, no del formulario:
            // se muestra en el resumen de validación de la misma pantalla.
            ModelState.AddModelError(string.Empty, resultado.Mensaje!);
            await CargarProductosAsync(ct);
            return View(input);
        }

        TempData["Mensaje"] = $"Venta #{resultado.Valor!.Id} creada correctamente.";
        return RedirectToAction(nameof(Index));
    }

    // GET /Ventas/Edit/5
    public async Task<IActionResult> Edit(int id, CancellationToken ct)
    {
        var venta = await _ventas.ObtenerAsync(id, ct);
        if (venta is null)
        {
            return VistaNoEncontrado(id);
        }

        await CargarProductosAsync(ct);

        return View(new VentaInput
        {
            Id = venta.Id,
            Compania = venta.Compania ?? string.Empty,
            IdProducto = venta.IdProducto,
            Fecha = venta.Fecha,
            Cantidad = venta.Cantidad,
            Precio = venta.Precio
        });
    }

    // POST /Ventas/Edit/5
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(int id, VentaInput input, CancellationToken ct)
    {
        if (!ModelState.IsValid)
        {
            await CargarProductosAsync(ct);
            return View(input);
        }

        var resultado = await _ventas.ActualizarAsync(id, input, ct);
        if (!resultado.EsExito)
        {
            if (resultado.Estado == EstadoResultado.NoEncontrado)
            {
                return VistaNoEncontrado(id);
            }

            ModelState.AddModelError(string.Empty, resultado.Mensaje!);
            await CargarProductosAsync(ct);
            return View(input);
        }

        TempData["Mensaje"] = $"Venta #{id} actualizada correctamente.";
        return RedirectToAction(nameof(Index));
    }

    // GET /Ventas/Delete/5  -> pantalla de confirmación
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var venta = await _ventas.ObtenerAsync(id, ct);
        return venta is null ? VistaNoEncontrado(id) : View(venta);
    }

    // POST /Ventas/Delete/5
    [HttpPost, ActionName("Delete")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteConfirmado(int id, CancellationToken ct)
    {
        var resultado = await _ventas.EliminarAsync(id, ct);

        if (!resultado.EsExito)
        {
            TempData["Error"] = resultado.Mensaje;
            return RedirectToAction(nameof(Index));
        }

        TempData["Mensaje"] = $"Venta #{id} eliminada.";
        return RedirectToAction(nameof(Index));
    }

    /// <summary>
    /// Sólo se ofrecen productos activos: un producto dado de baja no debe poder
    /// recibir ventas nuevas desde el formulario.
    /// </summary>
    private async Task CargarProductosAsync(CancellationToken ct)
    {
        var productos = await _productos.ListarActivosAsync(ct);
        ViewBag.Productos = new SelectList(productos, nameof(Producto.IdProducto),
                                                      nameof(Producto.NombreProducto));
    }

    private IActionResult VistaNoEncontrado(int id)
    {
        Response.StatusCode = StatusCodes.Status404NotFound;
        ViewBag.Mensaje = $"No existe la venta con Id {id}.";
        return View("NoEncontrado");
    }
}
