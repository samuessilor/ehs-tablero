#Requires -Version 5.1
<#
.SYNOPSIS
    Arma la carpeta que se lleva al equipo del area: la app, node.exe portable, el
    instalador de SQL Server 2022 Express y dos archivos de doble clic. Corre en la
    maquina de desarrollo (con internet), nunca en la de destino.

.DESCRIPTION
    Resultado:

      paquete\
        INSTALAR-EHS.cmd       doble clic: pide administrador (UAC) e instala
        DESINSTALAR-EHS.cmd    doble clic: retira EHS conservando el dato
        LEEME.txt
        app\                   la aplicacion, con node_modules SOLO de produccion
        node\node.exe          Node 22 portable: el equipo del area no instala Node
        instaladores\          SQLEXPR_x64_*.exe (y, opcional, la imagen del contenedor)

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
    Ademas guarda la imagen de SQL Server 2022 para el modo contenedor (plan B), con
    'docker save'. Pesa ~1,5 GB y hace que el .zip no se pueda armar (limite de 2 GB
    de Compress-Archive): se lleva la carpeta tal cual.

.PARAMETER ImagenContenedor
    Que imagen guardar con -ConImagenContenedor. Por defecto la que se probo.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$RutaNodePortable,
    [Parameter(Mandatory = $true)] [string]$RutaMedioSql,
    [string]$CarpetaSalida,
    [switch]$ConImagenContenedor,
    [string]$ImagenContenedor = 'mcr.microsoft.com/mssql/server:2022-latest'
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
    Write-Host "La carpeta de salida ya existe: se arma de nuevo desde cero."
    Remove-Item $CarpetaSalida -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PaqueteApp, $PaqueteNode, $PaqueteInstaladores | Out-Null

# ------------------------------------------------------------------- la app

# Rutas COMPLETAS en /XD: con un nombre suelto, robocopy excluye toda carpeta que se
# llame asi en cualquier nivel (asi se perdian las 'config' de node_modules).
$excluir = @('.git', '.vercel', 'node_modules', 'config', 'datos') | ForEach-Object { Join-Path $RaizApp $_ }
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

if ($ConImagenContenedor) {
    Write-Host "Guardando la imagen $ImagenContenedor (plan B, modo contenedor)…"
    & docker image inspect $ImagenContenedor *> $null
    if ($LASTEXITCODE -ne 0) { throw "No esta la imagen $ImagenContenedor en esta maquina (docker pull primero)." }
    & docker save -o (Join-Path $PaqueteInstaladores 'mssql-server-2022.tar') $ImagenContenedor
    if ($LASTEXITCODE -ne 0) { throw "docker save termino con codigo $LASTEXITCODE." }
}

# ------------------------------------------------------- los doble clic

# Los .cmd no hacen nada por su cuenta: piden el permiso de administrador (UAC) — si
# la persona del area es usuaria estandar, alli escribe IT su usuario y clave — y
# le pasan el control a instalar.ps1 / desinstalar.ps1. -NoExit deja la ventana
# abierta al terminar para leer el resultado.
#
# Unblock-File: un .zip traido de OneDrive o de un correo marca cada archivo como
# "descargado de internet", y con la directiva RemoteSigned esos .ps1 no corren.
# Es lo mismo que hacer clic en "Desbloquear" en Propiedades, archivo por archivo.
$instalarCmd = @"
@echo off
setlocal
set "RAIZ=%~dp0"
set "MEDIO=%RAIZ%instaladores\$nombreMedio"
if not exist "%MEDIO%" (
  echo No se encuentra el instalador de SQL Server: %MEDIO%
  pause
  exit /b 1
)
echo Preparando la instalacion de EHS...
powershell.exe -NoProfile -Command "Get-ChildItem -LiteralPath '%RAIZ%' -Recurse -File | Unblock-File"
powershell.exe -NoProfile -Command "`$p = Get-ExecutionPolicy -Scope MachinePolicy; `$u = Get-ExecutionPolicy -Scope UserPolicy; if (@(`$p, `$u) | Where-Object { `$_ -in 'AllSigned', 'Restricted' }) { Write-Host ('Una directiva de IT (' + `$p + ' / ' + `$u + ') impide correr los scripts de EHS. Pide a IT que los permita en este equipo.') -ForegroundColor Red; exit 1 }"
if errorlevel 1 ( pause & exit /b 1 )
echo Windows va a pedir permiso de administrador (una sola vez).
powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%RAIZ%app\instalacion\instalar.ps1\" -Motor nativo -RutaInstaladorSqlExpress \"%MEDIO%\" -ConDatosSemilla')"
"@
$desinstalarCmd = @"
@echo off
setlocal
set "RAIZ=%~dp0"
echo Windows va a pedir permiso de administrador para retirar EHS (el dato se conserva).
powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%RAIZ%app\instalacion\desinstalar.ps1\"')"
"@
[IO.File]::WriteAllText((Join-Path $CarpetaSalida 'INSTALAR-EHS.cmd'), $instalarCmd.Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $CarpetaSalida 'DESINSTALAR-EHS.cmd'), $desinstalarCmd.Replace("`n", "`r`n"), [Text.Encoding]::ASCII)

@"
EHS - tablero de indicadores
============================

Para instalar: doble clic en INSTALAR-EHS.cmd.
Windows pide permiso de administrador una vez (si la cuenta no es administradora,
alli escribe IT su usuario y clave). Tarda unos 10 minutos. Al final se abre el
tablero y quedan dos iconos en el escritorio: EHS y Reparar EHS.

No hace falta internet. No hay que instalar nada mas.

Detalle completo: app\instalacion\guia-instalacion.md
"@.Replace("`n", "`r`n") | Set-Content -Path (Join-Path $CarpetaSalida 'LEEME.txt') -Encoding ASCII

# ------------------------------------------------------------------------- zip

$tamano = (Get-ChildItem $CarpetaSalida -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("Tamano del paquete: {0:N0} MB" -f ($tamano / 1MB))
if ($tamano -lt 1.9GB) {
    $rutaZip = "$CarpetaSalida.zip"
    if (Test-Path $rutaZip) { Remove-Item $rutaZip -Force }
    Write-Host "Comprimiendo…"
    Compress-Archive -Path "$CarpetaSalida\*" -DestinationPath $rutaZip -CompressionLevel Optimal
    Write-Host "Paquete: $rutaZip" -ForegroundColor Green
} else {
    Write-Host "Pasa de 2 GB (Compress-Archive no puede): lleva la carpeta $CarpetaSalida tal cual." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "En el equipo del area: extraer en una carpeta fija (p. ej. C:\EHS) y doble clic en INSTALAR-EHS.cmd."
