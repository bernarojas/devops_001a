// ============================================================================
//  Comportamiento del lado del cliente.
//
//  Deliberadamente mínimo: la aplicación funciona sin JavaScript. Los datos se
//  renderizan en el servidor, las tablas y los gráficos llegan dibujados, y los
//  formularios envían de forma tradicional. Lo de acá es sólo mejora encima.
// ============================================================================

(function () {
    'use strict';

    document.addEventListener('DOMContentLoaded', function () {

        // --- Tooltips ------------------------------------------------------
        // Se usa el componente de Bootstrap, que ya viene en el bundle que la
        // aplicación carga: no agrega ninguna dependencia nueva.
        //
        // Frente al tooltip nativo del navegador (atributo title a secas), este
        // aparece de inmediato, admite varias líneas con formato, se reposiciona
        // solo cuando queda contra el borde de la pantalla, y responde al foco
        // por teclado además del mouse.
        //
        // Si Bootstrap no cargara, los elementos conservan su atributo title y
        // el navegador muestra el tooltip nativo. Se degrada, no se rompe.
        if (window.bootstrap && window.bootstrap.Tooltip) {
            var elementos = document.querySelectorAll('[data-bs-toggle="tooltip"]');

            Array.prototype.forEach.call(elementos, function (el) {
                new bootstrap.Tooltip(el, {
                    container: 'body',   // evita que lo recorte el overflow del SVG o de la tarjeta
                    delay: { show: 60, hide: 40 },
                    trigger: 'hover focus'
                });
            });
        }
    });
})();
