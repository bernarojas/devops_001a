using Microsoft.EntityFrameworkCore;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Web.Data;

/// <summary>
/// Contexto de EF Core sobre la base Tecnica.
///
/// ENFOQUE: database-first. La base ya existe (viene del backup .bak y del
/// script 01_esquema_y_matriz.sql), así que no hay migraciones. El modelo se
/// escribe a mano para calzar con el esquema existente, no al revés.
/// </summary>
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<Venta> Ventas => Set<Venta>();
    public DbSet<Producto> Productos => Set<Producto>();
    public DbSet<MatrizVentaMensual> MatrizVentasMensual => Set<MatrizVentaMensual>();
    public DbSet<ResumenMensualCompania> ResumenMensualPorCompania => Set<ResumenMensualCompania>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Producto>(entidad =>
        {
            entidad.ToTable("Productos");
            entidad.HasKey(p => p.IdProducto);
            entidad.HasIndex(p => p.NombreProducto).IsUnique();

            // La base pone el valor por defecto; EF no debe intentar escribirlo.
            entidad.Property(p => p.FechaCreacion)
                   .HasDefaultValueSql("SYSUTCDATETIME()")
                   .ValueGeneratedOnAdd();
        });

        modelBuilder.Entity<Venta>(entidad =>
        {
            entidad.ToTable("Ventas");
            entidad.HasKey(v => v.Id);
            entidad.Property(v => v.Precio).HasPrecision(18, 2);

            entidad.HasOne(v => v.ProductoMaestro)
                   .WithMany(p => p.Ventas)
                   .HasForeignKey(v => v.IdProducto)
                   .OnDelete(DeleteBehavior.Restrict);   // no borrar ventas al borrar un producto
        });

        // Vistas de sólo lectura. HasNoKey + ToView evita que EF intente
        // rastrear cambios o generar INSERT/UPDATE sobre ellas.
        modelBuilder.Entity<MatrizVentaMensual>(entidad =>
        {
            entidad.HasNoKey();
            entidad.ToView("vw_MatrizVentasMensual");
            entidad.Property(m => m.TotalVentas).HasPrecision(19, 2);
        });

        modelBuilder.Entity<ResumenMensualCompania>(entidad =>
        {
            entidad.HasNoKey();
            entidad.ToView("vw_ResumenMensualPorCompania");
            entidad.Property(r => r.TotalVentas).HasPrecision(19, 2);
        });
    }
}
