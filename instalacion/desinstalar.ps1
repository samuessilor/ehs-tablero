#Requires -Version 5.1
<#
.SYNOPSIS
    Retira EHS de este equipo: tareas programadas, accesos directos, el motor.

.DESCRIPTION
    Por defecto CONSERVA el dato: antes de retirar el motor toma un ultimo
    respaldo (.bak, a la carpeta local y a OneDrive), y no borra nada de
    ehs-datos ni config\ehs.env. Con eso, volver a correr instalar.ps1 — en el
    mismo modo o en el otro — arranca limpio sin perder nada.

    Es tambien el paso para CAMBIAR DE MODO si uno falla: desinstalar.ps1, y
    despues instalar.ps1 -Motor <el otro>.

    Necesita PowerShell como Administrador, igual que instalar.ps1: retirar
    tareas programadas y desinstalar SQL Server lo exigen.

.PARAMETER BorrarDatoTambien
    Ademas borra el volumen/carpeta de datos del motor, los respaldos locales y
    config\ehs.env. Pide escribir BORRAR para confirmar.

.PARAMETER SinConfirmacion
    Omite la confirmacion escrita de -BorrarDatoTambien. Para pruebas
    automatizadas; no usar con dato real.
#>
[CmdletBinding()]
param(
    [switch]$BorrarDatoTambien,
    [switch]$SinConfirmacion
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
$RaizPaquete = Split-Path -Parent $RaizApp
$ArchivoConfig = Join-Path $RaizApp 'config\ehs.env'
$CarpetaDatos = Join-Path $RaizPaquete 'ehs-datos'
$CarpetaMotorNativo = Join-Path $CarpetaDatos 'motor'

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $esAdmin) { throw "desinstalar.ps1 necesita PowerShell como Administrador." }

function Leer-Config {
    $variables = @{}
    if (-not (Test-Path $ArchivoConfig)) { return $variables }
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
$motor = $cfg['EHS_MOTOR']

Write-Host "=== EHS · desinstalar ($motor) ===" -ForegroundColor Cyan

if ($BorrarDatoTambien -and -not $SinConfirmacion) {
    Write-Warning "Vas a borrar TODO el dato de EHS de este equipo (motor, respaldos locales, configuracion)."
    if ((Read-Host 'Escribe BORRAR para confirmar (cualquier otra cosa cancela)') -ne 'BORRAR') {
        Write-Host "Cancelado: no se toco nada."
        exit 0
    }
}

# --------------------------------------------------------- lo que corre solo

foreach ($tarea in @('EHS Tablero', 'EHS Respaldo diario')) {
    if (Get-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $tarea -Confirm:$false -ErrorAction Stop
        Write-Host "Tarea programada '$tarea' retirada."
    }
}

# El escritorio de la sesion abierta en el equipo (la persona del area), no el de la
# cuenta que elevo: instalar.ps1 dejo los accesos directos alli.
$escritorio = [Environment]::GetFolderPath('Desktop')
$consola = (Get-CimInstance Win32_ComputerSystem).UserName
if ($consola) {
    try {
        $sid = ([Security.Principal.NTAccount]$consola).Translate([Security.Principal.SecurityIdentifier]).Value
        $perfil = (Get-CimInstance Win32_UserProfile -Filter "SID='$sid'").LocalPath
        $clave = Get-Item "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue
        $valor = if ($clave) { $clave.GetValue('Desktop', $null, 'DoNotExpandEnvironmentNames') } else { $null }
        if ($valor -and $perfil) { $escritorio = $valor.Replace('%USERPROFILE%', $perfil) }
        elseif ($perfil) { $escritorio = Join-Path $perfil 'Desktop' }
    } catch { }
}
foreach ($acceso in @('EHS.url', 'EHS.lnk', 'Reparar EHS.lnk')) {
    $ruta = Join-Path $escritorio $acceso
    if (Test-Path $ruta) {
        Remove-Item $ruta -Force
        Write-Host "Acceso directo '$acceso' retirado."
    }
}

# ------------------------------------------------ un ultimo respaldo, si se conserva

if (-not $BorrarDatoTambien -and $motor) {
    Write-Host "Tomando un ultimo respaldo antes de retirar el motor…"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'respaldar.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw "El ultimo respaldo fallo; no se retira el motor para no arriesgar el dato. Revisa el error de arriba."
    }
}

# --------------------------------------------------------------------- el motor

if ($motor -eq 'contenedor') {
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($herramienta) {
        & $herramienta rm -f ehs-motor *> $null
        Write-Host "Contenedor del motor retirado."
        if ($BorrarDatoTambien) {
            & $herramienta volume rm ehs-motor-datos *> $null
            Write-Host "Volumen de datos del motor borrado." -ForegroundColor Yellow
        } else {
            Write-Host "El volumen ehs-motor-datos se CONSERVA: instalar.ps1 -Motor contenedor lo vuelve a usar."
        }
    }
} elseif ($motor -eq 'nativo') {
    $setup = Get-ChildItem 'C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\SQL2022\setup.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (Get-Service 'MSSQL$EHSLOCAL' -ErrorAction SilentlyContinue) {
        if (-not $setup) { throw "No se encontro el setup.exe de SQL Server 2022 para desinstalar la instancia EHSLOCAL." }
        Write-Host "Desinstalando la instancia EHSLOCAL de SQL Server… tarda unos minutos."
        $p = Start-Process -FilePath $setup -Wait -PassThru `
            -ArgumentList '/ACTION=Uninstall /FEATURES=SQLENGINE /INSTANCENAME=EHSLOCAL /QUIET'
        if ($p.ExitCode -notin @(0, 3010)) { throw "La desinstalacion de SQL Server termino con codigo $($p.ExitCode)." }
        Write-Host "Instancia EHSLOCAL desinstalada."
    }
    # Los archivos .mdf/.ldf quedan en disco despues de desinstalar. Si se dejaran
    # donde estan, una reinstalacion fallaria al crear 'analitica' encima de un
    # archivo que ya existe; se apartan con fecha en vez de borrarse.
    if ((Test-Path $CarpetaMotorNativo) -and -not $BorrarDatoTambien) {
        $apartado = "$CarpetaMotorNativo-anterior-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item $CarpetaMotorNativo $apartado
        Write-Host "Archivos del motor anterior apartados en $apartado (el dato vive en el ultimo .bak)."
    }
}

# -------------------------------------------------------------- el dato local

if ($BorrarDatoTambien) {
    if (Test-Path $CarpetaDatos) {
        Remove-Item $CarpetaDatos -Recurse -Force
        Write-Host "Carpeta $CarpetaDatos borrada." -ForegroundColor Yellow
    }
    if (Test-Path $ArchivoConfig) {
        Remove-Item $ArchivoConfig -Force
        Write-Host "config\ehs.env borrado." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "La carpeta de la aplicacion ($RaizApp) no se borro."
