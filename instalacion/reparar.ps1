#Requires -Version 5.1
<#
.SYNOPSIS
    El atajo "Reparar EHS": reinicia el motor y el tablero, y confirma que
    responden. Un doble clic, sin consola que leer.

.DESCRIPTION
    Es lo unico que la franja de estado le pide a quien usa el tablero cuando el
    punto se pone rojo (ver public/js/franja_estado.js). No reinstala nada, no
    toca el esquema ni el dato: solo reinicia lo que ya esta instalado y espera
    a que vuelva a responder.
#>
[CmdletBinding()]
param()

# 'Continue': un aviso benigno en stderr de docker no debe abortar la reparacion;
# cada paso comprueba su propio resultado.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
$ArchivoConfig = Join-Path $RaizApp 'config\ehs.env'

function Leer-Config {
    if (-not (Test-Path $ArchivoConfig)) { throw "No existe $ArchivoConfig. ¿Se corrio instalar.ps1?" }
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
$puertoMotor = $cfg['SQL_PUERTO']
$puertoApp = $cfg['PUERTO']

Write-Host "=== EHS · reparar ===" -ForegroundColor Cyan

# --------------------------------------------------------------------- el motor

Write-Host "Reiniciando el motor ($($cfg['EHS_MOTOR']))…"
if ($cfg['EHS_MOTOR'] -eq 'contenedor') {
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $herramienta) { throw "Ni docker ni podman estan disponibles." }
    & $herramienta restart ehs-motor | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "No se pudo reiniciar el contenedor (codigo $LASTEXITCODE). ¿Esta abierto Docker Desktop / Podman?" -ForegroundColor Red }
} else {
    # instalar.ps1 le dio a esta cuenta permiso de reiniciar SOLO este servicio: quien
    # usa el equipo no es administrador, y este atajo corre sin elevar.
    Restart-Service 'MSSQL$EHSLOCAL' -Force -ErrorAction Continue
}

$limite = (Get-Date).AddSeconds(60)
$listo = $false
while ((Get-Date) -lt $limite) {
    try {
        $cliente = New-Object System.Net.Sockets.TcpClient
        $cliente.Connect('127.0.0.1', [int]$puertoMotor)
        $cliente.Close()
        $listo = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $listo) {
    Write-Host "El motor no volvio a responder en 60 segundos." -ForegroundColor Red
    Write-Host "Esto ya no lo resuelve este atajo — hay que avisar con este mensaje tal cual." -ForegroundColor Red
    Read-Host "Presiona Enter para cerrar"
    exit 1
}
Write-Host "Motor arriba." -ForegroundColor Green

# --------------------------------------------------------------------- la app

Write-Host "Reiniciando el tablero…"
Stop-ScheduledTask -TaskName 'EHS Tablero' -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName 'EHS Tablero'

$limite = (Get-Date).AddSeconds(30)
$appLista = $false
while ((Get-Date) -lt $limite) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$puertoApp/api/ehs/salud" -UseBasicParsing -TimeoutSec 3
        $cuerpo = $r.Content | ConvertFrom-Json
        if ($cuerpo.disponible) { $appLista = $true; break }
    } catch {
        Start-Sleep -Seconds 2
    }
}

Write-Host ""
if ($appLista) {
    Write-Host "=== Listo ===" -ForegroundColor Green
    Write-Host "El tablero responde en http://127.0.0.1:$puertoApp"
    Start-Sleep -Seconds 3
} else {
    Write-Host "El motor reinicio pero el tablero todavia no responde." -ForegroundColor Red
    Write-Host "Avisa con este mensaje: el motor esta arriba, la aplicacion no." -ForegroundColor Red
    Read-Host "Presiona Enter para cerrar"
    exit 1
}
