using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace PruebaTecnica.Web.Models;

/// <summary>
/// Maestro de productos (tabla dbo.Productos, creada por 01_esquema_y_matriz.sql).
/// </summary>
[Table("Productos")]
public class Producto
{
    [Key]
    public int IdProducto { get; set; }

    [Required(ErrorMessage = "El nombre del producto es obligatorio.")]
    [StringLength(100, MinimumLength = 2,
        ErrorMessage = "El nombre debe tener entre 2 y 100 caracteres.")]
    [Display(Name = "Nombre del producto")]
    public string NombreProducto { get; set; } = string.Empty;

    /// <summary>
    /// Borrado lógico. Un producto inactivo no se ofrece al registrar ventas nuevas,
    /// pero conserva todo su historial.
    /// </summary>
    [Display(Name = "Activo")]
    public bool Activo { get; set; } = true;

    [Display(Name = "Fecha de creación")]
    public DateTime FechaCreacion { get; set; }

    public ICollection<Venta> Ventas { get; set; } = new List<Venta>();
}
