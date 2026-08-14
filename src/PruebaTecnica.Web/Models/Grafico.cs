using System.Globalization;

namespace PruebaTecnica.Web.Models;

/// <summary>Un punto de una serie: una etiqueta y su valor.</summary>
public record PuntoGrafico(string Etiqueta, decimal Valor, string? Detalle = null);

/// <summary>
/// Datos y opciones de un gráfico de barras.
///
/// Los gráficos se dibujan como SVG generado en el servidor, sin librería de
/// terceros. Motivos:
///
///   - Coherencia: toda la solución es autocontenida (tipografía del sistema,
///     iconos SVG en línea, Bootstrap local). Agregar 200 KB de JavaScript para
///     tres gráficos rompería esa línea.
///   - Robustez: el gráfico llega dibujado en el HTML. No hay estado de carga,
///     ni parpadeo, ni un lienzo vacío si el JavaScript falla.
///   - Impresión: al pasar la página a PDF el gráfico sale, porque ya es parte
///     del documento y no algo que se pinta después en un canvas.
///
/// El costo asumido es que no hay interactividad más allá del tooltip nativo
/// del navegador. Para explorar los datos está Power BI, que es justamente el
/// entregable pensado para eso.
/// </summary>
public class DatosGraficoBarras
{
    public required IReadOnlyList<PuntoGrafico> Puntos { get; init; }

    /// <summary>Unidad en la que se rotulan los valores. Ej: "millones de $".</summary>
    public string UnidadEjeY { get; init; } = "";

    /// <summary>Divisor aplicado a los valores antes de rotularlos (1.000.000 = millones).</summary>
    public decimal Divisor { get; init; } = 1_000_000m;

    /// <summary>Con 37 barras no caben 37 etiquetas: se muestra una de cada N.</summary>
    public int CadaCuantasEtiquetas { get; init; } = 1;

    /// <summary>
    /// Dimensiones del lienzo SVG, en unidades del viewBox.
    ///
    /// Importan más de lo que parece. El SVG conserva su proporción y se escala
    /// para ocupar el ancho disponible, así que el lienzo determina dos cosas:
    ///
    ///   1. La altura final. Un lienzo de 1000x300 dentro de un contenedor de
    ///      1600 px se dibuja con 480 px de alto — demasiado.
    ///   2. El tamaño real del texto. Si el lienzo es más angosto que el
    ///      contenedor, todo se agranda; si es más ancho, todo se encoge. Un
    ///      rótulo de 11 unidades puede terminar viéndose a 8 px o a 18 px.
    ///
    /// Por eso cada pantalla declara un lienzo parecido al ancho real donde va
    /// el gráfico: así la escala queda cerca de 1 y el texto se ve del mismo
    /// tamaño en todas partes, con la altura bajo control.
    /// </summary>
    public double AnchoLienzo { get; init; } = 1000;

    public double AltoLienzo { get; init; } = 300;

    public string? IdAccesible { get; init; }
}

/// <summary>
/// Utilidades de dibujo compartidas por los gráficos.
/// </summary>
public static class Svg
{
    /// <summary>
    /// Convierte un número a texto para un atributo SVG.
    ///
    /// SIEMPRE con cultura invariante. Es obligatorio: la aplicación corre en
    /// es-CL, donde el separador decimal es la coma, y un atributo como
    /// x="12,5" es inválido en SVG — el navegador descarta el elemento y el
    /// gráfico aparece roto o vacío. Es la misma clase de error que el de los
    /// precios en los formularios, pero en sentido contrario.
    /// </summary>
    public static string N(double valor) =>
        valor.ToString("0.###", CultureInfo.InvariantCulture);

    /// <summary>Etiqueta compacta para el eje: 1500 -> "1.500", 0,5 -> "0,5".</summary>
    public static string Etiqueta(decimal valor) =>
        valor >= 10 ? valor.ToString("N0") : valor.ToString("0.#");
}
