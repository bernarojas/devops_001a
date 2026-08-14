using System.Globalization;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace PruebaTecnica.Web.Models;

/// <summary>
/// Enlaza valores decimales de los formularios usando cultura invariante.
///
/// EL PROBLEMA QUE RESUELVE
/// La aplicación se muestra en español de Chile, donde el separador decimal es
/// la coma. Pero el estándar HTML obliga a que un &lt;input type="number"&gt;
/// envíe siempre el valor con PUNTO como separador decimal, sin importar el
/// idioma del navegador o del servidor.
///
/// Por defecto, ASP.NET Core interpreta los valores de formulario con la cultura
/// actual. Con es-CL, el "12345.67" que manda el navegador se lee como si el
/// punto fuera separador de miles: se guarda 1.234.567. Un error de factor 100,
/// silencioso, que no dispara ninguna validación porque 1234567 es un decimal
/// perfectamente válido.
///
/// LA SOLUCIÓN
/// Se intenta primero con cultura invariante, que es el formato en el que el
/// navegador realmente envía el dato. Si eso falla, se reintenta con la cultura
/// actual, para no romper si el valor llega tecleado a mano como "12345,67"
/// (por ejemplo desde un cliente HTTP o un input de texto).
///
/// La API JSON no necesita esto: System.Text.Json ya deserializa números con
/// formato invariante por definición. El problema era exclusivo de los
/// formularios.
/// </summary>
public class EnlaceDecimalInvariante : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext contexto)
    {
        ArgumentNullException.ThrowIfNull(contexto);

        var nombre = contexto.ModelName;
        var resultado = contexto.ValueProvider.GetValue(nombre);

        if (resultado == ValueProviderResult.None)
        {
            return Task.CompletedTask;   // el campo no vino: lo maneja el binder por defecto
        }

        contexto.ModelState.SetModelValue(nombre, resultado);

        var texto = resultado.FirstValue;
        var tipoSubyacente = Nullable.GetUnderlyingType(contexto.ModelType) ?? contexto.ModelType;
        var esNullable = Nullable.GetUnderlyingType(contexto.ModelType) is not null;

        if (string.IsNullOrWhiteSpace(texto))
        {
            // Vacío es válido si el tipo lo admite; si no, lo reporta [Required].
            if (esNullable)
            {
                contexto.Result = ModelBindingResult.Success(null);
            }
            return Task.CompletedTask;
        }

        if (TryConvertir(texto, tipoSubyacente, out var valor))
        {
            contexto.Result = ModelBindingResult.Success(valor);
        }
        else
        {
            contexto.ModelState.TryAddModelError(
                nombre,
                $"'{texto}' no es un número válido.");
        }

        return Task.CompletedTask;
    }

    private static bool TryConvertir(string texto, Type tipo, out object? valor)
    {
        // Orden e ESTILOS deliberados, y los dos importan.
        //
        // 1) Invariante SIN AllowThousands. Es el formato que manda el navegador
        //    ("12345.67"). Excluir el separador de miles es lo que hace que un
        //    "12345,67" tecleado a mano FALLE acá y caiga al intento siguiente.
        //    Con AllowThousands activo, la coma se tomaría como separador de
        //    miles y "12345,67" se convertiría en 1234567: el mismo error de
        //    factor 100 que este binder existe para evitar, sólo que al revés.
        //
        // 2) Cultura actual CON AllowThousands, para aceptar tanto "12345,67"
        //    como "1.234.567" tal como los escribiría una persona en Chile.
        (CultureInfo Cultura, NumberStyles Estilos)[] intentos =
        [
            (CultureInfo.InvariantCulture, NumberStyles.Float),
            (CultureInfo.CurrentCulture,   NumberStyles.Float | NumberStyles.AllowThousands)
        ];

        foreach (var (cultura, estilos) in intentos)
        {
            if (tipo == typeof(decimal) && decimal.TryParse(texto, estilos, cultura, out var d))
            {
                valor = d;
                return true;
            }

            if (tipo == typeof(double) && double.TryParse(texto, estilos, cultura, out var db))
            {
                valor = db;
                return true;
            }

            if (tipo == typeof(float) && float.TryParse(texto, estilos, cultura, out var f))
            {
                valor = f;
                return true;
            }
        }

        valor = null;
        return false;
    }
}

/// <summary>
/// Aplica <see cref="EnlaceDecimalInvariante"/> a todas las propiedades
/// decimales, en lugar de tener que decorarlas una por una y confiar en que
/// nadie olvide hacerlo en la próxima que se agregue.
/// </summary>
public class ProveedorEnlaceDecimalInvariante : IModelBinderProvider
{
    public IModelBinder? GetBinder(ModelBinderProviderContext contexto)
    {
        ArgumentNullException.ThrowIfNull(contexto);

        var tipo = Nullable.GetUnderlyingType(contexto.Metadata.ModelType)
                   ?? contexto.Metadata.ModelType;

        return tipo == typeof(decimal) || tipo == typeof(double) || tipo == typeof(float)
            ? new EnlaceDecimalInvariante()
            : null;
    }
}
