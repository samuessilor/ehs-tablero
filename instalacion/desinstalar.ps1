#Requires -Version 5.1
<#
.SYNOPSIS
    Retira EHS de este equipo: tareas programadas, accesos directos, el motor.

.DESCRIPTION
    Por defecto CONSERVA el dato (el volumen del contenedor o los archivos del
    motor nativo, y la carpeta de respaldo): desinstalar la aplicacion no es lo
    mismo que decidir borrar informacion operativa de la empresa, y una cosa no
    debe arrastrar la otra por accidente. -BorrarDatoTambien lo hace explicito
    y pide una confirmacion aparte antes de tocar nada irreversible.

.PARAMETER BorrarDatoTambien
    Ademas de desinstalar, borra el volumen/carpeta de datos del motor y la
    carpeta de respaldo local. Pide confirmacion escrita antes de proceder.
#>
[CmdletBinding()]
param(
    [switch]$BorrarDatoTambien
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
$RaizPaquete = Split-Path -Parent $RaizApp
$ArchivoConfig = Join-Path $RaizApp 'config\ehs.env'

function Leer-Config {
    if (-not (Test-Path $ArchivoConfig)) { return @{} }
    $variables = @{}
    foreach ($linea in Get-Content $ArchivoConfig) {
        $t = $linea.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 0) { continue }
        $variables[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $variables
}

$cfg = Leer-Config

Write-Host "=== EHS · desinstalar ===" -ForegroundColor Cyan

# ------------------------------------------------------------------- lo automatico

foreach ($tarea in @('EHS Tablero', 'EHS Respaldo diario')) {
    if (Get-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $tarea -Confirm:$false
        Write-Host "Tarea programada '$tarea' retirada."
    }
}

$escritorio = [Environment]::GetFolderPath('Desktop')
foreach ($acceso in @('EHS.lnk', 'Reparar EHS.lnk')) {
    $ruta = Join-Path $escritorio $acceso
    if (Test-Path $ruta) {
        Remove-Item $ruta -Force
        Write-Host "Acceso directo '$acceso' retirado."
    }
}

# --------------------------------------------------------------------- el motor

if ($cfg['EHS_MOTOR'] -eq 'contenedor') {
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($herramienta) {
        & $herramienta stop ehs-motor 2>$null | Out-Null
        & $herramienta rm ehs-motor 2>$null | Out-Null
        Write-Host "Contenedor del motor detenido y retirado."
        if ($BorrarDatoTambien) {
            & $herramienta volume rm ehs-motor-datos 2>$null | Out-Null
            Write-Host "Volumen de datos del motor borrado." -ForegroundColor Yellow
        } else {
            Write-Host "El volumen de datos (ehs-motor-datos) se CONSERVA. Usa -BorrarDatoTambien para borrarlo tambien."
        }
    }
} else {
    Write-Host "Motor nativo: este script no desinstala SQL Server Express — se hace desde " -NoNewline
    Write-Host "Agregar o quitar programas de Windows, como cualquier otro programa instalado." -ForegroundColor Yellow
}

# -------------------------------------------------------------------- el dato local

if ($BorrarDatoTambien) {
    Write-Host ""
    Write-Warning "Vas a borrar la carpeta de datos local de EHS, incluidos los respaldos que no hayan llegado a OneDrive todavia."
    $confirmacion = Read-Host 'Escribe BORRAR para confirmar (cualquier otra cosa cancela)'
    if ($confirmacion -eq 'BORRAR') {
        $carpetaDatos = Join-Path $RaizPaquete 'datos'
        if (Test-Path $carpetaDatos) {
            Remove-Item $carpetaDatos -Recurse -Force
            Write-Host "Carpeta de datos local borrada: $carpetaDatos" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Cancelado: el dato local no se toco."
    }
}

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "La carpeta de la aplicacion ($RaizApp) no se borro: bórrala a mano si ya no la necesitas."
