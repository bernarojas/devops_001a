using Microsoft.AspNetCore.Mvc;
using PruebaTecnica.Web.Models;
using PruebaTecnica.Web.Services;

namespace PruebaTecnica.Web.Controllers;

/// <summary>CRUD del maestro de productos generado en el punto 1.1.</summary>
public class ProductosController : Controller
{
    private readonly IProductoService _productos;

    public ProductosController(IProductoService productos)
    {
        _productos = productos;
    }

    // GET /Productos
    public async Task<IActionResult> Index(string? busqueda, int pagina = 1, int tamanoPagina = 25,
                                           CancellationToken ct = default)
    {
        ViewBag.Busqueda = busqueda;
        return View(await _productos.ListarAsync(busqueda, pagina, tamanoPagina, ct));
    }

    // GET /Productos/Details/5
    public async Task<IActionResult> Details(int id, CancellationToken ct)
    {
        var producto = await _productos.ObtenerAsync(id, ct);
        if (producto is null)
        {
            return VistaNoEncontrado(id);
        }

        ViewBag.CantidadVentas = await _productos.ContarVentasAsync(id, ct);
        return View(producto);
    }

    // GET /Productos/Create
    public IActionResult Create() => View(new Producto { Activo = true });

    // POST /Productos/Create
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Create(Producto producto, CancellationToken ct)
    {
        if (!ModelState.IsValid)
        {
            return View(producto);
        }

        var resultado = await _productos.CrearAsync(producto, ct);
        if (!resultado.EsExito)
        {
            // El nombre duplicado se señala en el campo que lo causa, no en el
            // resumen general: así el usuario ve dónde corregir.
            ModelState.AddModelError(nameof(Producto.NombreProducto), resultado.Mensaje!);
            return View(producto);
        }

        TempData["Mensaje"] = $"Producto '{resultado.Valor!.NombreProducto}' creado correctamente.";
        return RedirectToAction(nameof(Index));
    }

    // GET /Productos/Edit/5
    public async Task<IActionResult> Edit(int id, CancellationToken ct)
    {
        var producto = await _productos.ObtenerAsync(id, ct);
        return producto is null ? VistaNoEncontrado(id) : View(producto);
    }

    // POST /Productos/Edit/5
    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(int id, Producto producto, CancellationToken ct)
    {
        if (!ModelState.IsValid)
        {
            return View(producto);
        }

        var resultado = await _productos.ActualizarAsync(id, producto, ct);
        if (!resultado.EsExito)
        {
            if (resultado.Estado == EstadoResultado.NoEncontrado)
            {
                return VistaNoEncontrado(id);
            }

            ModelState.AddModelError(nameof(Producto.NombreProducto), resultado.Mensaje!);
            return View(producto);
        }

        TempData["Mensaje"] = $"Producto '{producto.NombreProducto}' actualizado correctamente.";
        return RedirectToAction(nameof(Index));
    }

    // GET /Productos/Delete/5 -> pantalla de confirmación
    public async Task<IActionResult> Delete(int id, CancellationToken ct)
    {
        var producto = await _productos.ObtenerAsync(id, ct);
        if (producto is null)
        {
            return VistaNoEncontrado(id);
        }

        // Se avisa por adelantado si el borrado va a ser rechazado, en vez de
        // dejar que el usuario confirme y recién ahí recibir el error.
        ViewBag.CantidadVentas = await _productos.ContarVentasAsync(id, ct);
        return View(producto);
    }

    // POST /Productos/Delete/5
    [HttpPost, ActionName("Delete")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteConfirmado(int id, CancellationToken ct)
    {
        var resultado = await _productos.EliminarAsync(id, ct);

        if (!resultado.EsExito)
        {
            TempData["Error"] = resultado.Mensaje;
            return RedirectToAction(nameof(Index));
        }

        TempData["Mensaje"] = "Producto eliminado.";
        return RedirectToAction(nameof(Index));
    }

    private IActionResult VistaNoEncontrado(int id)
    {
        Response.StatusCode = StatusCodes.Status404NotFound;
        ViewBag.Mensaje = $"No existe el producto con Id {id}.";
        return View("NoEncontrado");
    }
}
