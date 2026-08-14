namespace PruebaTecnica.Web.Models;

/// <summary>
/// Formatos de presentación compartidos por las vistas.
///
/// Estar en un solo lugar evita que una pantalla muestre un monto de una forma
/// y otra pantalla el mismo monto de otra.
/// </summary>
public static class Formatos
{
    /// <summary>
    /// Importes de dinero.
    ///
    /// El "##" final significa "hasta dos decimales, pero sólo si existen":
    ///     200983      ->  $200.983
    ///     12345,67    ->  $12.345,67
    ///
    /// POR QUÉ NO SE USA "C2" (dos decimales siempre)
    /// Ninguno de los 15.088 precios del set tiene centavos: son todos enteros,
    /// y el total general también. Coherente con el peso chileno, que no se
    /// fracciona en la práctica. Mostrar ",00" en cada fila sería ruido, y el
    /// propio enunciado escribe el ejemplo como "totalVentas": 250000.
    ///
    /// POR QUÉ TAMPOCO SE USA "C0" (cero decimales siempre)
    /// Porque redondearía. La columna es decimal(18,2), así que los centavos
    /// son representables aunque hoy no se usen; con "C0" un precio de
    /// 12.345,67 se mostraría como $12.346 y esa diferencia quedaría invisible.
    /// Un formato de presentación no debe ocultar lo que la base sí guarda.
    ///
    /// El separador de miles y el símbolo salen de la cultura configurada en
    /// Program.cs, no están escritos a mano acá.
    /// </summary>
    public const string Moneda = "$#,##0.##";
}
