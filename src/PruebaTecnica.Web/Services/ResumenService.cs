using Microsoft.EntityFrameworkCore;
using PruebaTecnica.Web.Data;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Web.Services;

/// <summary>
/// Lectura de los consolidados mensuales.
///
/// La agregación NO se rehace acá: ya está resuelta en las vistas SQL del punto
/// 1.2 y este servicio sólo las consulta y filtra. Una única definición de
/// "total vendido" viviendo en la base garantiza que la app, la API y Power BI
/// muestren exactamente el mismo número.
/// </summary>
public class ResumenService : IResumenService
{
    private readonly AppDbContext _db;

    public ResumenService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<PaginaDe<MatrizVentaMensual>> ObtenerMatrizAsync(
        string? producto, DateOnly? periodo, bool incluirSinVentas,
        int pagina, int tamanoPagina, CancellationToken ct = default)
    {
        if (pagina < 1) pagina = 1;
        if (tamanoPagina is < 1 or > 500) tamanoPagina = 50;

        var consulta = _db.MatrizVentasMensual.AsNoTracking().AsQueryable();

        if (!string.IsNullOrWhiteSpace(producto))
        {
            var texto = producto.Trim();
            consulta = consulta.Where(m => m.Producto.Contains(texto));
        }

        if (periodo is { } p)
        {
            consulta = consulta.Where(m => m.Periodo == NormalizarPeriodo(p));
        }

        if (!incluirSinVentas)
        {
            // Por defecto se ocultan las celdas en cero: son 30.116 de 31.820 y
            // vuelven la pantalla ilegible. El requisito de que existan se cumple
            // en la vista SQL; mostrarlas o no es una decisión de presentación.
            consulta = consulta.Where(m => m.NumeroTransacciones > 0);
        }

        var total = await consulta.CountAsync(ct);

        var items = await consulta
            .OrderByDescending(m => m.Periodo)
            .ThenByDescending(m => m.TotalVentas)
            .Skip((pagina - 1) * tamanoPagina)
            .Take(tamanoPagina)
            .ToListAsync(ct);

        return new PaginaDe<MatrizVentaMensual>
        {
            Items = items,
            PaginaActual = pagina,
            TamanoPagina = tamanoPagina,
            TotalRegistros = total
        };
    }

    public async Task<PaginaDe<ResumenMensualCompania>> ObtenerResumenAsync(
        FiltroResumen filtro, CancellationToken ct = default)
    {
        var consulta = _db.ResumenMensualPorCompania.AsNoTracking().AsQueryable();

        if (!string.IsNullOrWhiteSpace(filtro.Compania))
        {
            var texto = filtro.Compania.Trim();
            consulta = consulta.Where(r => r.Compania == texto);
        }

        if (!string.IsNullOrWhiteSpace(filtro.Producto))
        {
            var texto = filtro.Producto.Trim();
            consulta = consulta.Where(r => r.Producto == texto);
        }

        if (filtro.Periodo is { } p)
        {
            consulta = consulta.Where(r => r.Periodo == NormalizarPeriodo(p));
        }

        var total = await consulta.CountAsync(ct);

        var items = await consulta
            .OrderBy(r => r.Compania)
            .ThenBy(r => r.Producto)
            .ThenBy(r => r.Periodo)
            .Skip((filtro.Pagina - 1) * filtro.TamanoPagina)
            .Take(filtro.TamanoPagina)
            .ToListAsync(ct);

        return new PaginaDe<ResumenMensualCompania>
        {
            Items = items,
            PaginaActual = filtro.Pagina,
            TamanoPagina = filtro.TamanoPagina,
            TotalRegistros = total
        };
    }

    public async Task<IReadOnlyList<DateOnly>> ListarPeriodosAsync(CancellationToken ct = default) =>
        await _db.MatrizVentasMensual
            .AsNoTracking()
            .Select(m => m.Periodo)
            .Distinct()
            .OrderByDescending(p => p)
            .ToListAsync(ct);

    public async Task<IReadOnlyList<string>> ListarCompaniasAsync(CancellationToken ct = default) =>
        await _db.ResumenMensualPorCompania
            .AsNoTracking()
            .Select(r => r.Compania)
            .Distinct()
            .OrderBy(c => c)
            .ToListAsync(ct);

    public async Task<IReadOnlyList<PuntoGrafico>> SerieMensualAsync(
        string? producto = null, CancellationToken ct = default)
    {
        var consulta = _db.MatrizVentasMensual.AsNoTracking().AsQueryable();

        if (!string.IsNullOrWhiteSpace(producto))
        {
            var texto = producto.Trim();
            consulta = consulta.Where(m => m.Producto.Contains(texto));
        }

        // La agregación se hace en SQL, no trayendo 31.820 filas a memoria
        // para sumarlas en C#.
        var filas = await consulta
            .GroupBy(m => m.Periodo)
            .Select(g => new
            {
                Periodo = g.Key,
                Total = g.Sum(x => x.TotalVentas),
                Unidades = g.Sum(x => x.CantidadVentas),
                Transacciones = g.Sum(x => x.NumeroTransacciones)
            })
            .OrderBy(x => x.Periodo)
            .ToListAsync(ct);

        return filas
            .Select(f => new PuntoGrafico(
                f.Periodo.ToString("yyyy-MM"),
                f.Total,
                $"{f.Total.ToString(Formatos.Moneda)} · {f.Unidades:N0} unidades · {f.Transacciones:N0} ventas"))
            .ToList();
    }

    public async Task<IReadOnlyList<PuntoGrafico>> TopProductosAsync(
        int cantidad = 10, CancellationToken ct = default)
    {
        if (cantidad is < 1 or > 50) { cantidad = 10; }

        var filas = await _db.MatrizVentasMensual
            .AsNoTracking()
            .GroupBy(m => m.Producto)
            .Select(g => new
            {
                Producto = g.Key,
                Total = g.Sum(x => x.TotalVentas),
                Unidades = g.Sum(x => x.CantidadVentas)
            })
            .OrderByDescending(x => x.Total)
            .Take(cantidad)
            .ToListAsync(ct);

        return filas
            .Select(f => new PuntoGrafico(
                f.Producto,
                f.Total,
                $"{f.Total.ToString(Formatos.Moneda)} · {f.Unidades:N0} unidades"))
            .ToList();
    }

    /// <summary>
    /// Lleva cualquier fecha al primer día de su mes, igual que la regla del
    /// punto 1.2. Si alguien consulta ?periodo=2024-01-15 recibe enero 2024 en
    /// vez de una lista vacía, que sería técnicamente correcto pero inútil.
    /// </summary>
    private static DateOnly NormalizarPeriodo(DateOnly fecha) =>
        new(fecha.Year, fecha.Month, 1);
}
