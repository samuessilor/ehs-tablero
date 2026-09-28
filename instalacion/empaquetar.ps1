#Requires -Version 5.1
<#
.SYNOPSIS
    Arma la carpeta que se lleva al equipo del area: la app, node.exe portable, el
    instalador de SQL Server 2022 Express y los archivos de doble clic. Corre en la
    maquina de desarrollo (con internet), nunca en la de destino.

.DESCRIPTION
    Resultado:

      paquete\
        INSTALAR-EHS.cmd         doble clic: modo contenedor, SIN administrador
        INSTALAR-EHS-NATIVO.cmd  doble clic: modo nativo, pide administrador (UAC)
        DESINSTALAR-EHS.cmd      doble clic: retira EHS conservando el dato
        PASOS-INSTALACION.html   el paso a paso para quien instala (doble clic)
        LEEME.txt
        app\                     la aplicacion, con node_modules SOLO de produccion
        node\node.exe            Node 22 portable: el equipo del area no instala Node
        instaladores\            SQLEXPR_x64_*.exe (y, opcional, la imagen del contenedor)

    node_modules se arma con 'npm ci --omit=dev' dentro del paquete, no copiando el
    de desarrollo: la version anterior copiaba con robocopy /XD 'config', que excluye
    TODAS las carpetas llamadas config — hay 15 dentro de node_modules, y sin ellas
    el driver de SQL Server (mssql -> @azure/msal-node) no carga.

.PARAMETER RutaNodePortable
    Carpeta del .zip "win-x64" de Node 22 ya extraido (la que contiene node.exe).

.PARAMETER RutaMedioSql
    El paquete offline de SQL Server 2022 Express (SQLEXPR_x64_ENU.exe o _ESN.exe).
    ENU se instala sobre Windows en cualquier idioma; ESN solo sobre Windows en espanol.

.PARAMETER ConImagenContenedor
    Ademas guarda la imagen de SQL Server 2022 para el modo contenedor, con
    'docker save', para instalar en un equipo SIN internet. La de 2022-latest pesa
    ~600 MB y el paquete completo ~1 GB, asi que el .zip todavia se arma (el limite de
    Compress-Archive es 2 GB). Sin esto, el equipo del area descarga la imagen al
    instalar. INSTALAR-EHS.cmd usa el .tar solo si esta en instaladores\.

.PARAMETER ImagenContenedor
    Que imagen guardar con -ConImagenContenedor. Por defecto la que se probo.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$RutaNodePortable,
    [Parameter(Mandatory = $true)] [string]$RutaMedioSql,
    [string]$CarpetaSalida,
    [switch]$ConImagenContenedor,
    [string]$ImagenContenedor = 'mcr.microsoft.com/mssql/server:2022-latest',
    # Un .tar de la imagen ya guardado antes (de un paquete anterior): se copia en vez de
    # volver a correr 'docker save', que es el paso que mas memoria pide. En el equipo de
    # desarrollo, con otros contenedores corriendo, Windows mato dos veces el empaquetado
    # justo ahi.
    [string]$RutaImagenTar
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
if (-not $CarpetaSalida) { $CarpetaSalida = Join-Path (Split-Path -Parent $RaizApp) 'paquete' }
$PaqueteApp = Join-Path $CarpetaSalida 'app'
$PaqueteNode = Join-Path $CarpetaSalida 'node'
$PaqueteInstaladores = Join-Path $CarpetaSalida 'instaladores'

Write-Host "=== EHS · empaquetar ===" -ForegroundColor Cyan
Write-Host "Origen : $RaizApp"
Write-Host "Salida : $CarpetaSalida"

$nodeOrigen = Join-Path $RutaNodePortable 'node.exe'
if (-not (Test-Path $nodeOrigen)) { throw "No hay node.exe en $RutaNodePortable." }
$versionNode = (& $nodeOrigen --version).Trim()
if ($versionNode -notlike 'v22.*') { throw "node.exe es $versionNode; el estandar fija Node 22." }
if (-not (Test-Path $RutaMedioSql)) { throw "No existe $RutaMedioSql." }
$firma = Get-AuthenticodeSignature $RutaMedioSql
if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw "$RutaMedioSql no trae una firma valida de Microsoft ($($firma.Status))."
}

if (Test-Path $CarpetaSalida) {
    # Nunca borrar una instalacion en uso: si alguien instalo DESDE esta carpeta, aqui
    # estan su dato (ehs-datos) y sus claves (config\ehs.env).
    if ((Test-Path (Join-Path $CarpetaSalida 'ehs-datos')) -or (Test-Path (Join-Path $PaqueteApp 'config\ehs.env'))) {
        throw ("$CarpetaSalida tiene una instalacion en uso (ehs-datos o config\ehs.env). Arma el paquete en otra " +
               "carpeta con -CarpetaSalida, o desinstala primero.")
    }
    Write-Host "La carpeta de salida ya existe: se arma de nuevo desde cero."
    Remove-Item $CarpetaSalida -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PaqueteApp, $PaqueteNode, $PaqueteInstaladores | Out-Null

# ------------------------------------------------------------------- la app

# Rutas COMPLETAS en /XD: con un nombre suelto, robocopy excluye toda carpeta que se
# llame asi en cualquier nivel (asi se perdian las 'config' de node_modules).
# 'datos' SI viaja: app\datos\datos.json es el manifiesto del corte (fuente, hallazgos
# del libro heredado, correcciones autorizadas) y adaptador_sql.js lo lee en cada
# panorama. Una version anterior lo excluia, y el tablero instalado respondia 503.
$excluir = @('.git', '.vercel', 'node_modules', 'config') | ForEach-Object { Join-Path $RaizApp $_ }
robocopy $RaizApp $PaqueteApp /E /XD @excluir /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy fallo copiando la app (codigo $LASTEXITCODE)." }

New-Item -ItemType Directory -Force -Path (Join-Path $PaqueteApp 'config') | Out-Null
Copy-Item (Join-Path $RaizApp 'config\ehs.env.ejemplo') (Join-Path $PaqueteApp 'config\ehs.env.ejemplo')

# La carga del historico 2026 del area (migracion 0008) no se versiona en git porque
# son cifras de la empresa, pero SI viaja en el paquete: va a un equipo de la propia
# empresa, y sin ella el tablero arrancaria vacio.
if (-not (Test-Path (Join-Path $PaqueteApp 'migraciones\0008_carga_inicial.sql'))) {
    Write-Warning "Falta migraciones\0008_carga_inicial.sql: el tablero arrancara sin el historico 2026 (generalo con analisis\generar_sql_carga.py)."
}

Write-Host "Instalando dependencias de produccion (npm ci --omit=dev)…"
Push-Location $PaqueteApp
try {
    & npm.cmd ci --omit=dev --no-audit --no-fund --loglevel=error
    if ($LASTEXITCODE -ne 0) { throw "npm ci termino con codigo $LASTEXITCODE." }
} finally {
    Pop-Location
}
foreach ($modulo in @('ejs', 'mssql', '@azure\msal-node')) {
    if (-not (Test-Path (Join-Path $PaqueteApp "node_modules\$modulo\package.json"))) {
        throw "Falta node_modules\$modulo en el paquete: sin eso la app no arranca contra SQL Server."
    }
}
# Prueba de humo con el MISMO node.exe que viaja: que el driver cargue de verdad.
& $nodeOrigen -e "require('$($PaqueteApp.Replace('\','/'))/node_modules/mssql'); console.log('mssql carga')"
if ($LASTEXITCODE -ne 0) { throw "El driver mssql no carga con el node.exe del paquete." }

# ------------------------------------------------------- node y SQL Server

Copy-Item $nodeOrigen $PaqueteNode
Copy-Item $RutaMedioSql $PaqueteInstaladores
$nombreMedio = Split-Path $RutaMedioSql -Leaf
if ($nombreMedio -notmatch '_ENU') {
    Write-Warning ("El medio de SQL Server es $nombreMedio, no ENU: el plan B (INSTALAR-EHS-NATIVO.cmd) de " +
                   "este paquete solo instala sobre Windows en ese mismo idioma. ENU sirve en cualquiera.")
}

if ($RutaImagenTar) {
    if (-not (Test-Path $RutaImagenTar)) { throw "-RutaImagenTar no existe: $RutaImagenTar" }
    Write-Host "Copiando la imagen del motor ya guardada ($RutaImagenTar)…"
    Copy-Item $RutaImagenTar (Join-Path $PaqueteInstaladores 'mssql-server-2022.tar')
} elseif ($ConImagenContenedor) {
    Write-Host "Guardando la imagen $ImagenContenedor (modo contenedor sin internet)…"
    & docker image inspect $ImagenContenedor *> $null
    if ($LASTEXITCODE -ne 0) { throw "No esta la imagen $ImagenContenedor en esta maquina (docker pull primero)." }
    & docker save -o (Join-Path $PaqueteInstaladores 'mssql-server-2022.tar') $ImagenContenedor
    if ($LASTEXITCODE -ne 0) { throw "docker save termino con codigo $LASTEXITCODE." }
}

# ------------------------------------------------------- los doble clic

# INSTALAR-EHS.cmd instala en modo CONTENEDOR y SIN administrador: corre en la misma
# ventana, sin aviso de Windows. Necesita Docker Desktop (o Podman) ya instalado y
# abierto en el equipo. Si el paquete trae la imagen (.tar, con -ConImagenContenedor)
# la carga sin internet; si no, usa la que ya este en Docker o la descarga.
#
# INSTALAR-EHS-NATIVO.cmd es el modo nativo (SQL Server Express como servicio de
# Windows): pide administrador (UAC) y no necesita Docker.
#
# Unblock-File: un .zip traido de OneDrive o de un correo marca cada archivo como
# "descargado de internet", y con la directiva RemoteSigned esos .ps1 no corren. Es lo
# mismo que "Desbloquear" en Propiedades, archivo por archivo.
$preparar = @"
echo Preparando la instalacion de EHS...
powershell.exe -NoProfile -Command "Get-ChildItem -LiteralPath '%RAIZ%' -Recurse -File | Unblock-File"
powershell.exe -NoProfile -Command "`$p = Get-ExecutionPolicy -Scope MachinePolicy; `$u = Get-ExecutionPolicy -Scope UserPolicy; if (@(`$p, `$u) | Where-Object { `$_ -in 'AllSigned', 'Restricted' }) { Write-Host ('Una directiva de IT (' + `$p + ' / ' + `$u + ') impide correr los scripts de EHS. Pide a IT que los permita en este equipo.') -ForegroundColor Red; exit 1 }"
if errorlevel 1 ( pause & exit /b 1 )
"@

$instalarCmd = @"
@echo off
setlocal
set "RAIZ=%~dp0"
$preparar
set "IMAGEN="
if exist "%RAIZ%instaladores\mssql-server-2022.tar" set "IMAGEN=-RutaImagen "%RAIZ%instaladores\mssql-server-2022.tar""
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RAIZ%app\instalacion\instalar.ps1" -Motor contenedor -ConDatosSemilla %IMAGEN%
if errorlevel 1 (
  echo.
  echo La instalacion NO termino. Lee el mensaje en rojo de arriba.
) else (
  echo.
  echo Instalacion terminada. En el escritorio quedaron EHS y Reparar EHS.
)
pause
"@

$instalarNativoCmd = @"
@echo off
setlocal
set "RAIZ=%~dp0"
set "MEDIO=%RAIZ%instaladores\$nombreMedio"
if not exist "%MEDIO%" (
  echo No se encuentra el instalador de SQL Server: %MEDIO%
  pause
  exit /b 1
)
$preparar
echo Windows va a pedir permiso de administrador (una sola vez).
powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%RAIZ%app\instalacion\instalar.ps1\" -Motor nativo -RutaInstaladorSqlExpress \"%MEDIO%\" -ConDatosSemilla')"
"@

$desinstalarCmd = @"
@echo off
setlocal
set "RAIZ=%~dp0"
echo Retirando EHS de este equipo (el dato se conserva: se toma un ultimo respaldo).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%RAIZ%app\instalacion\desinstalar.ps1"
pause
"@

[IO.File]::WriteAllText((Join-Path $CarpetaSalida 'INSTALAR-EHS.cmd'), $instalarCmd.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $CarpetaSalida 'INSTALAR-EHS-NATIVO.cmd'), $instalarNativoCmd.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $CarpetaSalida 'DESINSTALAR-EHS.cmd'), $desinstalarCmd.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)

@"
EHS - tablero de indicadores
============================

Para instalar: doble clic en INSTALAR-EHS-NATIVO.cmd. Windows pide confirmar el
permiso de administrador (UAC) UNA SOLA VEZ, para instalar SQL Server 2022 Express
como servicio de Windows. Tarda varios minutos. Al final se abre el tablero y
quedan dos iconos en el escritorio: EHS (el tablero) y Reparar EHS (si la franja
de arriba se pone roja). El tablero arranca solo cada vez que se inicia sesion en
Windows, sin volver a pedir administrador.

Alternativa, si el equipo ya tiene licencia de Docker Business resuelta:
INSTALAR-EHS.cmd instala el mismo tablero con SQL Server en un contenedor, sin
pedir administrador para instalar (Docker Desktop si lo pide, aparte, una vez).

Paso a paso completo: PASOS-INSTALACION.html (doble clic, se abre en el navegador).
"@.Replace("`r`n", "`n").Replace("`n", "`r`n") | Set-Content -Path (Join-Path $CarpetaSalida 'LEEME.txt') -Encoding ASCII

# La guia para quien instala, en la raiz del paquete: una pagina que se abre con doble
# clic y se imprime, sin internet. La fuente vive en app\instalacion.
Copy-Item (Join-Path $PSScriptRoot 'PASOS-INSTALACION.html') (Join-Path $CarpetaSalida 'PASOS-INSTALACION.html') -Force

# ------------------------------------------------------------------------- zip

$tamano = (Get-ChildItem $CarpetaSalida -Recurse -File | Measure-Object Length -Sum).Sum
$archivos = @(Get-ChildItem $CarpetaSalida -Recurse -File).Count
Write-Host ("Tamano del paquete: {0:N0} MB, {1} archivos" -f ($tamano / 1MB), $archivos)
$rutaZip = "$CarpetaSalida.zip"
if (Test-Path $rutaZip) { Remove-Item $rutaZip -Force }
Write-Host "Comprimiendo…"
# tar.exe (bsdtar, viene con Windows 10 y 11) comprime en streaming con poca memoria y
# sin el tope de 2 GB. Compress-Archive de PowerShell 5.1 es lento y pesado: en el
# equipo de desarrollo, con Docker ocupando la memoria, Windows lo mato a mitad y dejo
# un .zip de 15 MB que parecia bueno. Queda solo como respaldo si no hay tar.exe.
$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tar) {
    $raiz = @(Get-ChildItem $CarpetaSalida -Name)
    & $tar.Source -a -c -f $rutaZip -C $CarpetaSalida @raiz
    if ($LASTEXITCODE -ne 0) { throw "tar.exe termino con codigo $LASTEXITCODE armando $rutaZip." }
} elseif ($tamano -lt 1.9GB) {
    Compress-Archive -Path "$CarpetaSalida\*" -DestinationPath $rutaZip -CompressionLevel Optimal
} else {
    Write-Host "Sin tar.exe y pasa de 2 GB: lleva la carpeta $CarpetaSalida tal cual." -ForegroundColor Yellow
    $rutaZip = $null
}
if ($rutaZip) {
    # Un .zip cortado a la mitad se abre igual y parece bueno: se cuenta lo que trae.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($rutaZip)
    try {
        $enZip = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        $bytesEnZip = ($enZip | Measure-Object Length -Sum).Sum
    } finally { $zip.Dispose() }
    if ($enZip.Count -ne $archivos -or $bytesEnZip -ne $tamano) {
        throw ("El .zip no trae todo: {0} de {1} archivos, {2:N0} de {3:N0} bytes. No lo uses." -f
               $enZip.Count, $archivos, $bytesEnZip, $tamano)
    }
    Write-Host ("Paquete: {0} ({1:N0} MB, {2} archivos, completo)" -f $rutaZip, ((Get-Item $rutaZip).Length / 1MB), $archivos) -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "En el equipo del area: extraer en una carpeta fija (p. ej. C:\EHS) y doble clic en INSTALAR-EHS-NATIVO.cmd."
