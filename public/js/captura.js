/**
 * El cliente de la captura. JavaScript plano, sin framework, igual que el tablero.
 *
 * Hace tres cosas y ninguna es calcular:
 *   1. avisa al teclear de lo que ya se sabe que esta mal, sin ir al servidor
 *   2. arma el lote y lo manda
 *   3. enseña el reparto que devuelve el servidor: que entro, que se aparto, que hay
 *      que confirmar
 *
 * Lo que NO hace, a proposito: decidir si un valor entra. Eso lo deciden el servidor y
 * despues el procedimiento. Lo de aqui es cortesia para quien teclea, no una autoridad;
 * si alguien desactiva este archivo desde la consola del navegador no consigue meter un
 * numero que el servidor no acepte.
 */
(function () {
  'use strict';

  var $ = function (s, raiz) {
    return (raiz || document).querySelector(s);
  };
  var $$ = function (s, raiz) {
    return Array.prototype.slice.call((raiz || document).querySelectorAll(s));
  };

  /* Mismo rango que src/validacion.js y que ehs.dim_magnitud. Esta repetido aqui
     porque el navegador no puede requerir el modulo del servidor; la compuerta
     analisis/verificar_validacion_pareja.py comprueba que los tres no se separen. */
  var RANGO = {
    agua_m3: [110, 913.5],
    energia_kwh: [21827, 282792],
    residuo_peligroso_kg: [15, 21060],
    residuo_aprovechable_kg: [400, 28701],
    residuo_ordinario_kg: [133, 6744],
    unidades_buenas: [29258.5, 165361.5],
    accidentes_dafw: [0, 1.5],
    horas_fijos: [19423.5, 161880],
    horas_temp: [0, 14982],
  };

  var MESES = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  function aNumero(texto) {
    var s = String(texto == null ? '' : texto)
      .trim()
      .replace(',', '.');
    if (s === '') return null;
    if (!/^-?\d+(\.\d+)?$/.test(s)) return null;
    var n = Number(s);
    return isFinite(n) ? n : null;
  }

  /** Devuelve '' si esta bien, 'mal' si es imposible, 'raro' si solo es improbable. */
  function juzgar(magnitud, texto) {
    if (String(texto).trim() === '') return '';
    var n = aNumero(texto);
    if (n === null) return 'mal';
    if (n < 0) return 'mal';
    var r = RANGO[magnitud];
    if (!r) return '';
    if (n > r[1]) return 'raro';
    if (n > 0 && n < r[0]) return 'raro';
    return '';
  }

  /* ------------------------------------------------------------------ la rejilla */

  function celdas() {
    return $$('.cap-celda');
  }

  function marcarCelda(inp) {
    var estado = juzgar(inp.dataset.magnitud, inp.value);
    inp.classList.remove('mal', 'raro');
    var marca = inp.parentNode.querySelector('.cap-marca');
    if (estado === 'mal') {
      inp.classList.add('mal');
      marca.textContent = 'no válido';
      marca.className = 'cap-marca mal';
    } else if (estado === 'raro') {
      inp.classList.add('raro');
      marca.textContent = 'fuera de rango';
      marca.className = 'cap-marca raro';
    } else {
      marca.textContent = '';
      marca.className = 'cap-marca';
    }
  }

  function contar() {
    var conDato = celdas().filter(function (i) {
      return String(i.value).trim() !== '';
    });
    var malas = conDato.filter(function (i) {
      return i.classList.contains('mal');
    }).length;
    var raras = conDato.filter(function (i) {
      return i.classList.contains('raro');
    }).length;

    var t;
    if (!conDato.length) {
      t = 'ninguna celda con dato';
    } else {
      t = conDato.length + (conDato.length === 1 ? ' celda' : ' celdas') + ' con dato';
      if (malas) t += ' · ' + malas + ' sin validez';
      if (raras) t += ' · ' + raras + ' fuera de rango';
    }
    $('#conteo').textContent = t;
    $('#bEnviar').disabled = conDato.length === 0;
    return { conDato: conDato, malas: malas, raras: raras };
  }

  /** Arma el lote a partir de lo tecleado. Las celdas vacias NO viajan: no son ceros. */
  function armarLote() {
    var anio = Number($('#fAnio').value);
    var mes = Number($('#fMes').value);
    return celdas()
      .filter(function (i) {
        return String(i.value).trim() !== '';
      })
      .map(function (i) {
        return {
          anio: anio,
          mes: mes,
          sitio: i.dataset.sitio,
          magnitud: i.dataset.magnitud,
          valor: String(i.value).trim(),
        };
      });
  }

  /* ------------------------------------------------------------------- el envio */

  /* Confirmar un atipico REARMA el lote leyendo la rejilla otra vez, en vez de reenviar
     una copia guardada. Si entre el primer envio y la confirmacion alguien corrigio una
     celda, lo que se captura es lo que esta en pantalla — que es lo que esa persona
     cree estar confirmando. */
  async function enviar(confirmarAtipicos) {
    var quien = String($('#fQuien').value || '').trim();
    if (!quien) {
      pintarError('Falta escribir quién captura. Sin eso la bitácora no puede nombrar a nadie.');
      $('#fQuien').focus();
      return;
    }

    var filas = armarLote();
    if (!filas.length) {
      pintarError('No hay ninguna celda con dato.');
      return;
    }
    var boton = $('#bEnviar');
    boton.disabled = true;
    boton.textContent = 'Enviando…';
    $('#viva').textContent = 'Enviando ' + filas.length + ' lecturas.';

    try {
      var r = await fetch('/api/ehs/captura', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          filas: filas,
          capturadoPor: quien,
          confirmarAtipicos: !!confirmarAtipicos,
        }),
      });
      var cuerpo = await r.json();
      if (!r.ok) {
        pintarError(cuerpo.mensaje || 'El servidor rechazó la petición.');
        return;
      }
      pintarResultado(cuerpo);
    } catch (e) {
      pintarError('No se pudo hablar con el servidor: ' + e.message);
    } finally {
      boton.disabled = false;
      boton.textContent = 'Revisar y capturar';
      contar();
    }
  }

  /* ---------------------------------------------------------------- el resultado */

  function pintarError(mensaje) {
    $('#resultado').innerHTML =
      '<div class="cap-res cap-res-mal"><p>' + Fmt.esc(mensaje) + '</p></div>';
    $('#viva').textContent = mensaje;
  }

  function tablaFilas(filas, campo, clase) {
    return (
      '<table class="cap-res-tabla ' +
      clase +
      '"><tbody>' +
      filas
        .map(function (f) {
          return (
            '<tr><td class="cap-res-donde">' +
            Fmt.esc(f.sitio) +
            ' · ' +
            Fmt.esc(f.magnitud) +
            '</td><td class="cap-res-valor">' +
            Fmt.esc(f.valor === null || f.valor === '' ? '(vacío)' : f.valor) +
            '</td><td>' +
            Fmt.esc(f[campo]) +
            '</td></tr>'
          );
        })
        .join('') +
      '</tbody></table>'
    );
  }

  function pintarResultado(r) {
    var partes = [];
    var simulado = r.persistido === false;

    partes.push(
      '<div class="cap-res ' + (r.rechazadas.length ? 'cap-res-parcial' : 'cap-res-bien') + '">'
    );
    partes.push(
      '<p class="cap-res-titular">' +
        (simulado
          ? '<strong>' + r.grabadas + '</strong> lecturas habrían entrado'
          : '<strong>' + r.grabadas + '</strong> lecturas grabadas') +
        (r.rechazadas.length ? ' · <strong>' + r.rechazadas.length + '</strong> apartadas' : '') +
        (r.pendientes ? ' · <strong>' + r.pendientes + '</strong> esperando confirmación' : '') +
        (r.cargaId ? ' <span class="cap-res-carga">carga #' + Fmt.esc(r.cargaId) + '</span>' : '') +
        '</p>'
    );
    if (r.aviso) partes.push('<p class="cap-res-aviso">' + Fmt.esc(r.aviso) + '</p>');
    partes.push('</div>');

    if (r.rechazadas.length) {
      partes.push('<h3 class="cap-res-h">Apartadas · hay que corregirlas en el origen</h3>');
      partes.push(
        '<p class="cap-res-p">Esto no entró y no entrará mientras siga así. No se pierde: ' +
          'queda registrado con su motivo (R.5.3.5).</p>'
      );
      partes.push(tablaFilas(r.rechazadas, 'motivo', 'mal'));
    }

    if (r.advertidas.length && r.pendientes) {
      partes.push('<h3 class="cap-res-h">Fuera de rango · míralas antes de confirmar</h3>');
      partes.push(
        '<p class="cap-res-p">Estos valores son posibles pero se salen de lo que se ha ' +
          'visto históricamente. Pueden ser un cero de más al teclear, y pueden ser reales: ' +
          'una fuga de agua se ve exactamente así. Quien sabe cuál es de las dos es el área.</p>'
      );
      partes.push(tablaFilas(r.advertidas, 'advertencia', 'raro'));
      partes.push(
        '<div class="cap-acciones"><button type="button" id="bConfirmar" class="cap-boton">' +
          'Los revisé, son correctos: capturar</button></div>'
      );
    }

    if (r.sentencia) {
      partes.push('<h3 class="cap-res-h">Lo que se ejecutaría contra el servidor de IT</h3>');
      partes.push('<pre class="cap-sql">' + Fmt.esc(r.sentencia) + '</pre>');
    }

    $('#resultado').innerHTML = partes.join('');
    $('#viva').textContent =
      r.grabadas +
      ' lecturas, ' +
      r.rechazadas.length +
      ' apartadas, ' +
      r.pendientes +
      ' por confirmar.';

    var bc = $('#bConfirmar');
    if (bc) {
      bc.addEventListener('click', function () {
        enviar(true);
      });
    }
    $('#resultado').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  /* ----------------------------------------------------------------------- inicio */

  function sincronizarTitulo() {
    var mes = MESES[Number($('#fMes').value) - 1] || '';
    $('#subMes').textContent = mes + ' de ' + $('#fAnio').value;
  }

  function iniciar() {
    // el mes que se captura es normalmente el que acaba de cerrar, no el corriente
    var hoy = new Date();
    var mesPrevio = hoy.getMonth() === 0 ? 12 : hoy.getMonth();
    $('#fMes').value = String(mesPrevio);
    if (hoy.getMonth() === 0) $('#fAnio').value = String(hoy.getFullYear() - 1);

    celdas().forEach(function (inp) {
      inp.addEventListener('input', function () {
        marcarCelda(inp);
        contar();
      });
      // Enter baja a la misma columna en vez de enviar: se captura por sitio, no por fila
      inp.addEventListener('keydown', function (ev) {
        if (ev.key !== 'Enter') return;
        ev.preventDefault();
        var mismos = celdas().filter(function (o) {
          return o.dataset.sitio === inp.dataset.sitio;
        });
        var i = mismos.indexOf(inp);
        if (i >= 0 && i + 1 < mismos.length) mismos[i + 1].focus();
      });
    });

    $('#bEnviar').addEventListener('click', function () {
      enviar(false);
    });
    $('#bLimpiar').addEventListener('click', function () {
      celdas().forEach(function (i) {
        i.value = '';
        marcarCelda(i);
      });
      $('#resultado').innerHTML = '';
      contar();
    });
    $('#fMes').addEventListener('change', sincronizarTitulo);
    $('#fAnio').addEventListener('input', sincronizarTitulo);

    sincronizarTitulo();
    contar();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
