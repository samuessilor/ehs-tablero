/**
 * La franja de estado: pregunta a /api/ehs/salud y pinta si el motor responde.
 *
 * Por que no puede "reparar" desde aqui mismo: reparar significa reiniciar un
 * servicio de Windows o un contenedor, y una pagina en el navegador no tiene ni debe
 * tener ese permiso — es el mismo limite que ya separa a ehs_app de un login con
 * privilegios. El enlace "Reparar" que aparece cuando el motor esta abajo no ejecuta
 * nada: dice donde esta el atajo de verdad (el acceso directo del escritorio que
 * instala el paquete de Fase D, reparar.ps1).
 */
/* global Fmt */
(function () {
  'use strict';

  var $ = function (s) {
    return document.querySelector(s);
  };

  function pintar(r) {
    var punto = $('#fePunto');
    var texto = $('#feTexto');
    var reparar = $('#feReparar');
    if (!punto || !texto) return;

    punto.className = 'franja-estado-punto';
    if (r.modo === 'json') {
      punto.classList.add('gris');
      texto.textContent = 'Interinato sin base de datos — publica desde datos.json.';
      reparar.style.display = 'none';
      return;
    }
    if (r.disponible) {
      punto.classList.add('verde');
      texto.textContent =
        'Motor conectado' + (r.tardoMs != null ? ' (' + r.tardoMs + ' ms)' : '') + '.';
      reparar.style.display = 'none';
    } else {
      punto.classList.add('rojo');
      texto.textContent = (r.mensaje || 'El motor no responde.') + ' Usa el acceso directo "Reparar" del escritorio.';
      reparar.style.display = '';
      reparar.textContent = 'Cómo reparar';
      reparar.addEventListener('click', function (ev) {
        ev.preventDefault();
        window.alert(
          'Doble clic en el acceso directo "Reparar EHS" del escritorio (lo deja el ' +
            'instalador). Reinicia el motor de base de datos y vuelve a comprobar que ' +
            'el esquema esté al día. No hace falta abrir ninguna consola.'
        );
      });
    }
  }

  async function comprobar() {
    try {
      var r = await fetch('/api/ehs/salud');
      pintar(await r.json());
    } catch (e) {
      var punto = $('#fePunto');
      var texto = $('#feTexto');
      if (punto) punto.className = 'franja-estado-punto rojo';
      if (texto) texto.textContent = 'No se pudo hablar con el servidor.';
    }
  }

  function iniciar() {
    if (!$('#franjaEstado')) return;
    comprobar();
    // cada 30s: suficiente para que la franja no mienta mucho tiempo si el motor se
    // cae mientras alguien mira la pantalla, sin martillar el servidor con un fetch
    // por segundo en un equipo de escritorio que nadie va a dejar corriendo un mes.
    setInterval(comprobar, 30000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
