using Microsoft.EntityFrameworkCore;
using PruebaTecnica.Web.Data;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Web.Services;

/// <summary>
/// Reglas de negocio de las ventas. Los controladores no tocan el DbContext:
/// sólo traducen el resultado de este servicio a una respuesta HTTP o a una vista.
/// </summary>
public class VentaService : IVentaService
{
    private readonly AppDbContext _db;
    private readonly ILogger<VentaService> _log;

    public VentaService(AppDbContext db, ILogger<VentaService> log)
    {
        _db = db;
        _log = log;
    }

    public async Task<PaginaDe<Venta>> ListarAsync(FiltroVentas filtro, CancellationToken ct = default)
    {
        // AsNoTracking: es una consulta de sólo lectura, no hace falta que EF
        // vigile los cambios de 15.000 entidades.
        var consulta = _db.Ventas
            .AsNoTracking()
            .Include(v => v.ProductoMaestro)
            .AsQueryable();

        if (!string.IsNullOrWhiteSpace(filtro.Compania))
        {
            var texto = filtro.Compania.Trim();
            consulta = consulta.Where(v => v.Compania != null && v.Compania.Contains(texto));
        }

        if (!string.IsNullOrWhiteSpace(filtro.Producto))
        {
            var texto = filtro.Producto.Trim();
            consulta = consulta.Where(v => v.NombreProducto != null && v.NombreProducto.Contains(texto));
        }

        if (filtro.Desde is { } desde)
        {
            consulta = consulta.Where(v => v.Fecha >= desde.Date);
        }

        if (filtro.Hasta is { } hasta)
        {
            // Se incluye el día completo: <= 23:59:59 del día indicado.
            var finDelDia = hasta.Date.AddDays(1);
            consulta = consulta.Where(v => v.Fecha < finDelDia);
        }

        if (filtro.SoloAnomalias)
        {
            consulta = consulta.Where(v =>
                v.Cantidad == null || v.Cantidad <= 0 ||
                v.Precio   == null || v.Precio   <= 0 ||
                v.Fecha    == null ||
                v.IdProducto == null);
        }

        // Se cuenta antes de paginar: el total es el del filtro, no el de la página.
        var total = await consulta.CountAsync(ct);

        var items = await consulta
            .OrderByDescending(v => v.Fecha)
            .ThenByDescending(v => v.Id)
            .Skip((filtro.Pagina - 1) * filtro.TamanoPagina)
            .Take(filtro.TamanoPagina)
            .ToListAsync(ct);

        return new PaginaDe<Venta>
        {
            Items = items,
            PaginaActual = filtro.Pagina,
            TamanoPagina = filtro.TamanoPagina,
            TotalRegistros = total
        };
    }

    public Task<Venta?> ObtenerAsync(int id, CancellationToken ct = default) =>
        _db.Ventas
           .AsNoTracking()
           .Include(v => v.ProductoMaestro)
           .FirstOrDefaultAsync(v => v.Id == id, ct);

    public async Task<Resultado<Venta>> CrearAsync(VentaInput input, CancellationToken ct = default)
    {
        var producto = await _db.Productos
            .FirstOrDefaultAsync(p => p.IdProducto == input.IdProducto, ct);

        if (producto is null)
        {
            return Resultado<Venta>.Invalido(
                $"El producto con Id {input.IdProducto} no existe en el maestro.");
        }

        if (!producto.Activo)
        {
            return Resultado<Venta>.Conflicto(
                $"El producto '{producto.NombreProducto}' está inactivo y no admite ventas nuevas.");
        }

        var venta = new Venta
        {
            Compania = input.Compania.Trim(),
            IdProducto = producto.IdProducto,
            // El texto se copia del maestro, nunca de lo que escriba el usuario.
            // Así las dos columnas no se pueden desincronizar.
            NombreProducto = producto.NombreProducto,
            Fecha = input.Fecha!.Value.Date,
            Cantidad = input.Cantidad,
            Precio = input.Precio
        };

        _db.Ventas.Add(venta);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Venta {Id} creada para el producto {Producto}.",
                            venta.Id, producto.NombreProducto);

        return Resultado<Venta>.Exito(venta);
    }

    public async Task<Resultado> ActualizarAsync(int id, VentaInput input, CancellationToken ct = default)
    {
        var venta = await _db.Ventas.FirstOrDefaultAsync(v => v.Id == id, ct);
        if (venta is null)
        {
            return Resultado.NoEncontrado($"No existe la venta con Id {id}.");
        }

        var producto = await _db.Productos
            .FirstOrDefaultAsync(p => p.IdProducto == input.IdProducto, ct);

        if (producto is null)
        {
            return Resultado.Invalido($"El producto con Id {input.IdProducto} no existe en el maestro.");
        }

        // A diferencia de crear, acá NO se bloquea el producto inactivo: hay que
        // poder corregir una venta histórica de un producto que ya se descontinuó.
        venta.Compania = input.Compania.Trim();
        venta.IdProducto = producto.IdProducto;
        venta.NombreProducto = producto.NombreProducto;
        venta.Fecha = input.Fecha!.Value.Date;
        venta.Cantidad = input.Cantidad;
        venta.Precio = input.Precio;

        await _db.SaveChangesAsync(ct);
        _log.LogInformation("Venta {Id} actualizada.", id);

        return Resultado.Exito();
    }

    public async Task<Resultado> EliminarAsync(int id, CancellationToken ct = default)
    {
        var venta = await _db.Ventas.FirstOrDefaultAsync(v => v.Id == id, ct);
        if (venta is null)
        {
            return Resultado.NoEncontrado($"No existe la venta con Id {id}.");
        }

        _db.Ventas.Remove(venta);
        await _db.SaveChangesAsync(ct);
        _log.LogInformation("Venta {Id} eliminada.", id);

        return Resultado.Exito();
    }

    public async Task<IReadOnlyList<string>> ListarCompaniasAsync(CancellationToken ct = default) =>
        await _db.Ventas
            .AsNoTracking()
            .Where(v => v.Compania != null && v.Compania != "")
            .Select(v => v.Compania!)
            .Distinct()
            .OrderBy(c => c)
            .ToListAsync(ct);
}
