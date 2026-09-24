/**
 * El cliente de "Consultar y corregir". Reusa /api/ehs/detalle (lectura ya publicada
 * en el resto de la app) para mostrar qué hay, y manda la corrección a
 * /api/ehs/correccion. No decide si un valor entra: eso lo deciden el servidor y
 * después el procedimiento, igual que en captura.js.
 */
/* global Fmt */
(function () {
  'use strict';

  var $ = function (s, raiz) {
    return (raiz || document).querySelector(s);
  };

  var MAGNITUDES = window.EHS_MAGNITUDES || [];
  var porId = {};
  MAGNITUDES.forEach(function (m) {
    porId[m.id] = m;
  });

  var estado = { anio: null, mes: null, sitio: null, magnitud: null, valorActual: null };

  /* --------------------------------------------------------------- 01 · consultar */

  async function consultar() {
    var anio = Number($('#cAnio').value);
    var mes = Number($('#cMes').value);
    var sitio = $('#cSitio').value;
    estado.anio = anio;
    estado.mes = mes;
    estado.sitio = sitio;

    $('#subConsulta').textContent = 'Consultando…';
    try {
      var r = await fetch('/api/ehs/detalle?anio=' + anio);
      var cuerpo = await r.json();
      if (!r.ok) {
        $('#subConsulta').textContent = cuerpo.mensaje || 'No se pudo consultar.';
        return;
      }
      var fila = (cuerpo.filas || []).find(function (f) {
        return Number(f.mes) === mes && f.sitio === sitio;
      });
      pintarValores(fila);
    } catch (e) {
      $('#subConsulta').textContent = 'No se pudo hablar con el servidor: ' + e.message;
    }
  }

  function pintarValores(fila) {
    var cuerpo = $('#cuerpoValores');
    cuerpo.innerHTML = '';
    MAGNITUDES.forEach(function (m) {
      var valor = fila ? fila[m.id] : null;
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<th scope="row"><span class="cap-mag">' +
        Fmt.esc(m.etiqueta) +
        '</span><span class="cap-uni">' +
        Fmt.esc(m.unidad) +
        '</span></th>' +
        '<td>' +
        (valor === null || valor === undefined ? '<em>sin captura</em>' : Fmt.esc(valor)) +
        '</td>' +
        '<td></td>';
      var celdaBoton = tr.lastElementChild;
      var boton = document.createElement('button');
      boton.type = 'button';
      boton.className = 'cap-boton cap-boton-suave';
      boton.textContent =
        valor === null || valor === undefined ? 'sin valor que corregir' : 'Corregir';
      boton.disabled = valor === null || valor === undefined;
      boton.addEventListener('click', function () {
        abrirCorreccion(m, valor);
      });
      celdaBoton.appendChild(boton);
      cuerpo.appendChild(tr);
    });

    $('#secValores').style.display = '';
    var mesNombre = Fmt.mesLargo[estado.mes - 1];
    $('#subConsulta').textContent = mesNombre + ' ' + estado.anio + ' · ' + estado.sitio;
  }

  /* --------------------------------------------------------------- 02 · corregir */

  function abrirCorreccion(magnitud, valorActual) {
    estado.magnitud = magnitud.id;
    estado.valorActual = valorActual;
    $('#magACorregir').textContent = magnitud.etiqueta;
    $('#subCorregir').textContent = 'Valor actual: ' + Fmt.esc(valorActual) + ' ' + magnitud.unidad;
    $('#corValor').value = valorActual;
    $('#corMotivo').value = '';
    $('#resultadoCorreccion').innerHTML = '';
    $('#secCorregir').style.display = '';
    $('#secCorregir').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    $('#corValor').focus();
  }

  function cerrarCorreccion() {
    $('#secCorregir').style.display = 'none';
    estado.magnitud = null;
  }

  async function enviarCorreccion() {
    var quien = String($('#corQuien').value || '').trim();
    if (!quien) {
      pintarErrorCorreccion('Falta escribir quién corrige.');
      $('#corQuien').focus();
      return;
    }
    var motivo = String($('#corMotivo').value || '').trim();
    var boton = $('#bCorregir');
    boton.disabled = true;
    boton.textContent = 'Corrigiendo…';

    try {
      var r = await fetch('/api/ehs/correccion', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          anio: estado.anio,
          mes: estado.mes,
          sitio: estado.sitio,
          magnitud: estado.magnitud,
          valor: $('#corValor').value,
          motivo: motivo,
          corregidoPor: quien,
        }),
      });
      var cuerpo = await r.json();
      if (!r.ok) {
        pintarErrorCorreccion(cuerpo.mensaje || 'El servidor rechazó la corrección.');
        return;
      }
      pintarResultadoCorreccion(cuerpo);
    } catch (e) {
      pintarErrorCorreccion('No se pudo hablar con el servidor: ' + e.message);
    } finally {
      boton.disabled = false;
      boton.textContent = 'Corregir';
    }
  }

  function pintarErrorCorreccion(mensaje) {
    $('#resultadoCorreccion').innerHTML =
      '<div class="cap-res cap-res-mal"><p>' + Fmt.esc(mensaje) + '</p></div>';
    $('#viva').textContent = mensaje;
  }

  function pintarResultadoCorreccion(r) {
    var partes = [];
    var simulado = r.persistido === false;
    if (simulado) {
      partes.push(
        '<div class="cap-res cap-res-parcial"><p class="cap-res-titular">Corrección validada, no guardada</p>'
      );
      if (r.aviso) partes.push('<p class="cap-res-aviso">' + Fmt.esc(r.aviso) + '</p>');
      partes.push('</div>');
      if (r.sentencia) {
        partes.push('<h3 class="cap-res-h">Lo que se ejecutaría contra el servidor de IT</h3>');
        partes.push('<pre class="cap-sql">' + Fmt.esc(r.sentencia) + '</pre>');
      }
    } else if (r.corregida) {
      partes.push(
        '<div class="cap-res cap-res-bien"><p class="cap-res-titular">Corrección grabada.</p></div>'
      );
    } else {
      partes.push(
        '<div class="cap-res cap-res-parcial"><p class="cap-res-titular">El valor nuevo es igual al que ya había: no se archivó nada.</p></div>'
      );
    }
    $('#resultadoCorreccion').innerHTML = partes.join('');
    $('#viva').textContent = r.corregida ? 'Corrección grabada.' : 'Sin cambios.';

    if (r.corregida) {
      consultar();
      cargarHistorial();
    }
  }

  /* -------------------------------------------------------------- 03 · historial */

  async function cargarHistorial() {
    var anio = Number($('#cAnio').value) || new Date().getFullYear();
    $('#subHistorial').textContent = 'Cargando…';
    try {
      var r = await fetch('/api/ehs/correccion/historial?anio=' + anio);
      var cuerpo = await r.json();
      pintarHistorial(cuerpo.correcciones || []);
    } catch (e) {
      $('#subHistorial').textContent = 'No se pudo cargar: ' + e.message;
    }
  }

  /* corregido_en es la hora LOCAL del motor (sysdatetime, con TZ America/Bogota), pero
     el driver la serializa con una 'Z' que no le corresponde. Se muestra la hora tal
     como viene: pasarla por new Date() la correria cinco horas. */
  function fechaHora(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(iso || ''));
    return m ? m[3] + '/' + m[2] + '/' + m[1] + ' ' + m[4] + ':' + m[5] : String(iso || '—');
  }

  function pintarHistorial(lista) {
    var cuerpo = $('#cuerpoHistorial');
    if (!lista.length) {
      cuerpo.innerHTML = '<tr><td colspan="5">Sin correcciones registradas este año.</td></tr>';
      $('#subHistorial').textContent = '0 correcciones';
      return;
    }
    cuerpo.innerHTML = lista
      .map(function (c) {
        var mag = porId[c.magnitud];
        return (
          '<tr><td>' +
          Fmt.esc(fechaHora(c.corregidoEn)) +
          '</td><td>' +
          Fmt.esc(c.sitioCorto) +
          ' · ' +
          Fmt.esc(Fmt.mesMini[c.mes - 1]) +
          ' ' +
          Fmt.esc(c.anio) +
          '</td><td><s>' +
          Fmt.esc(c.valorAnterior) +
          '</s> → <b>' +
          Fmt.esc(c.valorCorregido) +
          '</b> ' +
          Fmt.esc((mag && mag.unidad) || c.magnitudNombre) +
          '</td><td>' +
          Fmt.esc(c.motivo) +
          '</td><td>' +
          Fmt.esc(c.autorizadoPor) +
          '</td></tr>'
        );
      })
      .join('');
    $('#subHistorial').textContent =
      lista.length + (lista.length === 1 ? ' corrección' : ' correcciones');
  }

  /* ----------------------------------------------------------------------- inicio */

  /* Abre en el mes del corte publicado, ya consultado: lo que se corrige casi siempre es
     lo ultimo que se capturo. Antes abria en enero y vacio.
     Con ?anio=&mes=&sitio=&magnitud= (el lapiz de la vista "Datos" del tablero) abre
     directo en esa lectura, con el formulario de correccion ya abierto. */
  async function abrirEnElCorte() {
    var q = new URLSearchParams(location.search);
    var mesUrl = parseInt(q.get('mes'), 10);
    var anioUrl = parseInt(q.get('anio'), 10);
    var sitioUrl = q.get('sitio');
    if (mesUrl >= 1 && mesUrl <= 12) {
      $('#cMes').value = String(mesUrl);
      if (anioUrl >= 2023 && anioUrl <= 2100) $('#cAnio').value = String(anioUrl);
    } else {
      try {
        var r = await fetch('/api/ehs/salud');
        var s = await r.json();
        if (s && s.corte && s.corte.mes) {
          $('#cMes').value = String(s.corte.mes);
          if (s.corte.anio) $('#cAnio').value = String(s.corte.anio);
        }
      } catch {
        // sin salud se queda en lo que trae la pagina; consultar igual funciona a mano
      }
    }
    if (
      sitioUrl &&
      Array.prototype.some.call($('#cSitio').options, function (o) {
        return o.value === sitioUrl;
      })
    ) {
      $('#cSitio').value = sitioUrl;
      // se llego desde el lapiz de "Datos": volver ahi, al mismo sitio y mes, y no a la
      // portada, que obligaba a buscar otra vez la tabla para ver el cambio
      var volver = document.querySelector('a.volver[href="/"]');
      if (volver && mesUrl >= 1 && mesUrl <= 12) {
        volver.href =
          '/?' + new URLSearchParams({ vista: 'datos', sitio: sitioUrl, mes: mesUrl }).toString();
        volver.textContent = '← Volver a Datos';
      }
    }
    await consultar();

    var i = MAGNITUDES.findIndex(function (m) {
      return m.id === q.get('magnitud');
    });
    if (i >= 0) {
      var boton = document.querySelector('#cuerpoValores tr:nth-child(' + (i + 1) + ') button');
      if (boton && !boton.disabled) boton.click();
    }
  }

  function iniciar() {
    $('#bConsultar').addEventListener('click', consultar);
    $('#bCorregir').addEventListener('click', enviarCorreccion);
    $('#bCancelar').addEventListener('click', cerrarCorreccion);
    cargarHistorial();
    abrirEnElCorte();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
