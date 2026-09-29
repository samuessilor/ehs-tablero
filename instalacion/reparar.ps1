#Requires -Version 5.1
<#
.SYNOPSIS
    El atajo "Reparar EHS": levanta el motor y el tablero, y confirma que
    responden. Un doble clic, sin administrador.

.DESCRIPTION
    Es lo unico que la franja de estado le pide a quien usa el tablero cuando el
    punto se pone rojo (ver public/js/franja_estado.js). No reinstala nada, no
    toca el esquema ni el dato: solo levanta lo que ya esta instalado y espera a
    que vuelva a responder.

    Modo contenedor: si Docker Desktop esta cerrado (despues de un reinicio, por
    ejemplo), lo abre y espera a que su motor responda antes de arrancar el
    contenedor. Modo nativo: reinicia el servicio de SQL Server, con el permiso
    que instalar.ps1 le dejo a esta cuenta sobre ESE servicio.
#>
[CmdletBinding()]
param()

# 'Continue': un aviso benigno en stderr de docker no debe abortar la reparacion;
# cada paso comprueba su propio resultado.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
$ArchivoConfig = Join-Path $RaizApp 'config\ehs.env'
. (Join-Path $PSScriptRoot 'tablero.ps1')

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

function Fallar {
    param([string]$Mensaje)
    Write-Host ""
    Write-Host $Mensaje -ForegroundColor Red
    Write-Host "Esto ya no lo resuelve este atajo: hay que avisar con este mensaje tal cual." -ForegroundColor Red
    Read-Host "Presiona Enter para cerrar"
    exit 1
}

$cfg = Leer-Config
$puertoMotor = [int]$cfg['SQL_PUERTO']
$puertoApp = [int]$cfg['PUERTO']
$NodeExe = Buscar-NodeExe -RaizApp $RaizApp

Write-Host "=== EHS · reparar ===" -ForegroundColor Cyan

# --------------------------------------------------------------------- el motor

if ($cfg['EHS_MOTOR'] -eq 'contenedor') {
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $herramienta) { Fallar "Ni docker ni podman estan instalados en este equipo." }

    & $herramienta info *> $null
    if ($LASTEXITCODE -ne 0 -and $herramienta -eq 'docker') {
        # Instalado para todos (Program Files) o solo para este usuario (install --user).
        $escritorio = @((Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
                        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe')) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $escritorio) { Fallar "Docker no responde y no se encontro Docker Desktop (buscado en Program Files y en %LOCALAPPDATA%\Programs\DockerDesktop)." }
        Write-Host "Docker Desktop esta cerrado: abriendolo (puede tardar un minuto)…"
        Start-Process $escritorio
        $limite = (Get-Date).AddSeconds(180)
        do {
            Start-Sleep -Seconds 5
            & $herramienta info *> $null
        } while ($LASTEXITCODE -ne 0 -and (Get-Date) -lt $limite)
        if ($LASTEXITCODE -ne 0) { Fallar "Docker Desktop no quedo listo en 3 minutos." }
    } elseif ($LASTEXITCODE -ne 0) {
        & podman machine start *> $null
    }

    Write-Host "Reiniciando el motor (contenedor ehs-motor)…"
    & $herramienta restart ehs-motor | Out-Null
    if ($LASTEXITCODE -ne 0) { Fallar "No se pudo reiniciar el contenedor ehs-motor (codigo $LASTEXITCODE)." }
} else {
    Write-Host "Reiniciando el motor (servicio MSSQL`$EHSLOCAL)…"
    # instalar.ps1 le dio a esta cuenta permiso de reiniciar SOLO este servicio.
    Restart-Service 'MSSQL$EHSLOCAL' -Force -ErrorAction SilentlyContinue
    if ((Get-Service 'MSSQL$EHSLOCAL' -ErrorAction SilentlyContinue).Status -ne 'Running') {
        Fallar "El servicio de SQL Server (MSSQL`$EHSLOCAL) no quedo corriendo."
    }
}

$limite = (Get-Date).AddSeconds(90)
$listo = $false
while ((Get-Date) -lt $limite) {
    try {
        $cliente = New-Object System.Net.Sockets.TcpClient
        $cliente.Connect('127.0.0.1', $puertoMotor)
        $cliente.Close()
        $listo = $true
        break
    } catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $listo) { Fallar "El motor no volvio a responder en 127.0.0.1:$puertoMotor." }
Write-Host "Motor arriba." -ForegroundColor Green

# ---------------------------------------------------------------------- el tablero

Write-Host "Reiniciando el tablero…"
Detener-Tablero -RaizApp $RaizApp
Iniciar-Tablero -RaizApp $RaizApp -NodeExe $NodeExe
# el motor recien reiniciado tarda unos segundos mas en aceptar logins que en abrir
# el puerto: por eso aqui se espera la salud completa (tablero + motor), no solo HTTP
$salud = Esperar-Tablero -Puerto $puertoApp -TimeoutSeg 90
if (-not $salud) { Fallar "El motor esta arriba pero el tablero no responde en http://127.0.0.1:$puertoApp." }

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "El tablero responde en http://127.0.0.1:$puertoApp"
Start-Sleep -Seconds 3
