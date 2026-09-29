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
| Licencia | Docker Desktop es gratis solo para empresas de menos de 250 empleados **y** menos de 10 millones de dólares de ingresos. EssilorLuxottica necesita un puesto de **Docker Business** para ese equipo, o usar **Podman Desktop** o **Rancher Desktop** con motor *dockerd* (gratis, sin esa condición). El instalador de EHS los detecta, pero el arranque automático y "Reparar EHS" están hechos para Docker Desktop, y no se han probado en vivo |
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
| Docker al iniciar sesión | El tablero, al arrancar, abre Docker Desktop si no está abierto. No se toca ningún ajuste de Docker: editar su configuración no se sostiene, porque Docker Desktop la reescribe |
| Dos logins SQL | `ehs_migrador` (crea y actualiza el esquema) y `ehs_app` (la que usa el tablero: solo lee y solo puede ejecutar tres procedimientos — capturar, corregir y confirmar un aviso; ni `db_owner` ni `sa`) |
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

## Las opciones de implementación, una por una

Hay cinco caminos. El paquete instala A y B con el mismo `INSTALAR-EHS.cmd`, y C con
`INSTALAR-EHS-NATIVO.cmd`. Las cifras de descarga se midieron el 28-sep-2026.

| | A. Contenedor con **Docker Desktop** (el que se instala) | B. Contenedor con **Podman / Rancher Desktop** | C. **Nativo**: SQL Server Express como servicio | D. **Solo lectura**, sin base de datos | E. **Servidor de la empresa** (IT) |
|---|---|---|---|---|---|
| Administrador para instalar EHS | No | No | **Sí** (UAC) | No | Lo hace IT |
| Administrador para desinstalar | No | No | **Sí** | No | IT |
| Administrador para lo previo | **Sí, una vez, IT**: instalar Docker Desktop (activa WSL 2; puede pedir reiniciar) y agregar la cuenta a `docker-users` | **Sí, una vez, IT**: instalar el programa | Está en el propio instalador de EHS | No | IT |
| Qué hay que descargar | **Docker Desktop**, 628 MB (docker.com). Lo demás ya viaja en el paquete: la imagen del motor (596 MB), Node portable, la aplicación | El instalador de Podman Desktop o de Rancher Desktop (motor *dockerd*); no medido | Nada aparte del paquete, **pero al instalar** baja 714 MB de Microsoft (SQL Server en inglés): **necesita internet** | Nada: Node portable ya está en el paquete | Lo define IT |
| Internet al instalar EHS | No | No | **Sí** | No | Según IT |
| Licencia | **Docker Business** (pago, decisión de la organización) | Gratis | Gratis | Gratis | La de IT |
| ¿Captura, corrige y confirma avisos? | Sí | Sí | Sí | **No**: las escrituras son simuladas, no guardan nada | Sí |
| Arranque automático, respaldos y Reparar | Sí, probados | El instalador funciona; el arranque automático y Reparar están hechos para Docker Desktop y **no se han probado** | Sí (en el código), **nunca corrido de punta a punta** | Nada de eso | Lo define IT |
| Estado de prueba | ✅ de punta a punta, dos veces (23 y 28-sep) | ⚠️ sin probar | ⚠️ el primer intento se detuvo por el idioma del instalador; sin repetir | Existe en el código (es el que corre en Vercel), pero el paquete **no trae lanzador** | No aplica todavía: IT no ha entregado el servidor |

**Cuál conviene.** En orden de practicidad:

1. **A, Docker Desktop.** Es la única que se probó completa y la única donde lo elevado es
   una sola cosa, hecha una vez por IT. La persona del área no vuelve a ver un aviso de
   administrador. Su costo es la licencia y unos 2 GB de memoria para el motor. **Es la
   recomendada, si IT aprueba la licencia.**
2. **B, Podman o Rancher Desktop**, si la licencia de Docker no se aprueba: mismo
   paquete, sin costo, pero hay que ensayarla una vez antes de dársela a la persona.
3. **E, servidor de la empresa**, que es el destino definitivo de la fase 1: EHS instala
   allí la misma aplicación contra un SQL Server de IT (ver "Migrar más adelante"). El
   equipo local es el puente mientras IT lo entrega.
4. **C, nativo**, solo si no hay ningún motor de contenedores posible: pide
   administrador dos veces, cambia más cosas del sistema, necesita internet y no está
   probado.
5. **D, solo lectura**, no reemplaza a las demás: sirve para mostrar el tablero, no para
   capturar datos.

## Qué permisos pide cada camino (medido en el código, 28-sep-2026)

| Permiso o cambio en el equipo | Contenedor (el que se instala) | Nativo (plan B) |
|---|---|---|
| Aviso de administrador (UAC) al instalar EHS | **No** | Sí |
| Aviso de administrador para desinstalar | **No** | Sí (retira un servicio de Windows) |
| Instala software con administrador | Solo Docker Desktop, una vez, por IT | SQL Server 2022 Express, una vez |
| Servicio de Windows nuevo | No (el motor vive dentro del contenedor) | Sí: `MSSQL$EHSLOCAL`, en Program Files |
| Cambia el registro de Windows (HKLM) | No | Sí: restringe el TCP del motor a `127.0.0.1` y, en algunos discos NVMe, un ajuste de sector del sistema |
| Cambia permisos de servicios y carpetas | No | Sí: `sc.exe sdset` (para que "Reparar" reinicie el servicio sin administrador) e `icacls` sobre la carpeta de respaldos |
| Quién administra la base | Solo los logins de EHS | El grupo local **Administradores** queda como administrador (`sysadmin`) de la instancia |
| Deja un servicio escuchando aparte | No | Se apaga SQL Server Browser (UDP 1434) |
| Requisito previo de licencia | **Docker Business** (o Podman/Rancher Desktop): ver arriba | Ninguno |

Por eso el contenedor es el camino principal: el instalador de EHS no eleva nada. Lo que
sí pide permisos es **Docker Desktop**, y eso lo hace IT una sola vez.

## Plan B, si Docker no es posible en ese equipo (o la licencia no se resuelve)

`INSTALAR-EHS-NATIVO.cmd` instala SQL Server 2022 Express como servicio de Windows, sin
Docker. Ese camino **sí** pide administrador (el aviso de UAC) para instalar y también
para desinstalar, y toca lo que dice la tabla de arriba. La aplicación, el esquema y las
pantallas son los mismos.

**Idioma del instalador de SQL Server — hallazgo de la primera corrida real
(28-sep-2026, equipo de Samuel).** El paquete anterior traía `SQLEXPR_x64_ESN.exe`
(español de España). En un Windows con idioma `es-ES` pero **formato regional `es-CO`**
(Colombia) `setup.exe` se detuvo con `0x84C4000E` sin dejar registro; corriéndolo a mano
dijo *"este medio no soporta el idioma del sistema"*. El medio en español exige que el
idioma de Windows, la configuración regional del sistema **y** el formato coincidan con
él, y en Colombia el formato no es el de España. (Una primera lectura culpó a un reinicio
pendiente de Windows: estaba equivocada, un reinicio real no lo arregló.) Ahora:

- El paquete trae el **descargador oficial de Microsoft** (`SQL2022-SSEI-Expr.exe`, 4 MB,
  firma verificada), que baja el medio **en inglés** —el que sirve en cualquier idioma—
  al instalar: este plan B necesita internet. (Alternativa sin internet:
  `SQLEXPR_x64_ENU.exe`, ~700 MB, y pasarlo con `-RutaInstaladorSqlExpress`.)
- `instalar.ps1` comprueba el idioma **antes** de lanzar `setup.exe` y, si el medio es ESN
  y el equipo no coincide, se detiene diciendo por qué. Y si `setup.exe` falla por otra
  causa, el error trae lo que `setup.exe` imprimió.

Este modo quedó preparado pero **todavía no se ha corrido de punta a punta**: el intento
del 28-sep se detuvo en ese punto, y no se repitió porque instala un servicio de sistema
y pide administrador. No quedó nada instalado ni a medias.

## Migrar más adelante a la instancia de empresa

El esquema, las migraciones y el ejecutor (`scripts\migrar.js`) son los mismos que se
usarían contra un SQL Server de la empresa. Migrar es cambiar `config\ehs.env`
(servidor, credenciales) y correr `migrar.js` contra la base nueva; no se reescribe
ninguna tabla ni vista.

## Contacto

Cualquier duda de esta instalación, con Samuel Galeano, por el mismo canal por el que
llegó este paquete.
