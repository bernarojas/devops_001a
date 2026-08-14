using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace PruebaTecnica.Web.Models;

/// <summary>
/// Venta individual (tabla dbo.Ventas, la tabla original del backup).
///
/// NOTA SOBRE NULABILIDAD: todas las columnas de negocio se declaran nullable
/// porque así están definidas en la base de datos original y porque los datos
/// reales contienen filas sucias. Si el modelo las declarara obligatorias, EF
/// Core lanzaría una excepción al leer esas filas y la app no podría ni siquiera
/// listarlas — justo las filas que interesa poder ver y corregir.
///
/// Las validaciones de entrada NO viven acá sino en VentaInput, que es lo que
/// reciben los formularios y la API. Separar "cómo está el dato guardado" de
/// "qué acepto como dato nuevo" permite mostrar el historial sucio y a la vez
/// impedir que entre más basura.
/// </summary>
[Table("Ventas")]
public class Venta
{
    [Key]
    [Column("ID")]
    public int Id { get; set; }

    [StringLength(100)]
    [Display(Name = "Compañía")]
    public string? Compania { get; set; }

    /// <summary>
    /// Nombre del producto como texto, tal como venía en la tabla original.
    /// Se mantiene sincronizado con IdProducto: la app siempre lo escribe a
    /// partir del maestro, nunca a mano.
    /// </summary>
    [Column("Producto")]
    [StringLength(100)]
    [Display(Name = "Producto")]
    public string? NombreProducto { get; set; }

    [Display(Name = "Fecha")]
    [DataType(DataType.Date)]
    public DateTime? Fecha { get; set; }

    [Display(Name = "Cantidad")]
    public int? Cantidad { get; set; }

    [Display(Name = "Precio unitario")]
    [Column(TypeName = "decimal(18,2)")]
    public decimal? Precio { get; set; }

    /// <summary>Clave foránea al maestro de productos.</summary>
    public int? IdProducto { get; set; }

    [ForeignKey(nameof(IdProducto))]
    public Producto? ProductoMaestro { get; set; }

    /// <summary>Total de la línea. Calculado, no se guarda en la base.</summary>
    [NotMapped]
    [Display(Name = "Total")]
    public decimal Total => (Cantidad ?? 0) * (Precio ?? 0m);
}
