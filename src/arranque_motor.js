/**
 * Abre Docker Desktop al arrancar el tablero, si no esta abierto (solo instalacion en
 * modo contenedor, en Windows).
 *
 * El tablero arranca al iniciar sesion (acceso directo en la carpeta Inicio), pero el
 * motor vive dentro de Docker Desktop, y Docker Desktop viene con "Start Docker Desktop
 * when you sign in" apagado. instalar.ps1 intentaba encenderlo editando su
 * settings-store.json, y no se sostiene: Docker Desktop reescribe ese archivo con lo
 * que tiene en memoria la siguiente vez que guarda sus ajustes (se vio en el equipo de
 * prueba: la instalacion lo dejo en true y horas despues estaba otra vez en false).
 * Despues de reiniciar, el tablero habria quedado esperando un motor que nadie abria.
 *
 * Por eso lo abre el propio tablero: no depende de los ajustes de Docker ni pide
 * administrador. El contenedor ehs-motor tiene --restart unless-stopped, asi que
 * arranca solo en cuanto el motor de Docker esta arriba.
 */
const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');
const { setTimeout } = require('timers');
const { obtener } = require('./datos/configuracion');

// Docker Desktop se instala en uno de dos sitios: para todos los usuarios (pide
// administrador) o solo para el usuario actual (`install --user`, sin administrador).
const CANDIDATOS = [
  path.join(
    process.env.ProgramFiles || 'C:\\Program Files',
    'Docker',
    'Docker',
    'Docker Desktop.exe'
  ),
  path.join(process.env.LOCALAPPDATA || '', 'Programs', 'DockerDesktop', 'Docker Desktop.exe'),
];
// Unos segundos de gracia al iniciar sesion: si Docker Desktop tiene su propio arranque
// automatico encendido, se le deja aparecer primero en vez de lanzar un segundo intento.
const ESPERA_MS = 20 * 1000;

/**
 * @param {object} [opciones] Solo para probar: otro ejecutable y la espera.
 * @returns {Promise<string>} Lo que hizo: 'no aplica', 'ya estaba abierto', 'abierto'.
 */
function asegurarDockerDesktop(opciones = {}) {
  const exe = opciones.exe || CANDIDATOS.find((c) => fs.existsSync(c)) || CANDIDATOS[0];
  const espera = opciones.esperaMs ?? ESPERA_MS;
  return new Promise((resolve) => {
    if (!opciones.exe && (process.platform !== 'win32' || obtener('EHS_MOTOR') !== 'contenedor')) {
      return resolve('no aplica');
    }
    if (!fs.existsSync(exe)) return resolve('no aplica');
    setTimeout(() => {
      const imagen = path.basename(exe);
      execFile(
        'tasklist',
        ['/FI', `IMAGENAME eq ${imagen}`, '/NH'],
        { windowsHide: true },
        (err, salida) => {
          if (!err && String(salida).toLowerCase().includes(imagen.toLowerCase())) {
            return resolve('ya estaba abierto');
          }
          try {
            // detached: que Docker Desktop no muera con el tablero (Reparar y actualizar
            // reinician node). Es una aplicacion de ventana, no de consola, asi que
            // detached no le quita nada.
            const hijo = spawn(exe, [], { detached: true, stdio: 'ignore' });
            hijo.on('error', () => {});
            hijo.unref();
            resolve('abierto');
          } catch {
            resolve('no aplica');
          }
        }
      );
    }, espera).unref();
  });
}

module.exports = { asegurarDockerDesktop };
