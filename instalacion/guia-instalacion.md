# EHS en el equipo del área: instalación paso a paso

La versión final se instala **en modo contenedor y sin administrador**: un doble clic
en `INSTALAR-EHS.cmd`, con Docker Desktop instalado. Tarda unos dos minutos, y deja todo
configurado: base, histórico 2026, íconos, arranque solo al encender y respaldos.

El modo nativo (SQL Server Express como servicio de Windows) queda como plan B en
`INSTALAR-EHS-NATIVO.cmd`, para un equipo donde Docker no sea posible. Ese sí pide
administrador, para instalar y para desinstalar, y toca más cosas del sistema; la tabla
comparativa de permisos está en [requisitos-it.md](requisitos-it.md). Por eso el
contenedor es el camino principal.

---

## 1. Antes: lo que el equipo necesita

| Qué | Cómo saber si ya está |
|---|---|
| Windows 10 u 11 de 64 bits, 8 GB de RAM, unos 4 GB libres en disco | Configuración → Sistema → Información |
| **Docker Desktop instalado** | Aparece en el menú Inicio |
| La cuenta de la persona en el grupo `docker-users` | Al abrir Docker Desktop no sale un error de permisos |
| Docker Desktop **abierto una vez** tras instalarlo, con sus términos aceptados | Después ya no hace falta abrirlo a mano: el instalador y el tablero lo abren solos |

Para comprobar todo esto de una vez, sin instalar nada: doble clic en
`VERIFICAR-EQUIPO.cmd`. Solo lee y termina con un resumen de lo que falta.

Instalar Docker Desktop **sí** pide administrador (salvo la instalación "solo para el
usuario" de Docker, que exige tener WSL 2 ya activo). Si el equipo no lo tiene, eso lo
hace IT una vez: ver [requisitos-it.md](requisitos-it.md), que además explica la
licencia. En resumen: para uso de trabajo en EssilorLuxottica, Docker Desktop requiere
suscripción paga (Docker Business), sin importar lo pequeño del proyecto. Rancher
Desktop o Podman Desktop son gratis y sirven igual.

No hace falta internet: la imagen del motor viaja dentro del paquete.

## 2. Instalar

1. **Copia `paquete.zip` al equipo** (USB, OneDrive, correo; lo que sea más fácil).
2. **Clic derecho → Extraer todo… → `C:\EHS`.** No en Descargas ni en el Escritorio:
   esa carpeta es la instalación y no se debe mover después. Quedan
   `C:\EHS\INSTALAR-EHS.cmd`, `app\`, `node\` e `instaladores\`.
3. **Doble clic en `C:\EHS\INSTALAR-EHS.cmd`.** Si Docker Desktop está cerrado, el
   instalador lo abre y espera a que esté listo. Si Windows pregunta "¿Desea ejecutar
   este archivo?" (pasa cuando el .zip vino de internet o de un correo), responde
   **Ejecutar**. No aparece ningún aviso de administrador.
4. **Espera unos dos minutos.** La ventana va mostrando cada paso. Al terminar dice
   `Instalacion terminada` y se abre el tablero en el navegador. Presiona una tecla
   para cerrar la ventana.
5. **Comprueba** que arriba del tablero la franja dice **"Motor conectado"** con el
   punto verde, y que en el escritorio quedaron dos íconos: **EHS** y **Reparar EHS**.

Si algo falla, la ventana lo dice en rojo y **no se pierde nada**: se corrige lo que
diga el mensaje (tabla de la sección 5) y se vuelve a hacer doble clic en
`INSTALAR-EHS.cmd`. Volver a correrlo es seguro.

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
- **06 Datos** (pestaña del tablero): las lecturas tal como están en la base y, por cada
  indicador, numerador, denominador y resultado del mes y del acumulado, que es lo que
  dibujan las gráficas. Cada fila dice **cuadra** si las lecturas dan lo que usa el
  cálculo. Con un sitio elegido, el lápiz ✎ de cada lectura abre su corrección.
- **Descargar reporte**: el resumen para imprimir o guardar como PDF, y el detalle en
  CSV.

El respaldo es automático: uno después de cada captura o corrección (varias dentro del mismo
minuto quedan cubiertas por un solo respaldo al cumplirse el minuto) y uno diario, en
`C:\EHS\ehs-datos\respaldo\` (se guardan los 14 más recientes), y una copia en la
carpeta `EHS-respaldo` del OneDrive **corporativo** si está configurado en el equipo.
La franja de arriba dice cuándo fue el último.

## 4. Al encender el equipo

No hay que hacer nada. El tablero arranca solo al iniciar sesión y, si Docker Desktop no
está abierto, lo abre él mismo. El motor tarda uno o dos minutos en estar
listo: si se abre EHS antes, sale "El motor de datos todavía no responde" y la página
lo vuelve a intentar sola cada 15 segundos.

## 5. Si algo falla

| Qué se ve | Qué hacer |
|---|---|
| "Ni docker ni podman estan disponibles" | Docker Desktop no está instalado: IT (sección 1) |
| "docker esta instalado pero no responde" | El instalador ya intentó abrirlo tres minutos. Abrir Docker Desktop a mano (la primera vez, aceptar sus términos), esperar *Engine running* y volver a correr `INSTALAR-EHS.cmd`. Si nunca llega: IT |
| "Docker responde 'acceso denegado': la cuenta … no esta en el grupo local docker-users" | IT agrega la cuenta a `docker-users`; se cierra sesión y se vuelve a instalar |
| "Una directiva de IT (…) impide correr los scripts de EHS" | La política de ejecución del equipo es `AllSigned` o `Restricted`: IT |
| "El puerto 14330 ya lo usa otro programa" | Casi siempre un EHS anterior instalado **sin Docker** (plan B). `DESINSTALAR-EHS.cmd` con doble clic no lo retira porque necesita administrador: IT corre, en PowerShell como Administrador, el `desinstalar.ps1` de la carpeta donde se instaló ese EHS. Si no es EHS, avisar |
| "Hay un motor EHS de un intento anterior, pero no su configuracion" | Se instaló antes desde **otra carpeta**. El desinstalar de `C:\EHS` no sirve: sin su `ehs.env` no sabe qué retirar. Sin dato real: `desinstalar.ps1 -BorrarDatoTambien` de **esa** carpeta, escribir `BORRAR` y reinstalar. Con dato real: `DESINSTALAR-EHS.cmd` de esa carpeta (conserva), copiar su `app\config\ehs.env` a `C:\EHS\app\config\` y reinstalar. Si la carpeta ya no existe: no borrar nada y avisar |
| "El motor de un intento anterior no acepta las claves" | Quedó un intento anterior a medias sin dato real: `powershell -ExecutionPolicy Bypass -File C:\EHS\app\instalacion\desinstalar.ps1 -BorrarDatoTambien`, escribir `BORRAR` (borra motor, respaldos locales y configuración) y volver a instalar |
| El navegador no puede conectarse a `127.0.0.1:3210` y F5 no lo arregla | El tablero no está corriendo: **Reparar EHS** lo arranca; después F5 |
| La franja se pone roja, o la página del motor no se va en 3 minutos | Doble clic en **Reparar EHS**: abre Docker Desktop si está cerrado, reinicia el motor y el tablero, y confirma que responden |
| Reparar termina con un mensaje en rojo | Ese mensaje, tal cual, es lo que hay que reportar |

Con Podman Desktop o Rancher Desktop (motor *dockerd*) el instalador funciona, pero el
arranque automático y **Reparar EHS** están hechos para Docker Desktop: con ellos hay que
dejar el motor arrancando solo a mano. Todavía no probados.

## 6. Qué se probó, y dónde

El 23 de septiembre de 2026, en el equipo de Samuel (Windows 11, Docker Desktop
28.3.2), con el paquete final, **sin administrador**:

| Prueba | Resultado |
|---|---|
| `INSTALAR-EHS.cmd` de principio a fin, cargando la imagen desde el paquete | ✅ 103 s, código 0 |
| Motor y tablero escuchando **solo** en `127.0.0.1` (puertos 14330 y 3210) | ✅ |
| Tablero sin ventana, arranque al iniciar sesión, íconos del escritorio | ✅ |
| Histórico 2026 cargado (enero a julio) y los cinco indicadores | ✅ verificados contra el libro (p. ej. frequency rate 0,613 a julio) |
| Captura de un mes completo desde la pantalla, en dos tandas (25 + 2 lecturas) | ✅ el tablero pasó solo a corte agosto |
| Corrección con motivo e historial | ✅ |
| Respaldo automático después de capturar | ✅ |
| Motor detenido → página legible → vuelve sola cuando el motor arranca | ✅ |
| **Reparar EHS** con el motor caído | ✅ 17 s |
| `actualizar.ps1` (aplicar una versión nueva) | ✅ |
| Desinstalar y reinstalar | ✅ |

Lo que **no** se probó todavía: el modo nativo de punta a punta (el intento del 28-sep se
detuvo en el idioma del medio de SQL Server: ver requisitos-it.md); Podman o Rancher
Desktop en lugar de Docker Desktop (el instalador los detecta, pero no se han corrido); y
que el instalador o el tablero abran Docker Desktop cuando está cerrado: la lógica se
probó con otro programa, pero cerrar Docker en el equipo de prueba habría detenido los
demás contenedores que corren ahí.

### Además, el 28-sep-2026, después de reiniciar Windows (mismo equipo, misma instalación)

| Prueba | Resultado |
|---|---|
| Al reiniciar el equipo, sin hacer nada: Docker Desktop, el motor (`ehs-motor`, política `unless-stopped`) y el tablero arrancan solos | ✅ el tablero quedó "Motor conectado" |
| Motor y tablero escuchando **solo** en `127.0.0.1` | ✅ |
| Todo lo anterior con la cuenta normal, **sin elevar** (la cuenta está en `docker-users`) | ✅ |
| `actualizar.ps1` (migraciones + permisos + reinicio del tablero) | ✅ 31 s |
| Motor detenido a propósito → página de espera legible (503) → **Reparar EHS** | ✅ 20 s, sin administrador |
| Respaldo (`respaldar.ps1`) | ✅ `.bak` nuevo de 7,2 MB; la franja de arriba lo reportó |
| Las 605 respuestas de la API y las páginas, contra el despliegue de prueba en Vercel | ✅ 614 comparaciones, 0 diferencias |

Restaurar un `.bak` necesita la clave de `sa`, que el instalador cambia al terminar y no
guarda (`ehs_migrador` no puede restaurar): en modo contenedor se restablece con
`mssql-conf set-sa-password`. Hoy ese procedimiento lo hace IT y no se ha ensayado.

## 7. Actualizar, desinstalar, dónde queda cada cosa

**Actualizar a una versión nueva:** copiar la carpeta `app\` nueva encima de
`C:\EHS\app` (se conserva `config\ehs.env`) y correr
`powershell -ExecutionPolicy Bypass -File C:\EHS\app\instalacion\actualizar.ps1`.
Aplica las migraciones que falten y reinicia el tablero. Sin administrador.

**Desinstalar:** doble clic en `DESINSTALAR-EHS.cmd`. Con Docker toma un último respaldo
y **conserva** el dato (el volumen del motor, `ehs-datos` y la configuración), así que
volver a instalar recupera todo. No cambia ningún ajuste de Docker Desktop.
Con el plan B (nativo) hace falta PowerShell como Administrador, desinstala SQL Server y el
dato queda solo en el último `.bak`: reinstalar no lo restaura solo.

**Plan B (nativo):** pide administrador para instalar y para desinstalar. Si el permiso lo
da la cuenta de IT, el tablero arranca en el siguiente inicio de sesión de la persona. El
paquete trae el descargador oficial de Microsoft (`SQL2022-SSEI-Expr.exe`), que baja el
medio en inglés al instalar (necesita internet): el medio en español de España falla en un
Windows con formato regional de Colombia (es-CO). Detalle en requisitos-it.md.

| Qué | Dónde |
|---|---|
| La aplicación | `C:\EHS\app` |
| Claves de la base (no compartir) | `C:\EHS\app\config\ehs.env` |
| Respaldos y registro del último | `C:\EHS\ehs-datos\respaldo\` |
| El motor | Contenedor `ehs-motor` y volumen `ehs-motor-datos`, en Docker Desktop |
| Arranque automático | `EHS Tablero.lnk` en la carpeta Inicio de la persona |
| Íconos | `EHS` y `Reparar EHS` en su escritorio |
