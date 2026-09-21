using System.ComponentModel.DataAnnotations;
using PruebaTecnica.Web.Models;

namespace PruebaTecnica.Tests;

/// <summary>
/// Cubre la validación de entrada de una venta.
///
/// Esta clase es la frontera que impide que vuelvan a entrar las anomalías que
/// 02_analisis_datos.sql encontró en el histórico. Las pruebas comprueban tanto
/// lo que debe rechazarse como lo que debe aceptarse: la ventana de fechas
/// futuras es una decisión deliberada, y una prueba que sólo verificara
/// rechazos dejaría pasar un endurecimiento accidental de esa regla.
/// </summary>
public class VentaInputTests
{
    private static IReadOnlyList<ValidationResult> Validar(VentaInput entrada)
    {
        var resultados = new List<ValidationResult>();
        Validator.TryValidateObject(
            entrada,
            new ValidationContext(entrada),
            resultados,
            validateAllProperties: true);
        return resultados;
    }

    /// <summary>Una venta correcta, sobre la que cada prueba cambia un solo campo.</summary>
    private static VentaInput VentaValida() => new()
    {
        Compania = "Comercial Andes",
        IdProducto = 1,
        Fecha = new DateTime(2024, 6, 15),
        Cantidad = 10,
        Precio = 19_990m
    };

    [Fact]
    public void VentaCorrecta_NoProduceErrores()
    {
        Assert.Empty(Validar(VentaValida()));
    }

    [Fact]
    public void CantidadNegativa_EsRechazada()
    {
        var entrada = VentaValida();
        entrada.Cantidad = -5;

        Assert.Contains(Validar(entrada),
            e => e.MemberNames.Contains(nameof(VentaInput.Cantidad)));
    }

    [Fact]
    public void PrecioEnCero_EsRechazado()
    {
        var entrada = VentaValida();
        entrada.Precio = 0m;

        Assert.Contains(Validar(entrada),
            e => e.MemberNames.Contains(nameof(VentaInput.Precio)));
    }

    [Fact]
    public void FechaAnteriorAlAno2000_EsRechazada()
    {
        // Valor centinela típico de una carga defectuosa.
        var entrada = VentaValida();
        entrada.Fecha = new DateTime(1900, 1, 1);

        Assert.Contains(Validar(entrada),
            e => e.MemberNames.Contains(nameof(VentaInput.Fecha)));
    }

    [Fact]
    public void FechaMuyLejanaEnElFuturo_EsRechazada()
    {
        // Error de tipeo en el año, más allá del horizonte de cinco años.
        var entrada = VentaValida();
        entrada.Fecha = DateTime.Today.AddYears(10);

        Assert.Contains(Validar(entrada),
            e => e.MemberNames.Contains(nameof(VentaInput.Fecha)));
    }

    [Fact]
    public void FechaFuturaDentroDelHorizonte_EsAceptada()
    {
        // Decisión deliberada: las ventas proyectadas son datos legítimos y
        // deben poder editarse desde la aplicación.
        var entrada = VentaValida();
        entrada.Fecha = DateTime.Today.AddMonths(6);

        Assert.Empty(Validar(entrada));
    }
}
