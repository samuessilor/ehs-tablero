# EHS en el equipo del área: instalación paso a paso

La versión que se instala es **modo nativo**: SQL Server 2022 Express como servicio de
Windows, con `INSTALAR-EHS-NATIVO.cmd`. Pide administrador (el aviso de UAC) **una sola
vez**, al instalar; el uso de cada día, después, no vuelve a pedirlo. Tarda unos minutos
y deja todo configurado: base, histórico 2026, íconos, arranque solo al encender y
respaldos.

Se evaluó también instalar con Docker (modo contenedor). Se descartó porque
EssilorLuxottica necesita una licencia de Docker Business que sigue sin resolverse — SQL
Server Express es gratis sin esa condición y evita el bloqueo en vez de rodearlo. El modo
contenedor queda preparado por si la licencia se resuelve más adelante: ver la sección
"Alternativa: modo contenedor" al final de esta guía.

---

## 1. Antes: lo que el equipo necesita

| Qué | Cómo saber si ya está |
|---|---|
| Windows 10 u 11 de 64 bits, 8 GB de RAM, ~6 GB libres en disco | Configuración → Sistema → Información |
| Una cuenta con permiso de administrador a mano, para el aviso de UAC | La de IT, o la de quien instale |

No hace falta internet: el instalador de SQL Server Express viaja dentro del paquete
(`SQLEXPR_x64_ESN.exe`, en español).

## 2. Instalar

1. **Copia `paquete.zip` al equipo** (USB, OneDrive, correo; lo que sea más fácil).
2. **Clic derecho → Extraer todo… → `C:\EHS`.** No en Descargas ni en el Escritorio:
   esa carpeta es la instalación y no se debe mover después. Quedan
   `C:\EHS\INSTALAR-EHS-NATIVO.cmd`, `app\`, `node\` e `instaladores\`.
3. **Doble clic en `C:\EHS\INSTALAR-EHS-NATIVO.cmd`.** Si Windows pregunta "¿Desea
   ejecutar este archivo?" (pasa cuando el .zip vino de internet o de un correo),
   responde **Ejecutar**. Enseguida aparece el aviso de administrador de Windows (UAC):
   **Sí**. Es el único momento de toda la instalación que lo pide.
4. **Espera varios minutos.** SQL Server Express se instala primero (la parte que más
   tarda); la ventana va mostrando cada paso. Al terminar dice `Listo` y se abre el
   tablero en el navegador.
5. **Comprueba** que arriba del tablero la franja dice **"Motor conectado"** con el
   punto verde, y que en el escritorio quedaron dos íconos: **EHS** y **Reparar EHS**.

Si algo falla, la ventana lo dice en rojo y **no se pierde nada**: se corrige lo que
diga el mensaje (tabla de la sección 5) y se vuelve a hacer doble clic en
`INSTALAR-EHS-NATIVO.cmd`. Volver a correrlo es seguro: reutiliza el motor y las claves
de un intento anterior en vez de empezar de cero.

## 3. El uso de cada mes

- **Tablero** (ícono EHS): los cinco indicadores al corte, contra su meta.
- **Capturar mes** (arriba a la derecha): las 27 lecturas del mes que cerró.
  - Una celda vacía **no** es un cero: se deja vacía si el dato no ha llegado.
  - Donde no hay personal temporal (hoy, Celta y La Estrella) se escribe **0** en sus
    horas.
  - El tablero publica el mes cuando están **las 27** (y los meses anteriores también).
    Mientras tanto, la pantalla de captura dice cuántas van y cuáles faltan, y marca en
    gris las ya capturadas, que no se reescriben ahí: se cambian en Consultar y corregir.
  - Números sin punto de miles: `9614`, o `979,1` con coma decimal. `9.614` se rechaza
    por ambiguo.
- **Consultar y corregir**: para cambiar un número ya capturado. Pide el motivo, y el
  valor anterior queda en el historial con quién lo cambió y cuándo.
- **06 Datos** (pestaña del tablero): las lecturas tal como están en la base, por cada
  indicador el numerador, denominador y resultado del mes y del acumulado (lo que
  dibujan las gráficas, con **cuadra** si las lecturas dan lo que usa el cálculo), las
  metas de cada indicador y el histórico por año. Con un sitio elegido, el lápiz ✎ de
  cada lectura abre su corrección.
- **Calidad del dato**: los avisos automáticos (un salto brusco mes a mes) se pueden
  confirmar ahí mismo — quien lo revisa escribe su nombre y, si quiere, una nota, y
  queda escrito en la base con quién y cuándo.
- **Descargar reporte**: el resumen para imprimir o guardar como PDF, y el detalle en
  CSV.

El respaldo es automático: uno después de cada captura o corrección (varias dentro del mismo
minuto quedan cubiertas por un solo respaldo al cumplirse el minuto) y uno diario, en
`C:\EHS\ehs-datos\respaldo\` (se guardan los 14 más recientes), y una copia en la
carpeta `EHS-respaldo` del OneDrive **corporativo** si está configurado en el equipo.
La franja de arriba dice cuándo fue el último.

## 4. Al encender el equipo

No hay que hacer nada. El tablero arranca solo al iniciar sesión; SQL Server Express es
un servicio de Windows que arranca solo con el equipo (antes incluso de iniciar sesión),
así que el motor ya está listo cuando el tablero lo busca.

## 5. Si algo falla

| Qué se ve | Qué hacer |
|---|---|
| "El modo nativo necesita PowerShell como Administrador" | No se aceptó el aviso de UAC, o se corrió el script directamente en vez de `INSTALAR-EHS-NATIVO.cmd`. Volver a hacer doble clic en el `.cmd` |
| "El disco reporta sectores de … bytes, que SQL Server no soporta" | Corrección automática ya aplicada (es un ajuste conocido de Microsoft para discos NVMe recientes): **reiniciar Windows** y volver a correr `INSTALAR-EHS-NATIVO.cmd` — continúa donde quedó |
| "Windows tiene un reinicio pendiente" | Reiniciar el equipo (hay una actualización de Windows esperando) y volver a instalar |
| "El instalador de SQL Server terminó con código …" | El detalle completo queda en `C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt`: ese archivo es lo que hay que reportar |
| "Una directiva de IT (…) impide correr los scripts de EHS" | La política de ejecución del equipo es `AllSigned` o `Restricted`: IT |
| "El puerto 14330 ya lo usa otro programa" | Casi siempre otra instancia de SQL Server ya instalada en ese equipo. Elegir otro puerto: `instalar.ps1 -Motor nativo -PuertoMotor <otro> -RutaInstaladorSqlExpress ...` (IT) |
| "Hay un motor EHS de un intento anterior, pero no su configuración" | Se instaló antes desde **otra carpeta**. El desinstalar de `C:\EHS` no sirve: sin su `ehs.env` no sabe qué retirar. Sin dato real: `desinstalar.ps1 -BorrarDatoTambien` de **esa** carpeta (como Administrador), escribir `BORRAR` y reinstalar. Con dato real: `DESINSTALAR-EHS.cmd` de esa carpeta (conserva), copiar su `app\config\ehs.env` a `C:\EHS\app\config\` y reinstalar |
| "El motor de un intento anterior no acepta las claves" | Quedó un intento anterior a medias sin dato real: PowerShell como Administrador, `desinstalar.ps1 -BorrarDatoTambien` (borra motor, respaldos locales y configuración), escribir `BORRAR` y volver a instalar |
| El navegador no puede conectarse a `127.0.0.1:3210` y F5 no lo arregla | El tablero no está corriendo: **Reparar EHS** lo arranca; después F5 |
| La franja se pone roja, o la página del motor no se va en unos minutos | Doble clic en **Reparar EHS**: reinicia el servicio de SQL Server y el tablero, y confirma que responden. No pide administrador |
| Reparar termina con un mensaje en rojo | Ese mensaje, tal cual, es lo que hay que reportar |

## 6. Qué se verificó, y qué falta

El código (`instalar.ps1`, `reparar.ps1`, `desinstalar.ps1` en modo nativo) se revisó
línea por línea el 28-sep-2026: mismas migraciones y mismos logins que el modo
contenedor ya probado en vivo, TCP restringido a `127.0.0.1` verificado con
`Get-NetTCPConnection` antes de continuar (no solo "debería quedar así"), SQL Server
Browser apagado, y el permiso para que "Reparar EHS" reinicie el servicio sin
administrador delegado con `sc.exe sdset` **solo** sobre ese servicio — nada de esto
tocado a última hora, es la misma disciplina que el modo contenedor.

**Lo que falta, y hay que hacer antes de dar por cerrada la instalación real:** correr
`INSTALAR-EHS-NATIVO.cmd` de principio a fin en un equipo real, con administrador —
nadie lo ha hecho todavía. Es el mismo tipo de primera corrida que ya se hizo con el
modo contenedor el 23-sep-2026 (ver el historial de este documento): instalar, capturar
un mes, corregir con motivo, confirmar un aviso, comprobar el respaldo automático,
apagar el motor y ver que "Reparar" lo recupera, actualizar a una versión nueva,
desinstalar y reinstalar. Se recomienda hacerlo en el propio equipo destino, o en un
equipo de prueba equivalente, antes de dejarlo en producción.

## 7. Actualizar, desinstalar, dónde queda cada cosa

**Actualizar a una versión nueva:** copiar la carpeta `app\` nueva encima de
`C:\EHS\app` (se conserva `config\ehs.env`) y correr
`powershell -ExecutionPolicy Bypass -File C:\EHS\app\instalacion\actualizar.ps1`.
Aplica las migraciones que falten y reinicia el tablero. Sin administrador.

**Desinstalar:** pide administrador (retira el servicio de SQL Server). PowerShell como
Administrador: `powershell -ExecutionPolicy Bypass -File C:\EHS\app\instalacion\desinstalar.ps1`.
Toma un último respaldo antes de desinstalar, pero el dato queda solo en ese `.bak`:
reinstalar no lo restaura solo, hay que restaurarlo a mano.

| Qué | Dónde |
|---|---|
| La aplicación | `C:\EHS\app` |
| Claves de la base (no compartir) | `C:\EHS\app\config\ehs.env` |
| Respaldos y registro del último | `C:\EHS\ehs-datos\respaldo\` |
| El motor | Servicio de Windows `MSSQL$EHSLOCAL`, dato en `C:\EHS\ehs-datos\motor\` |
| Arranque automático | `EHS Tablero.lnk` en la carpeta Inicio de la persona |
| Íconos | `EHS` y `Reparar EHS` en su escritorio |

---

## Alternativa: modo contenedor (Docker)

Si más adelante EssilorLuxottica resuelve la licencia de Docker Business (o decide usar
Podman/Rancher Desktop, gratis), `INSTALAR-EHS.cmd` instala el mismo tablero con SQL
Server en un contenedor, sin pedir administrador para el día a día (Docker Desktop sí lo
instala IT, una vez, con administrador — el mismo tipo de paso que el modo nativo
necesita). El esquema, las migraciones y las pantallas son exactamente los mismos.

Este camino sí se probó de punta a punta, el 23-sep-2026, en el equipo de Samuel
(Windows 11, Docker Desktop 28.3.2), sin administrador:

| Prueba | Resultado |
|---|---|
| `INSTALAR-EHS.cmd` de principio a fin, cargando la imagen desde el paquete | ✅ 103 s, código 0 |
| Motor y tablero escuchando **solo** en `127.0.0.1` (puertos 14330 y 3210) | ✅ |
| Tablero sin ventana, arranque al iniciar sesión, íconos del escritorio | ✅ |
| Histórico 2026 cargado (enero a julio) y los cinco indicadores | ✅ verificados contra el libro |
| Captura de un mes completo desde la pantalla, en dos tandas | ✅ |
| Corrección con motivo e historial | ✅ |
| Respaldo automático después de capturar | ✅ |
| Motor detenido → página legible → vuelve sola cuando el motor arranca | ✅ |
| **Reparar EHS** con el motor caído | ✅ 17 s |
| `actualizar.ps1` (aplicar una versión nueva) | ✅ |
| Desinstalar y reinstalar | ✅ |

Requisitos y pasos completos: ver `requisitos-it.md`, sección "Alternativa: modo
contenedor". En resumen: Docker Desktop instalado y abierto una vez (con administrador,
igual que el paso único que pide el modo nativo), la cuenta de la persona en el grupo
`docker-users`, y doble clic en `INSTALAR-EHS.cmd`.
