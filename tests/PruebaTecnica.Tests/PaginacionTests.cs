using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Tests;

/// <summary>
/// Cubre las reglas de paginación de los filtros y del contenedor de página.
///
/// Son reglas escritas en propiedades con lógica en el setter, que es
/// justamente el tipo de código que se rompe sin que nadie lo note: no falla,
/// simplemente devuelve otra cosa. El techo del tamaño de página, por ejemplo,
/// es lo único que impide que una petición pida un millón de filas.
/// </summary>
public class PaginacionTests
{
    [Fact]
    public void FiltroVentas_PaginaMenorQueUno_SeNormalizaAUno()
    {
        var filtro = new FiltroVentas { Pagina = 0 };

        Assert.Equal(1, filtro.Pagina);
    }

    [Fact]
    public void FiltroVentas_TamanoPaginaSobreElTecho_SeRecortaA200()
    {
        var filtro = new FiltroVentas { TamanoPagina = 1_000_000 };

        Assert.Equal(200, filtro.TamanoPagina);
    }

    [Fact]
    public void FiltroVentas_TamanoPaginaSinSentido_VuelveAlValorPorOmision()
    {
        var filtro = new FiltroVentas { TamanoPagina = 0 };

        Assert.Equal(25, filtro.TamanoPagina);
    }

    [Fact]
    public void FiltroResumen_TamanoPaginaSobreElTecho_SeRecortaA1000()
    {
        var filtro = new FiltroResumen { TamanoPagina = 5_000 };

        Assert.Equal(1000, filtro.TamanoPagina);
    }

    [Fact]
    public void PaginaDe_TotalPaginas_RedondeaHaciaArriba()
    {
        // 101 registros de a 25 son cinco páginas: cuatro llenas y una con un
        // solo registro. Redondear hacia abajo dejaría ese registro inalcanzable.
        var pagina = new PaginaDe<int> { TamanoPagina = 25, TotalRegistros = 101 };

        Assert.Equal(5, pagina.TotalPaginas);
    }

    [Fact]
    public void PaginaDe_EnLaPrimeraPagina_NoHayAnteriorYSiHaySiguiente()
    {
        var pagina = new PaginaDe<int>
        {
            PaginaActual = 1,
            TamanoPagina = 25,
            TotalRegistros = 60
        };

        Assert.False(pagina.HayAnterior);
        Assert.True(pagina.HaySiguiente);
    }
}
