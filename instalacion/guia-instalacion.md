# EHS en el equipo del área: instalación paso a paso

La versión final se instala **en modo contenedor y sin administrador**: un doble clic
en `INSTALAR-EHS.cmd`, con Docker Desktop abierto. Tarda unos dos minutos.

El modo nativo (SQL Server Express como servicio de Windows) queda como plan B en
`INSTALAR-EHS-NATIVO.cmd`, para un equipo donde Docker no sea posible. Ese sí pide
administrador una vez.

---

## 1. Antes: lo que el equipo necesita

| Qué | Cómo saber si ya está |
|---|---|
| Windows 10 u 11 de 64 bits, 8 GB de RAM, unos 4 GB libres en disco | Configuración → Sistema → Información |
| **Docker Desktop instalado** | Aparece en el menú Inicio |
| La cuenta de la persona en el grupo `docker-users` | Al abrir Docker Desktop no sale un error de permisos |
| Docker Desktop **abierto**, con el motor corriendo | La ballena en la barra de tareas; en Docker Desktop, abajo a la izquierda, *Engine running* |

Instalar Docker Desktop **sí** pide administrador. Si el equipo no lo tiene, eso lo
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
3. **Abre Docker Desktop** y espera a que diga *Engine running*.
4. **Doble clic en `C:\EHS\INSTALAR-EHS.cmd`.** Si Windows pregunta "¿Desea ejecutar
   este archivo?" (pasa cuando el .zip vino de internet o de un correo), responde
   **Ejecutar**. No aparece ningún aviso de administrador.
5. **Espera unos dos minutos.** La ventana va mostrando cada paso. Al terminar dice
   `Instalacion terminada` y se abre el tablero en el navegador. Presiona una tecla
   para cerrar la ventana.
6. **Comprueba** que arriba del tablero la franja dice **"Motor conectado"** con el
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
  - El tablero publica el mes cuando están **las 27**. Mientras tanto, la pantalla de
    captura dice cuántas van y cuáles faltan, y marca en gris las ya capturadas.
- **Consultar y corregir**: para cambiar un número ya capturado. Pide el motivo, y el
  valor anterior queda en el historial con quién lo cambió y cuándo.
- **Descargar reporte**: el resumen para imprimir o guardar como PDF, y el detalle en
  CSV.

El respaldo es automático: uno después de cada captura o corrección (varias dentro del mismo
minuto quedan cubiertas por un solo respaldo al cumplirse el minuto) y uno diario, en
`C:\EHS\ehs-datos\respaldo\` (se guardan los 14 más recientes), y una copia en la
carpeta `EHS-respaldo` del OneDrive **corporativo** si está configurado en el equipo.
La franja de arriba dice cuándo fue el último.

## 4. Al encender el equipo

No hay que hacer nada. Docker Desktop y el tablero arrancan solos al iniciar sesión
(el instalador dejó los dos configurados). El motor tarda uno o dos minutos en estar
listo: si se abre EHS antes, sale "El motor de datos todavía no responde" y la página
lo vuelve a intentar sola cada 15 segundos.

## 5. Si algo falla

| Qué se ve | Qué hacer |
|---|---|
| "Ni docker ni podman estan disponibles" | Docker Desktop no está instalado: IT (sección 1) |
| "docker esta instalado pero no responde" | Abrir Docker Desktop, esperar *Engine running* y volver a correr `INSTALAR-EHS.cmd`. Si nunca llega a *Engine running*: IT |
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

Lo que **no** se probó todavía: el modo nativo en un equipo real, y Podman o Rancher
Desktop en lugar de Docker Desktop (el instalador los detecta, pero no se han corrido).

## 7. Actualizar, desinstalar, dónde queda cada cosa

**Actualizar a una versión nueva:** copiar la carpeta `app\` nueva encima de
`C:\EHS\app` (se conserva `config\ehs.env`) y correr
`powershell -ExecutionPolicy Bypass -File C:\EHS\app\instalacion\actualizar.ps1`.
Aplica las migraciones que falten y reinicia el tablero. Sin administrador.

**Desinstalar:** doble clic en `DESINSTALAR-EHS.cmd`. Con Docker toma un último respaldo
y **conserva** el dato (el volumen del motor, `ehs-datos` y la configuración), así que
volver a instalar recupera todo. Devuelve Docker Desktop a su ajuste anterior de arranque.
Con el plan B (nativo) hace falta PowerShell como Administrador, desinstala SQL Server y el
dato queda solo en el último `.bak`: reinstalar no lo restaura solo.

**Plan B (nativo):** pide administrador para instalar y para desinstalar. Si el permiso lo
da la cuenta de IT, el tablero arranca en el siguiente inicio de sesión de la persona. El
paquete trae `SQLEXPR_x64_ESN.exe`, que solo instala sobre Windows en español; para otro
idioma, armar el paquete con `SQLEXPR_x64_ENU.exe`.

| Qué | Dónde |
|---|---|
| La aplicación | `C:\EHS\app` |
| Claves de la base (no compartir) | `C:\EHS\app\config\ehs.env` |
| Respaldos y registro del último | `C:\EHS\ehs-datos\respaldo\` |
| El motor | Contenedor `ehs-motor` y volumen `ehs-motor-datos`, en Docker Desktop |
| Arranque automático | `EHS Tablero.lnk` en la carpeta Inicio de la persona |
| Íconos | `EHS` y `Reparar EHS` en su escritorio |
