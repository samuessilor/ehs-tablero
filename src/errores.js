/**
 * Formato uniforme de error del contrato: { error, mensaje, detalle }.
 * El mensaje va en espanol y dirigido a quien usa el tablero, no al desarrollador.
 */
function responder(res, codigo, error, mensaje, detalle) {
  res.statusCode = codigo;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify({ error, mensaje, detalle: detalle || null }));
}

module.exports = {
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
