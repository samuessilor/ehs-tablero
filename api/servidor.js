/**
 * Punto de entrada en Vercel (@vercel/node). Es el mismo enrutador del servidor
 * local: una sola implementacion de rutas, dos envolturas.
 */
module.exports = require('../src/aplicacion').atender;
