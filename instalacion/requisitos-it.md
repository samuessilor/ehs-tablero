# EHS local — qué le pide este paquete a IT

**Instalar EHS no necesita administrador.** El instalador (`INSTALAR-EHS.cmd`) corre
con la cuenta normal de quien usa el equipo, sin aviso de Windows (UAC). Lo único que
debe existir antes en el equipo es un motor de contenedores funcionando, y ESO sí lo
instala IT, una vez.

## Lo que IT deja listo antes (una sola vez)

| Requisito | Detalle |
|---|---|
| Docker Desktop instalado | Con el motor WSL 2 (el que Docker Desktop propone por defecto). Necesita la virtualización activa en la BIOS/UEFI |
| La cuenta de la persona en el grupo `docker-users` | Si IT instala Docker Desktop con otra cuenta de administrador, la cuenta de quien usa el equipo **no** queda en ese grupo y `docker` le responde "acceso denegado". Docker lo documenta así: hay que agregarla a mano (Administración de equipos → Usuarios y grupos locales → `docker-users`) y cerrar sesión |
| Licencia | Docker Desktop es gratis solo para empresas de menos de 250 empleados **y** menos de 10 millones de dólares de ingresos. EssilorLuxottica necesita un puesto de **Docker Business** para ese equipo, o usar **Podman Desktop** (gratis, sin esa condición; el instalador de EHS lo detecta, pero con Podman no se ha probado en vivo) |
| Memoria | 8 GB de RAM en el equipo es lo razonable: SQL Server en contenedor pide al menos 2 GB para él solo |

Con eso listo, la persona del área (o Samuel con ella) hace doble clic en
`INSTALAR-EHS.cmd` y no hace falta nada más de IT.

## Qué instala EHS, exactamente

| Elemento | Detalle |
|---|---|
| Motor de base de datos | SQL Server 2022 Express en un contenedor (`ehs-motor`), con su dato en un volumen de Docker (`ehs-motor-datos`). La imagen viaja dentro del paquete: la instalación no descarga nada |
| Dónde escucha | **Solo `127.0.0.1`**: el motor en el puerto 14330 y el tablero en el 3210. Ninguno queda en una interfaz de red, así que no pide ninguna excepción del firewall |
| La aplicación | Node.js portable dentro de `C:\EHS\node\`. No instala Node en el sistema ni toca el PATH |
| Arranque | Un acceso directo en la carpeta **Inicio** de la persona (`EHS Tablero.lnk`), que abre el tablero sin ventana al iniciar sesión. No es un servicio de Windows ni una tarea programada, y no corre con cuenta de sistema |
| Docker al iniciar sesión | Se enciende "Start Docker Desktop when you sign in" en la configuración de Docker **de esa persona** (queda copia del archivo original como `settings-store.json.ehs-antes`). Sin esto, después de cada reinicio el tablero se quedaría sin motor |
| Dos logins SQL | `ehs_migrador` (crea y actualiza el esquema) y `ehs_app` (la que usa el tablero: solo lee y solo puede ejecutar dos procedimientos, el de captura y el de corrección; ni `db_owner` ni `sa`) |
| Respaldo | Un `.bak` después de cada captura o corrección y uno diario, en `C:\EHS\ehs-datos\respaldo\` (se conservan los 14 más recientes), copiado además a OneDrive corporativo si está configurado en el equipo |
| Accesos en el escritorio | **EHS** (abre el tablero) y **Reparar EHS** |

## Qué NO hace

- No expone ningún puerto a la red.
- No crea servicios de Windows, tareas programadas ni cuentas.
- No pide ni guarda ninguna contraseña de Windows.
- No manda datos fuera del equipo, salvo la copia del respaldo a OneDrive corporativo.
- Las claves de los dos logins SQL quedan en `C:\EHS\app\config\ehs.env`, un archivo
  local del equipo. La clave de `sa` se usa solo durante la instalación: al terminar,
  el instalador la cambia por una que no queda guardada en ningún lado (ni en ese
  archivo ni en la configuración del contenedor).

## Plan B, si Docker no es posible en ese equipo

`INSTALAR-EHS-NATIVO.cmd` instala SQL Server 2022 Express como servicio de Windows, sin
Docker. Ese camino **sí** pide administrador una vez (el aviso de UAC), porque instalar
un servicio lo exige. La aplicación, el esquema y las pantallas son los mismos. Este
modo quedó preparado pero todavía no se ha corrido de punta a punta en un equipo real.

## Migrar más adelante a la instancia de empresa

El esquema, las migraciones y el ejecutor (`scripts\migrar.js`) son los mismos que se
usarían contra un SQL Server de la empresa. Migrar es cambiar `config\ehs.env`
(servidor, credenciales) y correr `migrar.js` contra la base nueva; no se reescribe
ninguna tabla ni vista.

## Contacto

Cualquier duda de esta instalación, con Samuel Galeano, por el mismo canal por el que
llegó este paquete.
