#Requires -Version 5.1
<#
.SYNOPSIS
    Instala EHS en este equipo: motor de base de datos, esquema, y el tablero
    arrancando solo al iniciar sesion. Un comando, una vez.

.DESCRIPTION
    Dos condiciones gobiernan este script, tal como las fija el encargo de Fase D:

      1. Quien instala necesita exactamente UN permiso a IT (administrador local,
         solo durante esta instalacion) y UN comando.
      2. Quien USA el tablero despues ve un icono, cuatro pantallas y cero
         configuracion — nunca una consola, un puerto, ni el motor.

    Con -Motor nativo instala SQL Server 2022 Express de verdad en el equipo, via
    su instalador oficial. Con -Motor contenedor levanta el MISMO motor
    containerizado (Docker o Podman). Todo lo demas — migraciones, logins,
    configuracion, tarea programada, accesos directos — es IDENTICO entre los dos
    modos: la unica diferencia es como aparece el motor, tal como pide el encargo.

    Nada de lo que este script instala escucha fuera de 127.0.0.1. La tarea
    programada es por usuario, oculta, sin privilegios de sistema.

.PARAMETER Motor
    'nativo' o 'contenedor'.

.PARAMETER RutaInstaladorSqlExpress
    Solo para -Motor nativo: ruta al instalador oficial de SQL Server 2022
    Express (setup.exe o el ejecutable de descarga SQL2022-SSEI-Expr.exe). Este
    paquete no lo descarga — ver instalacion/requisitos-it.md.

.PARAMETER PuertoMotor
    Puerto TCP del motor, solo en 127.0.0.1. Por defecto 14330 (fuera del 1433
    por defecto, para no chocar con otra instancia de SQL Server que ya exista
    en el equipo).

.PARAMETER PuertoApp
    Puerto HTTP del tablero, solo en 127.0.0.1. Por defecto 3210.

.PARAMETER ConDatosSemilla
    Incluye la migracion 0008 (datos de ejemplo). NO usar en una instalacion
    real del area: un sitio real no debe arrancar con datos de otro sitio ya
    cargados. Existe para demostraciones y para esta misma prueba de Fase D.

.EXAMPLE
    .\instalar.ps1 -Motor contenedor

.EXAMPLE
    .\instalar.ps1 -Motor nativo -RutaInstaladorSqlExpress 'D:\SQL2022-SSEI-Expr.exe'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('nativo', 'contenedor')]
    [string]$Motor,

    [string]$RutaInstaladorSqlExpress,

    [int]$PuertoMotor = 14330,

    [int]$PuertoApp = 3210,

    [switch]$ConDatosSemilla
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ------------------------------------------------------------------- rutas base

# instalacion\instalar.ps1 vive DENTRO de app\; la app entera es la unidad que se
# copia al equipo (mismo codigo que despues va a la instancia de empresa, por
# diseno). node\ es hermano de app\ en el paquete distribuible que arma
# empaquetar.ps1 — aqui se usa si existe, y si no, el node del PATH, para poder
# probar este script sin haber corrido el empaquetado primero.
$RaizApp = Split-Path -Parent $PSScriptRoot
$RaizPaquete = Split-Path -Parent $RaizApp
$NodeBundle = Join-Path $RaizPaquete 'node\node.exe'
$NodeExe = if (Test-Path $NodeBundle) { $NodeBundle } else { (Get-Command node -ErrorAction SilentlyContinue).Source }
if (-not $NodeExe) {
    throw "No se encontro node.exe ni empaquetado (node\node.exe junto a app\) ni en el PATH. " +
          "empaquetar.ps1 es quien deberia haberlo dejado empaquetado."
}

$CarpetaConfig = Join-Path $RaizApp 'config'
$ArchivoConfig = Join-Path $CarpetaConfig 'ehs.env'
$CarpetaDatos = Join-Path $RaizPaquete 'datos'
$CarpetaRespaldo = Join-Path $CarpetaDatos 'respaldo'
$CarpetaMotorNativo = Join-Path $CarpetaDatos 'motor'

Write-Host "=== EHS · instalar ($Motor) ===" -ForegroundColor Cyan
Write-Host "Carpeta de la aplicacion : $RaizApp"
Write-Host "node.exe                : $NodeExe"
Write-Host ""

# --------------------------------------------------------- claves de un solo uso

function Nueva-Clave {
    # 24 caracteres de un alfabeto que evita ambiguedades visuales (sin 0/O, 1/l/I)
    # y que sqlcmd/T-SQL puede llevar entre comillas simples sin escapar nada raro.
    $alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#%^*-_='
    -join (1..24 | ForEach-Object { $alfabeto[(Get-Random -Maximum $alfabeto.Length)] })
}

$ClaveSa = Nueva-Clave
$ClaveMigrador = Nueva-Clave
$ClaveApp = Nueva-Clave

# ------------------------------------------------------------- preparar el motor

function Esperar-Motor {
    param([int]$Puerto, [int]$TimeoutSeg = 90)
    Write-Host "Esperando que el motor responda en 127.0.0.1:$Puerto…"
    $limite = (Get-Date).AddSeconds($TimeoutSeg)
    while ((Get-Date) -lt $limite) {
        try {
            $cliente = New-Object System.Net.Sockets.TcpClient
            $cliente.Connect('127.0.0.1', $Puerto)
            $cliente.Close()
            Write-Host "Motor responde." -ForegroundColor Green
            return
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "El motor no respondio en 127.0.0.1:$Puerto tras $TimeoutSeg segundos."
}

# Ejecuta crear-logins.sql. En modo contenedor via 'docker exec' (sqlcmd ya vive
# DENTRO de la imagen, cero dependencia del host); en modo nativo via el sqlcmd
# del host, que el instalador de SQL Server deja instalado.
function Correr-CrearLogins {
    param([string]$ClaveSa)
    Write-Host "Aplicando instalacion/crear-logins.sql…"
    $rutaScript = Join-Path $PSScriptRoot 'crear-logins.sql'

    if ($Motor -eq 'contenedor') {
        docker cp $rutaScript "${script:NombreContenedor}:/tmp/crear-logins.sql" | Out-Null
        docker exec $script:NombreContenedor /opt/mssql-tools18/bin/sqlcmd `
            -C -S localhost -U sa -P $ClaveSa `
            -v ClaveMigrador=$ClaveMigrador ClaveApp=$ClaveApp `
            -i /tmp/crear-logins.sql
    } else {
        & sqlcmd -C -S "127.0.0.1,$PuertoMotor" -U sa -P $ClaveSa `
            -v ClaveMigrador=$ClaveMigrador ClaveApp=$ClaveApp `
            -i $rutaScript
    }
    if ($LASTEXITCODE -ne 0) { throw "crear-logins.sql termino con codigo $LASTEXITCODE." }
}

if ($Motor -eq 'contenedor') {
    $script:NombreContenedor = 'ehs-motor'
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $herramienta) {
        throw "Ni docker ni podman estan disponibles. Instala Docker Desktop o usa -Motor nativo."
    }
    Write-Host "Usando $herramienta."

    New-Item -ItemType Directory -Force -Path $CarpetaDatos | Out-Null
    New-Item -ItemType Directory -Force -Path $CarpetaRespaldo | Out-Null

    $yaExiste = & $herramienta ps -a --format '{{.Names}}' | Where-Object { $_ -eq $script:NombreContenedor }
    if ($yaExiste) {
        Write-Host "El contenedor $($script:NombreContenedor) ya existe: se reutiliza (no se reinstala el motor)." -ForegroundColor Yellow
    } else {
        Write-Host "Creando el contenedor del motor…"
        & $herramienta run -d --name $script:NombreContenedor `
            --restart unless-stopped `
            -e "ACCEPT_EULA=Y" `
            -e "MSSQL_SA_PASSWORD=$ClaveSa" `
            -e "MSSQL_PID=Express" `
            -p "127.0.0.1:${PuertoMotor}:1433" `
            -v "ehs-motor-datos:/var/opt/mssql" `
            -v "${CarpetaRespaldo}:/var/opt/mssql-respaldo" `
            mcr.microsoft.com/mssql/server:2022-latest | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$herramienta run termino con codigo $LASTEXITCODE." }
    }
    Esperar-Motor -Puerto $PuertoMotor
    Correr-CrearLogins -ClaveSa $ClaveSa
} else {
    # ------------------------------------------------------------- modo nativo
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    if (-not $esAdmin) {
        throw "Instalar el motor nativo requiere PowerShell como Administrador. " +
              "Es el UNICO permiso que pide instalacion/requisitos-it.md, y solo durante esta instalacion."
    }
    if (-not $RutaInstaladorSqlExpress -or -not (Test-Path $RutaInstaladorSqlExpress)) {
        throw "-RutaInstaladorSqlExpress no se dio o no existe. Ver instalacion/requisitos-it.md."
    }

    New-Item -ItemType Directory -Force -Path $CarpetaMotorNativo | Out-Null
    New-Item -ItemType Directory -Force -Path $CarpetaRespaldo | Out-Null
    # La cuenta virtual del servicio (NT SERVICE\MSSQL$EHSLOCAL) es quien ejecuta
    # BACKUP DATABASE, asi que es quien necesita poder escribir el .bak aqui — sin
    # este permiso explicito, respaldar.ps1 fallaria con "Access is denied"
    # aunque el login SQL (ehs_migrador) tenga permiso de base de datos de sobra.
    icacls $CarpetaRespaldo /grant 'NT SERVICE\MSSQL$EHSLOCAL:(OI)(CI)M' | Out-Null

    $rutaIni = Join-Path $PSScriptRoot 'configuracion-nativo.ini'
    $iniTemporal = Join-Path $env:TEMP 'ehs-configuracion-nativo.ini'
    $cuentaActual = "$env:USERDOMAIN\$env:USERNAME"
    (Get-Content $rutaIni -Raw) `
        -replace '__CUENTA_ADMINISTRADORA__', $cuentaActual `
        -replace '__CARPETA_DATOS__', $CarpetaMotorNativo |
        Set-Content -Path $iniTemporal -Encoding ASCII

    Write-Host "Instalando SQL Server 2022 Express (instancia EHSLOCAL)… esto tarda varios minutos."
    & $RutaInstaladorSqlExpress /ConfigurationFile=$iniTemporal /SAPWD=$ClaveSa /IACCEPTSQLSERVERLICENSETERMS
    if ($LASTEXITCODE -ne 0) { throw "El instalador de SQL Server termino con codigo $LASTEXITCODE." }
    Remove-Item $iniTemporal -Force -ErrorAction SilentlyContinue

    # TCPENABLED=1 del .ini deja la instancia escuchando en TODAS las interfaces:
    # setup.exe no tiene una opcion para restringirlo. Se corrige aqui, via el
    # proveedor WMI que usa SQL Server Configuration Manager por debajo, fijando
    # el puerto y dejando activa solo la IP de loopback antes de reiniciar el
    # servicio — sin este paso, "nada escucha fuera de 127.0.0.1" seria falso.
    Write-Host "Restringiendo el motor a 127.0.0.1:$PuertoMotor…"
    $smo = [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
    if (-not $smo) {
        Write-Warning ("No se pudo cargar el proveedor WMI de SQL Server. Configura manualmente en " +
                        "SQL Server Configuration Manager: Protocolos > TCP/IP > IPAll = puerto $PuertoMotor, " +
                        "y en cada IP que no sea 127.0.0.1, Habilitado = No. Reinicia el servicio despues.")
    } else {
        $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
        $instancia = $wmi.ServerInstances['EHSLOCAL']
        $tcp = $instancia.ServerProtocols['Tcp']
        foreach ($ip in $tcp.IPAddresses) {
            if ($ip.Name -eq 'IPAll') {
                $ip.IPAddressProperties['TcpPort'].Value = "$PuertoMotor"
                $ip.IPAddressProperties['TcpDynamicPorts'].Value = ''
            } elseif ($ip.IPAddress.ToString() -eq '127.0.0.1') {
                $ip.IPAddressProperties['Enabled'].Value = $true
                $ip.IPAddressProperties['TcpPort'].Value = "$PuertoMotor"
                $ip.IPAddressProperties['TcpDynamicPorts'].Value = ''
            } else {
                $ip.IPAddressProperties['Enabled'].Value = $false
            }
        }
        $tcp.IsEnabled = $true
        $tcp.Alter()
        Restart-Service 'MSSQL$EHSLOCAL' -Force
    }

    Esperar-Motor -Puerto $PuertoMotor
    Correr-CrearLogins -ClaveSa $ClaveSa
}

# ---------------------------------------------------------------- configuracion

Write-Host "Escribiendo config\ehs.env…"
New-Item -ItemType Directory -Force -Path $CarpetaConfig | Out-Null
@"
# Escrito por instalar.ps1 el $(Get-Date -Format 'yyyy-MM-dd HH:mm'). No editar a mano:
# una reinstalacion lo sobrescribe. Ver config\ehs.env.ejemplo para el formato.
SQL_SERVIDOR=127.0.0.1
SQL_PUERTO=$PuertoMotor
SQL_BASE=analitica
SQL_CONFIAR_CERT=1
SQL_CIFRAR=1
SQL_USUARIO=ehs_app
SQL_CLAVE=$ClaveApp
SQL_MIGRADOR_USUARIO=ehs_migrador
SQL_MIGRADOR_CLAVE=$ClaveMigrador
SQL_TIMEOUT_CONEXION_MS=5000
SQL_TIMEOUT_CONSULTA_MS=15000
PUERTO=$PuertoApp
ORIGEN_DATOS=sql
# Leido por reparar.ps1 y respaldar.ps1 para saber como hablarle al motor
# (docker exec vs. Restart-Service / sqlcmd directo). No lo usa la aplicacion.
EHS_MOTOR=$Motor
EHS_CARPETA_RESPALDO=$CarpetaRespaldo
"@ | Set-Content -Path $ArchivoConfig -Encoding UTF8

# ------------------------------------------------------------------ migraciones

Write-Host "Aplicando migraciones…"
Push-Location $RaizApp
try {
    $argsMigrar = @('scripts\migrar.js')
    if ($ConDatosSemilla) { $argsMigrar += '--con-datos-semilla' }
    & $NodeExe @argsMigrar
    if ($LASTEXITCODE -ne 0) { throw "migrar.js termino con codigo $LASTEXITCODE." }
} finally {
    Pop-Location
}

# Segunda pasada: ahora que migrar.js ya creo ehs.sp_capturar_lote y
# ehs.sp_corregir_lectura, esta pasada completa los GRANT EXECUTE que la
# primera (antes de migrar) dejo pendientes — ver el comentario en
# crear-logins.sql sobre por que son dos pasadas.
Correr-CrearLogins -ClaveSa $ClaveSa

# ------------------------------------------------------- arranque automatico

$NombreTarea = 'EHS Tablero'
Write-Host "Registrando el arranque automatico (tarea programada '$NombreTarea')…"
$accion = New-ScheduledTaskAction -Execute $NodeExe -Argument '"servidor.js"' -WorkingDirectory $RaizApp
$disparador = New-ScheduledTaskTrigger -AtLogOn
$config = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $NombreTarea -Action $accion -Trigger $disparador -Settings $config -Force `
    -Description 'Arranca el tablero EHS al iniciar sesion. Sin privilegios de sistema.' | Out-Null

# Respaldo diario, mismo patron: tarea por usuario, oculta. SQL Server Express no
# trae SQL Server Agent (es Standard+), asi que el respaldo no puede programarse
# DENTRO del motor — tiene que ser una tarea de Windows por fuera.
$NombreTareaRespaldo = 'EHS Respaldo diario'
$accionRespaldo = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\respaldar.ps1`""
$disparadorRespaldo = New-ScheduledTaskTrigger -Daily -At '20:00'
Register-ScheduledTask -TaskName $NombreTareaRespaldo -Action $accionRespaldo -Trigger $disparadorRespaldo -Settings $config -Force `
    -Description 'Respaldo diario de la base EHS a la carpeta local que sincroniza OneDrive.' | Out-Null

# Arranca ya, para no obligar a cerrar sesion antes de poder usarlo.
Start-ScheduledTask -TaskName $NombreTarea
Start-Sleep -Seconds 2

# ------------------------------------------------------------- accesos directos

Write-Host "Creando accesos directos en el escritorio…"
$shell = New-Object -ComObject WScript.Shell
$escritorio = [Environment]::GetFolderPath('Desktop')

$accesoApp = $shell.CreateShortcut((Join-Path $escritorio 'EHS.lnk'))
$accesoApp.TargetPath = "http://127.0.0.1:$PuertoApp"
$accesoApp.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
$accesoApp.Description = 'Tablero EHS'
$accesoApp.Save()

$accesoReparar = $shell.CreateShortcut((Join-Path $escritorio 'Reparar EHS.lnk'))
$accesoReparar.TargetPath = 'powershell.exe'
$accesoReparar.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\reparar.ps1`""
$accesoReparar.IconLocation = "$env:SystemRoot\System32\shell32.dll,238"
$accesoReparar.Description = 'Reinicia el motor de EHS y verifica que todo responda'
$accesoReparar.Save()

# ------------------------------------------------------------------------ fin

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Motor      : $Motor, en 127.0.0.1:$PuertoMotor"
Write-Host "Tablero    : http://127.0.0.1:$PuertoApp"
Write-Host "Accesos directos creados en el escritorio: EHS, Reparar EHS."
Start-Process "http://127.0.0.1:$PuertoApp"
