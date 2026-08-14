namespace PruebaTecnica.Web.Services;

/// <summary>
/// Cómo terminó una operación de la capa de servicios.
///
/// Se usa un resultado explícito en vez de excepciones para los casos
/// esperables ("no existe", "no se puede borrar porque tiene ventas"): esas
/// situaciones son parte del flujo normal, no fallas. Las excepciones quedan
/// reservadas para lo verdaderamente excepcional (se cayó la base), que es
/// justo lo que atrapa el middleware de errores.
///
/// Cada estado tiene una traducción directa a HTTP, que usan tanto los
/// controladores MVC como los de la API.
/// </summary>
public enum EstadoResultado
{
    /// <summary>Todo bien. HTTP 200 / 201.</summary>
    Exito,

    /// <summary>El recurso pedido no existe. HTTP 404.</summary>
    NoEncontrado,

    /// <summary>Los datos recibidos no son válidos. HTTP 400.</summary>
    Invalido,

    /// <summary>La operación choca con una regla de negocio. HTTP 409.</summary>
    Conflicto
}

/// <summary>Resultado de una operación que devuelve un valor.</summary>
public class Resultado<T>
{
    private Resultado(EstadoResultado estado, T? valor, string? mensaje)
    {
        Estado = estado;
        Valor = valor;
        Mensaje = mensaje;
    }

    public EstadoResultado Estado { get; }
    public T? Valor { get; }
    public string? Mensaje { get; }

    public bool EsExito => Estado == EstadoResultado.Exito;

    public static Resultado<T> Exito(T valor) =>
        new(EstadoResultado.Exito, valor, null);

    public static Resultado<T> NoEncontrado(string mensaje) =>
        new(EstadoResultado.NoEncontrado, default, mensaje);

    public static Resultado<T> Invalido(string mensaje) =>
        new(EstadoResultado.Invalido, default, mensaje);

    public static Resultado<T> Conflicto(string mensaje) =>
        new(EstadoResultado.Conflicto, default, mensaje);
}

/// <summary>Resultado de una operación que no devuelve valor (borrar, actualizar).</summary>
public class Resultado
{
    private Resultado(EstadoResultado estado, string? mensaje)
    {
        Estado = estado;
        Mensaje = mensaje;
    }

    public EstadoResultado Estado { get; }
    public string? Mensaje { get; }

    public bool EsExito => Estado == EstadoResultado.Exito;

    public static Resultado Exito() => new(EstadoResultado.Exito, null);
    public static Resultado NoEncontrado(string mensaje) => new(EstadoResultado.NoEncontrado, mensaje);
    public static Resultado Invalido(string mensaje) => new(EstadoResultado.Invalido, mensaje);
    public static Resultado Conflicto(string mensaje) => new(EstadoResultado.Conflicto, mensaje);
}
