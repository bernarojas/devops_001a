using System.Globalization;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.AspNetCore.Routing;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Tests;

/// <summary>
/// Cubre el enlazador de decimales.
///
/// Es la prueba más valiosa del conjunto, porque el defecto que este código
/// evita es silencioso: un precio de 12.345,67 guardado como 1.234.567 no
/// dispara ninguna validación —1234567 es un decimal perfectamente válido— y
/// sólo se descubre cuando alguien revisa un total que no cuadra.
/// </summary>
public class EnlaceDecimalInvarianteTests
{
    /// <summary>
    /// Arma el contexto mínimo que necesita un IModelBinder para ejecutarse
    /// fuera de una petición HTTP real.
    /// </summary>
    private static DefaultModelBindingContext ContextoPara(string? valorEnviado)
    {
        var valores = new RouteValueDictionary();
        if (valorEnviado is not null)
        {
            valores["Precio"] = valorEnviado;
        }

        return new DefaultModelBindingContext
        {
            ModelMetadata = new EmptyModelMetadataProvider()
                .GetMetadataForType(typeof(decimal?)),
            ModelName = "Precio",
            ModelState = new ModelStateDictionary(),
            ValueProvider = new RouteValueProvider(BindingSource.Form, valores)
        };
    }

    [Fact]
    public async Task ValorDelNavegador_ConPunto_SeLeeComoDecimalConComa()
    {
        // Lo que manda un <input type="number">, siempre, sin importar el idioma.
        var contexto = ContextoPara("12345.67");

        await new EnlaceDecimalInvariante().BindModelAsync(contexto);

        Assert.True(contexto.Result.IsModelSet);
        Assert.Equal(12345.67m, contexto.Result.Model);
    }

    [Fact]
    public async Task ValorTecleadoAMano_ConComa_SeLeeIgualBajoCulturaChilena()
    {
        var culturaPrevia = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = new CultureInfo("es-CL");

        try
        {
            // Este valor debe FALLAR el primer intento (invariante sin miles) y
            // acertar en el segundo. Si el primer intento admitiera separador de
            // miles, la coma se leería como tal y daría 1.234.567.
            var contexto = ContextoPara("12345,67");

            await new EnlaceDecimalInvariante().BindModelAsync(contexto);

            Assert.True(contexto.Result.IsModelSet);
            Assert.Equal(12345.67m, contexto.Result.Model);
        }
        finally
        {
            CultureInfo.CurrentCulture = culturaPrevia;
        }
    }

    [Fact]
    public async Task TextoNoNumerico_DejaErrorEnElEstadoDelModelo()
    {
        var contexto = ContextoPara("mil quinientos");

        await new EnlaceDecimalInvariante().BindModelAsync(contexto);

        Assert.False(contexto.Result.IsModelSet);
        Assert.False(contexto.ModelState.IsValid);
    }
}
