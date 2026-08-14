using Microsoft.EntityFrameworkCore;
using PruebaTecnica.Web.Data;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Web.Services;

/// <summary>
/// Reglas de negocio del maestro de productos.
///
/// Dos reglas cargan con casi todo el peso:
///  1. El nombre es único. Si no, el maestro deja de ser un maestro.
///  2. No se borra un producto que tiene ventas. Se desactiva.
/// </summary>
public class ProductoService : IProductoService
{
    private readonly AppDbContext _db;
    private readonly ILogger<ProductoService> _log;

    public ProductoService(AppDbContext db, ILogger<ProductoService> log)
    {
        _db = db;
        _log = log;
    }

    public async Task<PaginaDe<Producto>> ListarAsync(string? busqueda, int pagina, int tamanoPagina,
                                                      CancellationToken ct = default)
    {
        if (pagina < 1) pagina = 1;
        if (tamanoPagina is < 1 or > 200) tamanoPagina = 25;

        var consulta = _db.Productos.AsNoTracking().AsQueryable();

        if (!string.IsNullOrWhiteSpace(busqueda))
        {
            var texto = busqueda.Trim();
            consulta = consulta.Where(p => p.NombreProducto.Contains(texto));
        }

        var total = await consulta.CountAsync(ct);

        var items = await consulta
            .OrderBy(p => p.NombreProducto)
            .Skip((pagina - 1) * tamanoPagina)
            .Take(tamanoPagina)
            .ToListAsync(ct);

        return new PaginaDe<Producto>
        {
            Items = items,
            PaginaActual = pagina,
            TamanoPagina = tamanoPagina,
            TotalRegistros = total
        };
    }

    public async Task<IReadOnlyList<Producto>> ListarActivosAsync(CancellationToken ct = default) =>
        await _db.Productos
            .AsNoTracking()
            .Where(p => p.Activo)
            .OrderBy(p => p.NombreProducto)
            .ToListAsync(ct);

    public Task<Producto?> ObtenerAsync(int id, CancellationToken ct = default) =>
        _db.Productos.AsNoTracking().FirstOrDefaultAsync(p => p.IdProducto == id, ct);

    public async Task<Resultado<Producto>> CrearAsync(Producto producto, CancellationToken ct = default)
    {
        var nombre = producto.NombreProducto.Trim();

        if (string.IsNullOrWhiteSpace(nombre))
        {
            return Resultado<Producto>.Invalido("El nombre del producto no puede estar vacío.");
        }

        // Se valida acá además de tener el índice único en la base: así el
        // usuario recibe un mensaje claro en vez de un error de SQL Server.
        var yaExiste = await _db.Productos.AnyAsync(p => p.NombreProducto == nombre, ct);
        if (yaExiste)
        {
            return Resultado<Producto>.Conflicto($"Ya existe un producto llamado '{nombre}'.");
        }

        var nuevo = new Producto
        {
            NombreProducto = nombre,
            Activo = producto.Activo
        };

        _db.Productos.Add(nuevo);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Producto {Id} '{Nombre}' creado.", nuevo.IdProducto, nombre);
        return Resultado<Producto>.Exito(nuevo);
    }

    public async Task<Resultado> ActualizarAsync(int id, Producto producto, CancellationToken ct = default)
    {
        var existente = await _db.Productos.FirstOrDefaultAsync(p => p.IdProducto == id, ct);
        if (existente is null)
        {
            return Resultado.NoEncontrado($"No existe el producto con Id {id}.");
        }

        var nombre = producto.NombreProducto.Trim();
        if (string.IsNullOrWhiteSpace(nombre))
        {
            return Resultado.Invalido("El nombre del producto no puede estar vacío.");
        }

        var nombreOcupado = await _db.Productos
            .AnyAsync(p => p.NombreProducto == nombre && p.IdProducto != id, ct);

        if (nombreOcupado)
        {
            return Resultado.Conflicto($"Ya existe otro producto llamado '{nombre}'.");
        }

        var cambioElNombre = !string.Equals(existente.NombreProducto, nombre, StringComparison.Ordinal);

        // Renombrar un producto obliga a propagar el cambio a la columna de texto
        // Ventas.Producto. Es el costo de tener el producto duplicado (texto + FK);
        // si no se propaga, el chequeo 6 de 02_analisis_datos.sql empieza a fallar.
        // Las dos escrituras van en una transacción: o cambian ambas, o ninguna.
        //
        // La transacción se ejecuta a través de la execution strategy de EF Core.
        // Es obligatorio: la conexión tiene EnableRetryOnFailure activado, y una
        // transacción abierta a mano sobre una estrategia con reintentos lanza
        // InvalidOperationException. El motivo es sensato: si el reintento
        // ocurriera a mitad de la transacción, EF no sabría desde qué punto
        // reanudar. Pasándole el bloque entero, reintenta la unidad completa.
        var estrategia = _db.Database.CreateExecutionStrategy();

        await estrategia.ExecuteAsync(async () =>
        {
            await using var transaccion = await _db.Database.BeginTransactionAsync(ct);

            existente.NombreProducto = nombre;
            existente.Activo = producto.Activo;
            await _db.SaveChangesAsync(ct);

            if (cambioElNombre)
            {
                var filas = await _db.Ventas
                    .Where(v => v.IdProducto == id)
                    .ExecuteUpdateAsync(s => s.SetProperty(v => v.NombreProducto, nombre), ct);

                _log.LogInformation(
                    "Producto {Id} renombrado a '{Nombre}'. Se propagó a {Filas} ventas.",
                    id, nombre, filas);
            }

            // Si algo falla antes de este punto, el using descarta la transacción
            // sin commit y SQL Server revierte todo automáticamente.
            await transaccion.CommitAsync(ct);
        });

        return Resultado.Exito();
    }

    public async Task<Resultado> EliminarAsync(int id, CancellationToken ct = default)
    {
        var producto = await _db.Productos.FirstOrDefaultAsync(p => p.IdProducto == id, ct);
        if (producto is null)
        {
            return Resultado.NoEncontrado($"No existe el producto con Id {id}.");
        }

        var ventasAsociadas = await _db.Ventas.CountAsync(v => v.IdProducto == id, ct);
        if (ventasAsociadas > 0)
        {
            // Borrar en cascada destruiría historial de ventas real. Se rechaza
            // y se ofrece la alternativa correcta: desactivar.
            return Resultado.Conflicto(
                $"No se puede eliminar '{producto.NombreProducto}': tiene {ventasAsociadas:N0} " +
                "ventas asociadas. Desactívelo en su lugar para sacarlo de circulación " +
                "sin perder el historial.");
        }

        _db.Productos.Remove(producto);
        await _db.SaveChangesAsync(ct);

        _log.LogInformation("Producto {Id} '{Nombre}' eliminado.", id, producto.NombreProducto);
        return Resultado.Exito();
    }

    public Task<int> ContarVentasAsync(int idProducto, CancellationToken ct = default) =>
        _db.Ventas.CountAsync(v => v.IdProducto == idProducto, ct);
}
