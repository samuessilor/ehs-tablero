#Requires -Version 5.1
<#
.SYNOPSIS
    Aplica una version nueva de la aplicacion ya copiada sobre esta carpeta:
    corre las migraciones que falten y reinicia el tablero.

.DESCRIPTION
    Este script asume que ya se copio una version nueva de app\ (con nuevas
    migraciones numeradas, si las hay) ENCIMA de la instalacion actual — la
    copia de archivos no la hace este script, porque eso puede ser un simple
    reemplazo de carpeta o venir de un paquete distinto segun como lo distribuya
    IT. Lo que si hace, siempre igual:

      1. Corre scripts\migrar.js: aplica solo las migraciones nuevas, nunca
         repite las que ya estan en ops.migracion_aplicada.
      2. Vuelve a correr crear-logins.sql, por si la version nueva agrego un
         procedimiento que necesita un GRANT que todavia no existe (como paso
         con ehs.sp_corregir_lectura en esta misma sesion).
      3. Reinicia la tarea programada del tablero para que cargue el codigo
         nuevo del servidor.
#>
[CmdletBinding()]
param(
    [switch]$ConDatosSemilla
)

# 'Continue': un DeprecationWarning de Node en stderr no debe abortar la
# actualizacion; cada paso nativo comprueba su codigo de salida.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
$RaizPaquete = Split-Path -Parent $RaizApp
$NodeBundle = Join-Path $RaizPaquete 'node\node.exe'
$NodeExe = if (Test-Path $NodeBundle) { $NodeBundle } else { (Get-Command node -ErrorAction SilentlyContinue).Source }
if (-not $NodeExe) { throw "No se encontro node.exe." }

$ArchivoConfig = Join-Path $RaizApp 'config\ehs.env'
if (-not (Test-Path $ArchivoConfig)) { throw "No existe $ArchivoConfig. Esto no es una instalacion existente — usa instalar.ps1." }

function Leer-Config {
    $variables = @{}
    foreach ($linea in Get-Content $ArchivoConfig) {
        $t = $linea.Trim().TrimStart([char]0xFEFF)
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 0) { continue }
        $variables[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $variables
}
$cfg = Leer-Config

Write-Host "=== EHS · actualizar ===" -ForegroundColor Cyan

Write-Host "Aplicando migraciones pendientes…"
Push-Location $RaizApp
try {
    $env:SQL_SERVIDOR = $cfg['SQL_SERVIDOR']; $env:SQL_PUERTO = $cfg['SQL_PUERTO']
    $env:SQL_BASE = $cfg['SQL_BASE']; $env:SQL_CONFIAR_CERT = $cfg['SQL_CONFIAR_CERT']
    $env:SQL_CIFRAR = $cfg['SQL_CIFRAR']
    $env:SQL_MIGRADOR_USUARIO = $cfg['SQL_MIGRADOR_USUARIO']; $env:SQL_MIGRADOR_CLAVE = $cfg['SQL_MIGRADOR_CLAVE']
    $argsMigrar = @('scripts\migrar.js')
    if ($ConDatosSemilla) { $argsMigrar += '--con-datos-semilla' }
    & $NodeExe @argsMigrar
    if ($LASTEXITCODE -ne 0) { throw "migrar.js termino con codigo $LASTEXITCODE." }
} finally {
    Pop-Location
}

# Con las credenciales de config\ehs.env alcanza: ehs_migrador es db_owner de
# analitica (ver crear-logins.sql), asi que puede completar el GRANT EXECUTE de un
# procedimiento nuevo sin volver a pedir la clave de sa — que instalar.ps1 nunca
# guarda en ningun archivo, a proposito, porque solo hacia falta una vez.
Write-Host "Completando permisos sobre lo que la migracion haya agregado…"
$rutaScript = Join-Path $PSScriptRoot 'crear-logins.sql'
if ($cfg['EHS_MOTOR'] -eq 'contenedor') {
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    & $herramienta cp $rutaScript "ehs-motor:/tmp/crear-logins.sql" | Out-Null
    & $herramienta exec ehs-motor /opt/mssql-tools18/bin/sqlcmd `
        -C -b -S localhost -U $cfg['SQL_MIGRADOR_USUARIO'] -P $cfg['SQL_MIGRADOR_CLAVE'] `
        -v ClaveMigrador=$($cfg['SQL_MIGRADOR_CLAVE']) ClaveApp=$($cfg['SQL_CLAVE']) `
        -i /tmp/crear-logins.sql
} else {
    & $cfg['EHS_SQLCMD'] -C -b -S "$($cfg['SQL_SERVIDOR']),$($cfg['SQL_PUERTO'])" `
        -U $cfg['SQL_MIGRADOR_USUARIO'] -P $cfg['SQL_MIGRADOR_CLAVE'] `
        -v ClaveMigrador=$($cfg['SQL_MIGRADOR_CLAVE']) ClaveApp=$($cfg['SQL_CLAVE']) `
        -i $rutaScript
}
if ($LASTEXITCODE -ne 0) { throw "crear-logins.sql termino con codigo $LASTEXITCODE." }

Write-Host "Reiniciando el tablero con el codigo nuevo…"
Stop-ScheduledTask -TaskName 'EHS Tablero' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName 'EHS Tablero'

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
