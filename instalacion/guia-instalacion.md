# EHS en el equipo del área — cuál modo, y cómo instalarlo

## La recomendación, primero

**Modo nativo** para el equipo del área. **Modo contenedor** solo si IT ya tiene
Docker Business o Podman aprobado en ese equipo.

La razón no es técnica, es de licencia. Docker Desktop es gratis para uso personal y
para empresas chicas, pero **no para EssilorLuxottica**: su licencia exige una
suscripción paga (Docker Business) en empresas de más de 250 empleados o más de 10
millones de dólares en ingresos. SQL Server 2022 Express, en cambio, es gratis para
uso comercial sin esa condición, y cabe de sobra en lo que este proyecto necesita
(la auditoría de Fase A midió la base en 16 MB; el límite de Express es 10 GB).

Podman es gratis y no tiene esa restricción, así que el modo contenedor sigue
siendo una opción válida **si** IT instala Podman en vez de Docker Desktop.

## Qué se probó de verdad, y qué no

| | Modo contenedor | Modo nativo |
|---|---|---|
| Motor arrancando y aceptando logins | ✅ probado en vivo | ⚠️ no probado — no hay instalador de SQL Server Express en este entorno |
| `crear-logins.sql` (los dos logins, los permisos) | ✅ probado en vivo | ✅ mismo script — cambia solo cómo se le habla al motor |
| Las 9 migraciones | ✅ probado en vivo | ✅ mismo `migrar.js` — no depende del modo |
| Restringir el motor a `127.0.0.1` | ✅ lo hace Docker (`-p 127.0.0.1:…`) | ⚠️ no probado — WMI o registro, ver abajo |
| Tarea programada y accesos directos | ⚠️ bloqueado por UAC en esta sesión | ⚠️ igual — mismo código |

Construyendo y corriendo el modo contenedor aparecieron **seis defectos reales**, ya
corregidos (ver el commit `e82e626`). El modo nativo comparte el 80% del código con
el contenedor, así que la mayoría de esos arreglos le aplican también — pero su
parte propia (instalar SQL Server Express, restringirlo a `127.0.0.1`) **no se pudo
correr ni una vez** aquí. Es la parte con más probabilidad de sorprender en el primer
intento real.

## El único paso que no se puede automatizar

**Hay que aceptar una ventana de Windows (UAC) una vez**, al principio. Registrar la
tarea programada que arranca el tablero exige un PowerShell elevado — en los dos
modos, no solo en el nativo. Se confirmó con dos herramientas distintas de Windows
(`Register-ScheduledTask` y `schtasks.exe`): ninguna deja crear la tarea sin
elevación, aunque la cuenta sea administradora y la tarea misma corra después sin
privilegios. No es un error del script: es cómo funciona el Programador de tareas.

Todo lo demás corre solo después de ese clic, sin más ventanas ni preguntas.

---

## Paso a paso — modo nativo (recomendado)

**Antes, en la máquina de desarrollo:**

1. Descarga el instalador oficial de SQL Server 2022 Express desde Microsoft
   (`SQL2022-SSEI-Expr.exe`). Guárdalo junto al paquete.
2. Descarga Node.js 22 portable para Windows x64 (el `.zip` "win-x64" de
   nodejs.org, **no** el instalador `.msi`). Extráelo en una carpeta.
3. En `app\`, corre `npm install --omit=dev` para que el paquete no lleve
   herramientas de desarrollo.
4. Arma el paquete:
   ```powershell
   cd app\instalacion
   .\empaquetar.ps1 -RutaNodePortable 'C:\ruta\a\node-v22-win-x64'
   ```
   Deja `paquete.zip` junto a `app\`.
5. Copia `paquete.zip` y `SQL2022-SSEI-Expr.exe` al equipo del área (USB, OneDrive,
   como IT lo prefiera).

**En el equipo del área:**

6. Extrae `paquete.zip` en una carpeta permanente — por ejemplo
   `C:\EHS\`. No en Descargas ni en el Escritorio: esa carpeta es la instalación.
7. Abre **PowerShell como Administrador** (clic derecho en el ícono → Ejecutar como
   administrador). **Este es el único clic que no se puede evitar.**
8. Corre, ajustando las dos rutas:
   ```powershell
   cd C:\EHS\app\instalacion
   .\instalar.ps1 -Motor nativo -RutaInstaladorSqlExpress 'C:\ruta\a\SQL2022-SSEI-Expr.exe'
   ```
   Tarda varios minutos (instalar SQL Server es lo lento). Al terminar, abre el
   navegador solo.
9. **Verifica que el motor solo escucha en `127.0.0.1`** — es la parte no probada:
   ```powershell
   netstat -ano | findstr :14330
   ```
   Tiene que mostrar **solo** `127.0.0.1:14330`. Si aparece `0.0.0.0:14330`, abre
   *SQL Server Configuration Manager* → *Protocolos de EHSLOCAL* → *TCP/IP* → en
   cada IP que no sea `127.0.0.1`, pon *Habilitado = No*, y reinicia el servicio.
10. Cierra la ventana de PowerShell. Desde aquí, quien usa el equipo solo ve el
    ícono **EHS** del escritorio.

## Paso a paso — modo contenedor (si IT tiene Podman o Docker Business)

Igual que el nativo, salvo:

- **No hace falta** el instalador de SQL Server (pasos 1 y 5 sin el `.exe`).
- **Sí hace falta** Podman o Docker Desktop **ya instalado y corriendo** en el equipo
  del área antes del paso 8.
- En el paso 8:
  ```powershell
  .\instalar.ps1 -Motor contenedor
  ```
- El paso 9 no hace falta: Docker/Podman publica el puerto **solo** en `127.0.0.1`
  por construcción (`-p 127.0.0.1:14330:1433`), y eso sí se probó.

---

## Si algo falla en el primer intento

| Qué se ve | Qué es | Qué hacer |
|---|---|---|
| "Este instalador necesita PowerShell como Administrador" | No se abrió como admin | Paso 7 |
| "Ni docker ni podman están disponibles" | Modo contenedor sin Docker/Podman | Instalar Podman, o usar `-Motor nativo` |
| "-RutaInstaladorSqlExpress no se dio o no existe" | Ruta mal escrita | Revisa la ruta del paso 8 |
| "El motor no aceptó conexiones… tras 120 segundos" | El motor no arrancó | En nativo: revisa el servicio `MSSQL$EHSLOCAL` en *Servicios*. En contenedor: `docker logs ehs-motor` |
| Cualquier otro error de `instalar.ps1` | Algo que esta sesión no pudo prever | El mensaje de error completo es lo que hace falta para diagnosticarlo |

Correr `instalar.ps1` otra vez después de un error es seguro: es idempotente en todo
lo que ya quedó hecho (el motor, los logins, las migraciones aplicadas).

## Después de instalar

- **Reparar**: doble clic en *Reparar EHS* del escritorio cuando la franja de
  estado se ponga roja.
- **Respaldo**: automático, todos los días a las 20:00 y después de cada captura, a
  `C:\EHS\datos\respaldo\` y a OneDrive si está configurado.
- **Actualizar a una versión nueva**: copia la carpeta `app\` nueva encima de la
  actual y corre `.\actualizar.ps1` (no hace falta admin: usa las credenciales que
  ya están en `config\ehs.env`).
- **Desinstalar**: `.\desinstalar.ps1` (conserva el dato por defecto;
  `-BorrarDatoTambien` lo borra, pidiendo confirmación escrita).
