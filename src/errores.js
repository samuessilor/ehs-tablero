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
