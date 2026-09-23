/**
 * Formato uniforme de error del contrato: { error, mensaje, detalle }.
 * El mensaje va en espanol y dirigido a quien usa el tablero, no al desarrollador.
 */
function responder(res, codigo, error, mensaje, detalle) {
  res.statusCode = codigo;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify({ error, mensaje, detalle: detalle || null }));
}

/**
 * El error de una PANTALLA, no de la API: una pagina legible en vez del JSON. Con el
 * motor caido la portada mostraba {"error":"motor_inalcanzable",...} en texto plano,
 * y es justo lo que ve quien abre el tablero apenas enciende el equipo, mientras
 * Docker Desktop todavia esta levantando el motor. Los textos son fijos: nada de lo
 * que llega en la peticion se escribe en el HTML.
 */
function paginaDeError(res, codigo, titulo, texto, recargar) {
  res.statusCode = codigo;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(`<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
${recargar ? '<meta http-equiv="refresh" content="15" />' : ''}
<title>EHS · ${titulo}</title>
<link rel="stylesheet" href="/css/ehs.css" />
<link rel="icon" href="data:," />
</head>
<body>
<main class="body cap">
  <section class="panel c12 cap-aviso">
    <div class="cuerpo">
      <p><strong>${titulo}</strong></p>
      <p>${texto}</p>
      <p><a href="">Reintentar ahora</a></p>
    </div>
  </section>
</main>
</body>
</html>`);
}

module.exports = {
  /** Para las rutas de pantalla (/, /captura, /corregir, /reporte). */
  pagina(res, err) {
    if (err && err.name === 'ConnectionError') {
      paginaDeError(
        res,
        503,
        'El motor de datos todavía no responde',
        'Si acabas de encender el equipo, el motor tarda uno o dos minutos en arrancar: ' +
          'esta página vuelve a intentarlo sola cada 15 segundos. Si en tres minutos sigue ' +
          'igual, usa el ícono <b>Reparar EHS</b> del escritorio.',
        true
      );
    } else if (err && err.codigo === 'sin_datos_publicados') {
      paginaDeError(
        res,
        503,
        'Todavía no hay un mes publicado',
        'El tablero se llena cuando un mes tiene sus 27 lecturas. Empieza por ' +
          '<a href="/captura">Capturar mes</a>.',
        false
      );
    } else {
      paginaDeError(
        res,
        500,
        'El tablero no pudo mostrar esta página',
        'El detalle quedó en el registro del servidor. Si se repite, usa el ícono ' +
          '<b>Reparar EHS</b> del escritorio.',
        false
      );
    }
    console.error(err);
  },

  parametroInvalido(res, mensaje, detalle) {
    responder(res, 400, 'parametro_invalido', mensaje, detalle);
  },
  noEncontrado(res, mensaje) {
    responder(res, 404, 'no_encontrado', mensaje || 'No existe ese recurso.');
  },
  interno(res, err) {
    // dos causas se explican al cliente porque las puede arreglar quien opera: el
    // adaptador SQL sin implementar y el dato sin publicar. Cualquier otra solo va al
    // registro del servidor: un traceback en pantalla no ayuda a nadie
    const explicables = { sin_implementar: 501, sin_datos_publicados: 503 };
    const codigo = err && err.codigo;

    // El motor caido o inalcanzable es la falla que mas va a ver quien opera el
    // paquete instalable (Fase C-D): el servicio no arranco, o el atajo "Reparar"
    // esta corriendo. Sin distinguirla, era el mismo 500 generico que un error de
    // programacion — y "el detalle quedo en el registro" no ayuda a alguien sin
    // consola. mssql marca esta familia con name='ConnectionError'
    // (ESOCKET/ETIMEOUT/ELOGIN); una falla de una consulta ya conectada es
    // RequestError y sigue siendo generica a proposito, porque esa si es un error
    // de programacion que hay que mirar en el registro.
    if (err && err.name === 'ConnectionError') {
      responder(
        res,
        503,
        'motor_inalcanzable',
        'El tablero no pudo conectarse a la base de datos. Si el problema sigue, usa "Reparar".',
        null
      );
      console.error(err);
      return;
    }

    responder(
      res,
      explicables[codigo] || 500,
      codigo || 'error_interno',
      explicables[codigo]
        ? 'El tablero no puede responder todavia.'
        : 'El tablero no pudo responder. El detalle quedo en el registro del servidor.',
      explicables[codigo] ? err.message : null
    );
    console.error(err);
  },
};
