# EHS local — qué le pide este paquete a IT

**Instalar EHS pide administrador una sola vez** (el aviso de UAC): el motor de base de
datos es SQL Server 2022 Express, instalado como servicio de Windows. Con eso listo, la
persona del área hace doble clic en `INSTALAR-EHS-NATIVO.cmd`, confirma el aviso de
administrador y no hace falta nada más de IT — el uso de cada día no vuelve a pedir
elevación.

**Por qué SQL Server Express y no un contenedor (Docker).** Se evaluaron los dos. Docker
Desktop es gratis solo para empresas de menos de 250 empleados y menos de 10 millones de
dólares de ingresos: EssilorLuxottica necesita un puesto de **Docker Business** para el
equipo, y esa decisión de licencia y compra sigue sin resolverse. SQL Server 2022
Express es gratis sin ninguna condición de tamaño de empresa — elimina ese bloqueo en
vez de rodearlo con una alternativa (Podman Desktop, Rancher Desktop) sin probar. El
modo contenedor queda preparado y documentado (sección "Alternativa" más abajo) por si
la licencia de Docker se resuelve más adelante, pero **no es el camino que se está
instalando**.

## Lo que IT hace antes (una sola vez, con administrador)

| Requisito | Detalle |
|---|---|
| Windows 10 u 11 de 64 bits, 8 GB de RAM, ~6 GB libres en disco | SQL Server Express en sí pesa unos 2-3 GB |
| Confirmar el aviso de administrador (UAC) al correr `INSTALAR-EHS-NATIVO.cmd` | Es el único momento de toda la instalación y del uso diario que lo pide |
| Nada de licencia que gestionar | SQL Server 2022 Express es gratis, sin cupo de usuarios ni condición de tamaño de empresa |

Con eso, la persona del área (o Samuel con ella) hace doble clic en
`INSTALAR-EHS-NATIVO.cmd`. El paquete trae el instalador oficial de SQL Server Express
(`SQLEXPR_x64_ESN.exe`, en español; para otro idioma se arma con `SQLEXPR_x64_ENU.exe`)
— no descarga nada de internet.

## Qué instala EHS, exactamente

| Elemento | Detalle |
|---|---|
| Motor de base de datos | SQL Server 2022 Express como servicio de Windows, instancia propia `EHSLOCAL` (no toca ninguna instancia de SQL Server que ya exista en el equipo). Su dato queda en `C:\EHS\ehs-datos\motor\` |
| Dónde escucha | **Solo `127.0.0.1`**: el motor en el puerto 14330 y el tablero en el 3210, verificado con `Get-NetTCPConnection` al terminar de instalar. Ninguno queda en una interfaz de red, así que no pide ninguna excepción del firewall |
| La aplicación | Node.js portable dentro de `C:\EHS\node\`. No instala Node en el sistema ni toca el PATH |
| Arranque | Un acceso directo en la carpeta **Inicio** de la persona (`EHS Tablero.lnk`), que abre el tablero sin ventana al iniciar sesión. No es un servicio de Windows con cuenta de sistema ni una tarea programada |
| "Reparar EHS" sin administrador | El instalador le da a la cuenta de la persona permiso para reiniciar **solo** el servicio `MSSQL$EHSLOCAL` (nada más, y ningún otro servicio) — así "Reparar EHS" funciona sin pedir UAC en el día a día |
| Dos logins SQL | `ehs_migrador` (crea y actualiza el esquema) y `ehs_app` (la que usa el tablero: solo lee y solo puede ejecutar tres procedimientos — capturar, corregir y confirmar un aviso; ni `db_owner` ni `sa`) |
| Respaldo | Un `.bak` después de cada captura o corrección y uno diario, en `C:\EHS\ehs-datos\respaldo\` (se conservan los 14 más recientes), copiado además a OneDrive corporativo si está configurado en el equipo |
| Accesos en el escritorio | **EHS** (abre el tablero) y **Reparar EHS** |

## Qué NO hace

- No expone ningún puerto a la red.
- No crea tareas programadas ni cuentas de dominio nuevas.
- No pide ni guarda ninguna contraseña de Windows.
- No manda datos fuera del equipo, salvo la copia del respaldo a OneDrive corporativo.
- No toca ninguna otra instancia de SQL Server que ya exista en el equipo: instala la
  suya propia, con su propio nombre (`EHSLOCAL`).
- Las claves de los dos logins SQL quedan en `C:\EHS\app\config\ehs.env`, un archivo
  local del equipo. La clave de `sa` se usa solo durante la instalación: al terminar,
  el instalador la cambia por una que no queda guardada en ningún lado.

## Alternativa: modo contenedor (Docker), si la licencia ya está resuelta

Si más adelante EssilorLuxottica tiene un puesto de Docker Business (o decide usar
Podman/Rancher Desktop), `INSTALAR-EHS.cmd` instala el mismo tablero con SQL Server en
un contenedor, **sin pedir administrador para el día a día** (el motor de contenedores
sí lo instala IT, una vez, con administrador — el mismo tipo de paso que el modo
nativo). El esquema, las migraciones y las pantallas son exactamente los mismos; cambiar
de un modo al otro no reescribe ninguna tabla ni vista. Ver `guia-instalacion.md`,
sección "Alternativa: modo contenedor".

## Migrar más adelante a la instancia de empresa

El esquema, las migraciones y el ejecutor (`scripts\migrar.js`) son los mismos que se
usarían contra un SQL Server de la empresa. Migrar es cambiar `config\ehs.env`
(servidor, credenciales) y correr `migrar.js` contra la base nueva; no se reescribe
ninguna tabla ni vista.

## Contacto

Cualquier duda de esta instalación, con Samuel Galeano, por el mismo canal por el que
llegó este paquete.
