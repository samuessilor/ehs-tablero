#Requires -Version 5.1
<#
.SYNOPSIS
    Revisa este equipo y dice si puede recibir EHS por el camino A (Docker Desktop) o
    por el C (SQL Server nativo). Solo LEE: no instala, no cambia nada y no pide
    administrador. Se puede correr antes de llevar el paquete.

.DESCRIPTION
    Para cada camino imprime lo que falta (FALTA), lo que conviene mirar (REVISAR) y lo
    que esta bien (OK). Los minimos salen de la documentacion de Docker y de Microsoft
    (ver requisitos-it.md); los marcados "recomendado" son estimaciones del proyecto.

    Uso: doble clic en VERIFICAR-EQUIPO.cmd, o
         powershell -ExecutionPolicy Bypass -File verificar-equipo.ps1
#>
$ErrorActionPreference = 'Continue'
$faltaA = New-Object System.Collections.Generic.List[string]
$faltaC = New-Object System.Collections.Generic.List[string]
$mirarA = New-Object System.Collections.Generic.List[string]
$mirarC = New-Object System.Collections.Generic.List[string]

function Reportar {
    param([string]$Estado, [string]$Que, [string]$Detalle, [string]$Para = '')
    $color = switch ($Estado) { 'OK' { 'Green' } 'FALTA' { 'Red' } 'REVISAR' { 'Yellow' } default { 'Gray' } }
    Write-Host ('[{0,-7}] {1}: {2}' -f $Estado, $Que, $Detalle) -ForegroundColor $color
    if ($Estado -eq 'FALTA') {
        if ($Para -match 'A') { $faltaA.Add("$Que ($Detalle)") }
        if ($Para -match 'C') { $faltaC.Add("$Que ($Detalle)") }
    } elseif ($Estado -eq 'REVISAR') {
        if ($Para -match 'A') { $mirarA.Add("$Que ($Detalle)") }
        if ($Para -match 'C') { $mirarC.Add("$Que ($Detalle)") }
    }
}

Write-Host ''
Write-Host 'EHS: revision de este equipo (solo lectura, no cambia nada)' -ForegroundColor Cyan
Write-Host ('Equipo {0}, cuenta {1}\{2}' -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME)
Write-Host ''

# ------------------------------------------------------------------- Windows y hardware
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$build = [int]$os.BuildNumber
$esW11 = $build -ge 22000

$minA = if ($esW11) { 22631 } else { 19045 }
if ($build -ge $minA) {
    Reportar 'OK' 'Windows (A)' "$($os.Caption), compilacion $build (Docker pide 22H2 en W10 o 23H2 en W11)"
} else {
    Reportar 'FALTA' 'Windows (A)' "$($os.Caption), compilacion ${build}: Docker Desktop pide $minA o posterior" 'A'
}
if ($os.Caption -match 'Home') {
    Reportar 'REVISAR' 'Edicion de Windows (A)' 'Home: la pagina de Docker lista Pro, Enterprise y Education; en el equipo de prueba (Windows 11 Home) funciona con WSL 2' 'A'
}
if ($build -ge 14393) {
    Reportar 'OK' 'Windows (C)' 'SQL Server 2022 Express pide Windows 10 1607 o posterior'
} else {
    Reportar 'FALTA' 'Windows (C)' "compilacion ${build}: SQL Server 2022 pide Windows 10 1607 (14393) o posterior" 'C'
}

$ram = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
if ($ram -ge 8) { Reportar 'OK' 'Memoria (A)' "$ram GB (Docker Desktop pide 8 GB)" }
else { Reportar 'REVISAR' 'Memoria (A)' "$ram GB: Docker Desktop pide 8 GB" 'A' }
if ($ram -ge 2) { Reportar 'OK' 'Memoria (C)' "$ram GB (SQL Server Express recomienda 1 GB)" }
else { Reportar 'REVISAR' 'Memoria (C)' "$ram GB: SQL Server Express recomienda 1 GB" 'C' }

$unidad = $env:SystemDrive.TrimEnd(':')
$libre = [math]::Round((Get-PSDrive -Name $unidad).Free / 1GB, 1)
if ($libre -ge 10) { Reportar 'OK' 'Disco libre (A)' "$libre GB en $($env:SystemDrive) (recomendado 10: Docker, su maquina WSL y la imagen)" }
else { Reportar 'REVISAR' 'Disco libre (A)' "$libre GB en $($env:SystemDrive): recomendado 10" 'A' }
if ($libre -ge 6) { Reportar 'OK' 'Disco libre (C)' "$libre GB (Microsoft pide 6 GB libres en la unidad del sistema al instalar)" }
else { Reportar 'FALTA' 'Disco libre (C)' "$libre GB: Microsoft pide 6 GB libres en la unidad del sistema al instalar" 'C' }

# ------------------------------------------------------------------- camino A: WSL 2 y Docker
$virt = ($cs.HypervisorPresent -eq $true) -or ($cpu.VirtualizationFirmwareEnabled -eq $true)
if ($virt) { Reportar 'OK' 'Virtualizacion (A)' 'activa (el equipo ya corre con hipervisor o la BIOS la tiene encendida)' }
else { Reportar 'FALTA' 'Virtualizacion (A)' 'apagada: hay que activarla en la BIOS/UEFI (o la politica de IT la bloquea)' 'A' }
if ($cs.Model -match 'Virtual|VMware|KVM|HVM') {
    Reportar 'REVISAR' 'Equipo virtual (A)' "el equipo es una maquina virtual ($($cs.Model)): necesita virtualizacion anidada" 'A'
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Reportar 'FALTA' 'WSL 2 (A)' 'no esta instalado: Docker Desktop lo activa solo, pero eso pide administrador una vez y a veces reiniciar' 'A'
} else {
    $previo = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $salidaWsl = (& wsl.exe --version 2>&1 | Out-String)
    } catch { $salidaWsl = '' } finally { [Console]::OutputEncoding = $previo }
    if ($salidaWsl -match '(\d+\.\d+\.\d+)') {
        $vWsl = [version]$Matches[1]
        if ($vWsl -ge [version]'2.1.5') { Reportar 'OK' 'WSL 2 (A)' "version $vWsl (Docker pide 2.1.5 o posterior)" }
        else { Reportar 'REVISAR' 'WSL 2 (A)' "version ${vWsl}: Docker pide 2.1.5 o posterior (wsl --update)" 'A' }
    } else {
        Reportar 'REVISAR' 'WSL 2 (A)' 'esta la orden wsl pero no informa version: es una version antigua (wsl --update)' 'A'
    }
}

$lan = Get-Service LanmanServer -ErrorAction SilentlyContinue
if ($lan -and $lan.StartType -eq 'Automatic') { Reportar 'OK' 'Servicio Servidor (A)' 'LanmanServer en Automatico (lo pide Docker Desktop)' }
else { Reportar 'REVISAR' 'Servicio Servidor (A)' 'LanmanServer no esta en Automatico: Docker Desktop lo pide asi' 'A' }

$rutasDocker = @((Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
                 (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe')) | Where-Object { Test-Path $_ }
$docker = Get-Command docker.exe -ErrorAction SilentlyContinue
if (-not $rutasDocker -and -not $docker) {
    Reportar 'FALTA' 'Docker Desktop (A)' 'no esta instalado (IT lo instala una vez; ver requisitos-it.md)' 'A'
} else {
    Reportar 'OK' 'Docker Desktop (A)' ("instalado en " + (($rutasDocker | ForEach-Object { Split-Path $_ -Parent }) -join ' y '))
    if ($docker) {
        $trabajo = Start-Job { & docker.exe version --format '{{.Server.Version}}' 2>&1 | Out-String }
        if (Wait-Job $trabajo -Timeout 20) {
            $v = (Receive-Job $trabajo).Trim()
            if ($v -match '^\d+\.\d+') { Reportar 'OK' 'Motor de Docker (A)' "responde, version $v" }
            elseif ($v -match 'denied|denegado') { Reportar 'FALTA' 'Motor de Docker (A)' 'acceso denegado: la cuenta no esta en el grupo docker-users' 'A' }
            else { Reportar 'REVISAR' 'Motor de Docker (A)' 'instalado pero no responde: abrir Docker Desktop (la primera vez, aceptar sus terminos) y esperar Engine running' 'A' }
        } else {
            Reportar 'REVISAR' 'Motor de Docker (A)' 'no respondio en 20 segundos: abrir Docker Desktop y esperar Engine running' 'A'
        }
        Remove-Job $trabajo -Force -ErrorAction SilentlyContinue
    }
}
try {
    $du = @(Get-LocalGroupMember -Group 'docker-users' -ErrorAction Stop | ForEach-Object { $_.Name })
    if ($du -contains "$env:USERDOMAIN\$env:USERNAME") { Reportar 'OK' 'Grupo docker-users (A)' 'la cuenta esta en el grupo (recuerda: Docker lo equipara a administrador del equipo)' }
    else { Reportar 'REVISAR' 'Grupo docker-users (A)' 'la cuenta NO esta en el grupo: solo hace falta si Docker se instala para todos los usuarios' 'A' }
} catch {
    Reportar 'INFO' 'Grupo docker-users (A)' 'no existe: Docker Desktop no esta instalado para todos los usuarios'
}
if (Get-Command podman.exe -ErrorAction SilentlyContinue) { Reportar 'INFO' 'Podman' 'esta instalado: EHS tambien lo detecta (sin probar)' }

# ------------------------------------------------------------------- camino C: SQL nativo
$rel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
if ($rel -ge 461808) { Reportar 'OK' '.NET Framework (C)' "4.7.2 o posterior (Release $rel)" }
else { Reportar 'FALTA' '.NET Framework (C)' 'SQL Server 2022 pide .NET Framework 4.7.2 o posterior' 'C' }

if ($cs.DomainRole -ge 4) { Reportar 'FALTA' 'Controlador de dominio (C)' 'Microsoft no recomienda SQL Server en un controlador de dominio' 'C' }
else { Reportar 'OK' 'Controlador de dominio (C)' 'no lo es' }

$esAdminSesion = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$esAdminLocal = $false
try {
    $esAdminLocal = [bool](@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Where-Object { $_.Name -eq "$env:USERDOMAIN\$env:USERNAME" }).Count)
} catch { }
if ($esAdminSesion -or $esAdminLocal) {
    Reportar 'INFO' 'Administrador (C)' 'la cuenta es administradora local: el aviso UAC solo pide confirmar'
} else {
    Reportar 'REVISAR' 'Administrador (C)' 'la cuenta es estandar: el aviso UAC pedira usuario y clave de un administrador (IT)' 'C'
}

try {
    $r = Invoke-WebRequest -Uri 'https://www.microsoft.com' -Method Head -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    Reportar 'OK' 'Internet (C)' 'llega a microsoft.com (el camino C baja 714 MB de ahi al instalar)'
} catch {
    if ($_.Exception.Response) { Reportar 'OK' 'Internet (C)' 'llega a microsoft.com (el camino C baja 714 MB de ahi al instalar)' }
    else { Reportar 'REVISAR' 'Internet (C)' 'no llega a microsoft.com (proxy o sin red): el camino C necesita bajar 714 MB o llevar SQLEXPR_x64_ENU.exe' 'C' }
}

# ------------------------------------------------------------------- comun
$pMachine = Get-ExecutionPolicy -Scope MachinePolicy
$pUser = Get-ExecutionPolicy -Scope UserPolicy
if (@($pMachine, $pUser) | Where-Object { $_ -in 'AllSigned', 'Restricted' }) {
    Reportar 'FALTA' 'Politica de scripts' "una directiva de IT ($pMachine / $pUser) impide correr los scripts de EHS" 'AC'
} else {
    Reportar 'OK' 'Politica de scripts' 'ninguna directiva de IT bloquea los scripts de EHS'
}
foreach ($puerto in 3210, 14330) {
    $uso = Get-NetTCPConnection -State Listen -LocalPort $puerto -ErrorAction SilentlyContinue
    if ($uso) { Reportar 'REVISAR' "Puerto $puerto" 'ya lo usa otro programa (puede ser un EHS anterior)' 'AC' }
    else { Reportar 'OK' "Puerto $puerto" 'libre' }
}
if ((Test-Path 'C:\EHS\app\config\ehs.env') -or (Get-Service 'MSSQL$EHSLOCAL' -ErrorAction SilentlyContinue)) {
    Reportar 'INFO' 'EHS ya instalado' 'hay rastros de una instalacion anterior en este equipo (C:\EHS o el servicio MSSQL$EHSLOCAL)'
}

# ------------------------------------------------------------------- resumen
Write-Host ''
Write-Host '============================== RESUMEN ==============================' -ForegroundColor Cyan
function Resumen {
    param([string]$Titulo, $Falta, $Mirar)
    if ($Falta.Count -eq 0) { Write-Host ("$Titulo : LISTO para instalar" + $(if ($Mirar.Count) { " (con $($Mirar.Count) cosa(s) por mirar)" } else { '' })) -ForegroundColor Green }
    else { Write-Host ("$Titulo : FALTAN $($Falta.Count) cosa(s)") -ForegroundColor Red }
    foreach ($f in $Falta) { Write-Host "    FALTA   $f" -ForegroundColor Red }
    foreach ($m in $Mirar) { Write-Host "    REVISAR $m" -ForegroundColor Yellow }
}
Resumen 'Camino A (Docker Desktop)' $faltaA $mirarA
Resumen 'Camino C (SQL Server nativo)' $faltaC $mirarC
Write-Host ''
Write-Host 'No se cambio nada en este equipo. Licencia de Docker (Business) y politica de IT: eso no se puede medir aqui.'
Write-Host ''
