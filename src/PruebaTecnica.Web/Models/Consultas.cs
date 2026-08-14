using System.ComponentModel.DataAnnotations;

namespace PruebaTecnica.Web.Models;

/// <summary>
/// Página de resultados. La tabla Ventas tiene ~15.000 filas: devolverlas todas
/// de una vez es lento en la web e innecesario en la API.
/// </summary>
public class PaginaDe<T>
{
    public IReadOnlyList<T> Items { get; init; } = Array.Empty<T>();
    public int PaginaActual { get; init; } = 1;
    public int TamanoPagina { get; init; } = 25;
    public int TotalRegistros { get; init; }

    public int TotalPaginas =>
        TamanoPagina <= 0 ? 0 : (int)Math.Ceiling(TotalRegistros / (double)TamanoPagina);

    public bool HayAnterior => PaginaActual > 1;
    public bool HaySiguiente => PaginaActual < TotalPaginas;
}

/// <summary>Filtros y paginación para el listado de ventas.</summary>
public class FiltroVentas
{
    private const int TamanoMaximo = 200;

    [Display(Name = "Compañía")]
    public string? Compania { get; set; }

    [Display(Name = "Producto")]
    public string? Producto { get; set; }

    [Display(Name = "Desde")]
    [DataType(DataType.Date)]
    public DateTime? Desde { get; set; }

    [Display(Name = "Hasta")]
    [DataType(DataType.Date)]
    public DateTime? Hasta { get; set; }

    /// <summary>Muestra sólo las filas que 02_analisis_datos.sql marcaría como sospechosas.</summary>
    [Display(Name = "Sólo registros con anomalías")]
    public bool SoloAnomalias { get; set; }

    private int _pagina = 1;
    public int Pagina
    {
        get => _pagina;
        set => _pagina = value < 1 ? 1 : value;   // una página 0 o negativa no existe
    }

    private int _tamanoPagina = 25;
    public int TamanoPagina
    {
        get => _tamanoPagina;
        set => _tamanoPagina = value switch
        {
            < 1            => 25,             // valor sin sentido: se usa el por defecto
            > TamanoMaximo => TamanoMaximo,   // techo, para que nadie pida 1.000.000 de filas
            _              => value
        };
    }
}

/// <summary>Filtros del resumen mensual, compartidos por la vista MVC y la API.</summary>
public class FiltroResumen
{
    [Display(Name = "Compañía")]
    public string? Compania { get; set; }

    [Display(Name = "Producto")]
    public string? Producto { get; set; }

    /// <summary>
    /// Período: se espera el primer día del mes (2024-01-01). Si llega cualquier
    /// otro día del mes, el servicio lo normaliza al día 1 en vez de no devolver
    /// nada, que sería un resultado desconcertante para quien consume la API.
    /// </summary>
    [Display(Name = "Período")]
    [DataType(DataType.Date)]
    public DateOnly? Periodo { get; set; }

    private int _pagina = 1;
    public int Pagina
    {
        get => _pagina;
        set => _pagina = value < 1 ? 1 : value;
    }

    private int _tamanoPagina = 50;
    public int TamanoPagina
    {
        get => _tamanoPagina;
        set => _tamanoPagina = value switch
        {
            < 1     => 50,
            > 1000  => 1000,
            _       => value
        };
    }
}
