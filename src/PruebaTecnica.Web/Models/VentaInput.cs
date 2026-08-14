using System.ComponentModel.DataAnnotations;

namespace PruebaTecnica.Web.Models;

/// <summary>
/// Datos que la app acepta para crear o editar una venta.
///
/// Acá sí todo es obligatorio y validado. Es la frontera que impide que entren
/// las mismas anomalías que 02_analisis_datos.sql encontró en el histórico:
/// cantidades negativas, precios en 0 y fechas absurdas.
/// </summary>
public class VentaInput : IValidatableObject
{
    public int Id { get; set; }

    [Required(ErrorMessage = "La compañía es obligatoria.")]
    [StringLength(100, MinimumLength = 2,
        ErrorMessage = "La compañía debe tener entre 2 y 100 caracteres.")]
    [Display(Name = "Compañía")]
    public string Compania { get; set; } = string.Empty;

    [Required(ErrorMessage = "Debe seleccionar un producto del maestro.")]
    [Display(Name = "Producto")]
    public int? IdProducto { get; set; }

    [Required(ErrorMessage = "La fecha es obligatoria.")]
    [DataType(DataType.Date)]
    [Display(Name = "Fecha")]
    public DateTime? Fecha { get; set; }

    [Required(ErrorMessage = "La cantidad es obligatoria.")]
    [Range(1, 100_000, ErrorMessage = "La cantidad debe ser mayor que 0.")]
    [Display(Name = "Cantidad")]
    public int? Cantidad { get; set; }

    [Required(ErrorMessage = "El precio es obligatorio.")]
    [Range(0.01, 999_999_999, ErrorMessage = "El precio debe ser mayor que 0.")]
    [Display(Name = "Precio unitario")]
    public decimal? Precio { get; set; }

    /// <summary>
    /// Ventana de fechas aceptada, en años hacia adelante.
    ///
    /// DECISIÓN DELIBERADA: no se rechaza toda fecha futura. Los datos del
    /// backup traen ~2.700 ventas fechadas después de hoy, distribuidas de forma
    /// pareja (unas 600 por mes hasta 2026-12). Ese patrón es demasiado regular
    /// para ser un error de carga: son ventas proyectadas o programadas, es
    /// decir datos legítimos. Prohibir la fecha futura dejaría esas 2.700 filas
    /// imposibles de editar desde la app, que es exactamente lo contrario de lo
    /// que debería lograr una validación.
    ///
    /// Lo que sí se rechaza es lo absurdo: fechas anteriores al 2000 (típico
    /// valor centinela) y fechas a más de 5 años vista (típico error de tipeo
    /// en el año). El caso intermedio queda reportado, no bloqueado: el chequeo
    /// 4 de 02_analisis_datos.sql cuantifica las fechas futuras para que el
    /// negocio decida.
    /// </summary>
    private const int HorizonteFuturoEnAnios = 5;

    /// <summary>
    /// Validaciones que no se pueden expresar con un atributo suelto porque
    /// dependen del contexto (la fecha de hoy, en este caso).
    /// </summary>
    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Fecha is not { } fecha)
        {
            yield break;
        }

        if (fecha.Year < 2000)
        {
            yield return new ValidationResult(
                "La fecha parece inválida: debe ser posterior al año 2000.",
                new[] { nameof(Fecha) });
        }

        var limiteSuperior = DateTime.Today.AddYears(HorizonteFuturoEnAnios);
        if (fecha.Date > limiteSuperior)
        {
            yield return new ValidationResult(
                $"La fecha no puede superar el {limiteSuperior:dd-MM-yyyy} " +
                $"({HorizonteFuturoEnAnios} años hacia adelante).",
                new[] { nameof(Fecha) });
        }
    }
}
