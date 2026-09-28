#Requires -Version 5.1
<#
.SYNOPSIS
    Instala EHS en este equipo: motor de base de datos, esquema, y el tablero
    arrancando solo al iniciar sesion. Un comando, una vez.

.DESCRIPTION
    Dos condiciones gobiernan este script, tal como las fija el encargo de Fase D:

      1. Quien instala necesita UN comando (el doble clic en INSTALAR-EHS-NATIVO.cmd).
      2. Quien USA el tablero despues ve un icono, cuatro pantallas y cero
         configuracion — nunca una consola, un puerto, ni el motor.

    Con -Motor nativo (el modo del paquete, decision del 28-sep-2026: ver
    instalacion/requisitos-it.md) instala SQL Server 2022 Express como servicio de
    Windows via su instalador oficial; ese modo SI necesita administrador, una sola
    vez, para instalar. Con -Motor contenedor levanta SQL Server 2022 en Docker
    Desktop o Podman, SIN administrador para instalar — queda documentado como
    alternativa, para si la licencia de Docker Business de la empresa se resuelve mas
    adelante. Todo lo demas — migraciones, logins, configuracion, accesos directos —
    es IDENTICO entre los dos modos: la unica diferencia es como aparece el motor.

    Se corre COMO LA CUENTA DE QUIEN VA A USAR EL EQUIPO. En modo nativo, si el
    aviso de UAC lo eleva otra cuenta (la de IT), el arranque automatico, los
    accesos directos y el permiso para "Reparar" igual quedan a nombre de la
    persona con la sesion abierta en la consola.

    Se puede volver a correr despues de un error, y se puede cambiar de modo si
    uno falla: reutiliza las claves de un intento anterior (config\ehs.env) y el
    motor que ya exista, en vez de generar claves nuevas que ya no coincidirian.

.PARAMETER Motor
    'nativo' o 'contenedor'.

.PARAMETER RutaInstaladorSqlExpress
    Solo para -Motor nativo, y solo si el motor todavia no esta instalado: el
    instalador oficial de SQL Server 2022 Express. Acepta el descargador
    (SQL2022-SSEI-Expr.exe, necesita internet), el paquete ya descargado
    (SQLEXPR_x64_ENU.exe, no necesita internet) o el setup.exe de un medio ya
    extraido.

.PARAMETER PuertoMotor
    Puerto TCP del motor, solo en 127.0.0.1. Por defecto 14330.

.PARAMETER PuertoApp
    Puerto HTTP del tablero, solo en 127.0.0.1. Por defecto 3210.

.PARAMETER ConDatosSemilla
    Incluye la migracion 0008: el historico 2026 del area (enero a julio) tomado del
    libro 'KPI's EHS 2026', la hoja cruda. Es lo que pasa INSTALAR-EHS.cmd: sin ella el
    tablero arrancaria vacio. No viaja en git (son cifras de la empresa); la arma
    analisis\generar_sql_carga.py y la mete empaquetar.ps1.

.EXAMPLE
    .\instalar.ps1 -Motor nativo -RutaInstaladorSqlExpress 'D:\SQLEXPR_x64_ENU.exe'

.EXAMPLE
    .\instalar.ps1 -Motor contenedor
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('nativo', 'contenedor')]
    [string]$Motor,

    [string]$RutaInstaladorSqlExpress,

    [int]$PuertoMotor = 14330,

    [int]$PuertoApp = 3210,

    [switch]$ConDatosSemilla,

    # Solo -Motor contenedor, sin internet: el .tar de 'docker save' de la imagen de
    # SQL Server 2022. Sin esto, 'docker run' intentaria descargarla y fallaria.
    [string]$RutaImagen,

    # Para una instalacion desatendida (o de prueba): no abre el navegador al final.
    [switch]$NoAbrirNavegador
)

# 'Continue', no 'Stop': con 'Stop', PowerShell convierte CUALQUIER linea que un
# ejecutable nativo escriba en stderr (un DeprecationWarning de Node, un aviso de
# sqlcmd) en una excepcion terminante, y el instalador se caia antes de revisar si
# el comando habia fallado de verdad — se vio en vivo. Cada llamada nativa de este
# script comprueba su codigo de salida por su cuenta; los cmdlets criticos llevan
# -ErrorAction Stop explicito.
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

# ------------------------------------------------------------------- rutas base

$RaizApp = Split-Path -Parent $PSScriptRoot
$RaizPaquete = Split-Path -Parent $RaizApp
$NodeBundle = Join-Path $RaizPaquete 'node\node.exe'
$NodeExe = if (Test-Path $NodeBundle) { $NodeBundle } else { (Get-Command node -ErrorAction SilentlyContinue).Source }
if (-not $NodeExe) {
    throw ("No se encontro node.exe ni empaquetado (node\node.exe junto a app\) ni en el PATH. " +
           "empaquetar.ps1 es quien deberia haberlo dejado empaquetado.")
}

$CarpetaConfig = Join-Path $RaizApp 'config'
$ArchivoConfig = Join-Path $CarpetaConfig 'ehs.env'
# 'ehs-datos' y no 'datos': corriendo desde el repositorio de desarrollo, la carpeta
# hermana 'datos' es la de los insumos crudos del area (CSV, JSON del generador), y
# desinstalar.ps1 -BorrarDatoTambien borraria esa carpeta entera. Un nombre propio
# hace imposible confundirlas.
$CarpetaDatos = Join-Path $RaizPaquete 'ehs-datos'
$CarpetaRespaldo = Join-Path $CarpetaDatos 'respaldo'
$CarpetaMotorNativo = Join-Path $CarpetaDatos 'motor'
$NombreContenedor = 'ehs-motor'
$NombreServicio = 'MSSQL$EHSLOCAL'
$NombreTarea = 'EHS Tablero'
$NombreTareaRespaldo = 'EHS Respaldo diario'
$ImagenLocal = 'ehs/mssql-server:2022'

# Para QUIEN se instala. Si la persona del area es usuaria estandar, el aviso de UAC
# le pide a IT sus credenciales y este proceso corre con la cuenta de IT: tomar
# $env:USERNAME dejaria la tarea, los accesos directos y el permiso de "Reparar" a
# nombre de IT. Win32_ComputerSystem.UserName es la sesion abierta en la consola,
# la de la persona sentada frente al equipo, aunque este proceso este elevado con
# otra cuenta.
$UsuarioElevado = "$env:USERDOMAIN\$env:USERNAME"
$UsuarioConsola = (Get-CimInstance Win32_ComputerSystem).UserName
$Usuario = if ($UsuarioConsola) { $UsuarioConsola } else { $UsuarioElevado }
try {
    $SidUsuario = ([Security.Principal.NTAccount]$Usuario).Translate([Security.Principal.SecurityIdentifier]).Value
} catch {
    throw "No se pudo resolver la cuenta '$Usuario' a un SID: $($_.Exception.Message)"
}

Write-Host "=== EHS · instalar ($Motor) ===" -ForegroundColor Cyan
Write-Host "Carpeta de la aplicacion : $RaizApp"
Write-Host "node.exe                : $NodeExe"
Write-Host "Se instala para         : $Usuario"
if ($Usuario -ne $UsuarioElevado) { Write-Host "Elevado con              : $UsuarioElevado" -ForegroundColor Yellow }
Write-Host ""

# ------------------------------------------------------ administrador, lo primero

# Solo el modo NATIVO necesita administrador: instalar SQL Server, restringir su TCP
# en el registro y dar permiso sobre su servicio. El modo contenedor se instala sin
# elevar: el arranque automatico es un acceso directo en la carpeta Inicio de la
# persona (no una tarea programada, que si exige elevar: probado en vivo con
# Register-ScheduledTask y schtasks.exe), y el respaldo diario lo programa la propia
# aplicacion (src/respaldo.js). Se comprueba antes de tocar nada.
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if ($Motor -eq 'nativo' -and -not $esAdmin) {
    throw ("El modo nativo necesita PowerShell como Administrador (instala SQL Server como " +
           "servicio de Windows). El modo contenedor no: .\instalar.ps1 -Motor contenedor")
}
. (Join-Path $PSScriptRoot 'tablero.ps1')

# ------------------------------------------------------------------ utilidades

function Leer-Config {
    param([string]$Ruta)
    $variables = @{}
    if (-not (Test-Path $Ruta)) { return $variables }
    foreach ($linea in Get-Content $Ruta) {
        $t = $linea.Trim().TrimStart([char]0xFEFF)
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 0) { continue }
        $variables[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $variables
}

function Nueva-Clave {
    # 24 caracteres SIN '=': sqlcmd -v Nombre=Valor trunca el valor en el primer '='
    # que aparezca DENTRO del valor. Probado en vivo: una clave con '=' a la mitad
    # llegaba a SQL Server cortada — a veces tan corta que create login la
    # rechazaba, a veces de 8+ caracteres, y entonces el login se creaba con una
    # clave distinta a la de config\ehs.env y fallaba despues, lejos de la causa.
    $alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#%^*-_'
    -join (1..24 | ForEach-Object { $alfabeto[(Get-Random -Maximum $alfabeto.Length)] })
}

function Puerto-Ocupado {
    param([int]$Puerto)
    [bool](Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue)
}

# Una sola forma de hablarle al motor, para los dos modos. -b hace que sqlcmd
# termine con codigo de error ante un error de SQL: sin -b sale con 0 aunque una
# sentencia falle, y asi fue como un 'create login' rechazado paso de largo en una
# de las pruebas en vivo y el problema aparecio dos pasos despues.
function Invocar-Sqlcmd {
    param([string]$UsuarioSql, [string]$ClaveSql, [string]$Consulta, [string]$Archivo,
          [string[]]$Variables = @(), [switch]$Silencioso)
    $argumentos = @('-C', '-b', '-U', $UsuarioSql, '-P', $ClaveSql)
    if ($Variables.Count -gt 0) { $argumentos += '-v'; $argumentos += $Variables }
    if ($Motor -eq 'contenedor') {
        if ($Archivo) {
            & $script:Herramienta cp $Archivo "${NombreContenedor}:/tmp/ehs-script.sql" | Out-Null
            $argumentos += @('-i', '/tmp/ehs-script.sql')
        } else {
            $argumentos += @('-Q', $Consulta)
        }
        $todo = @('exec', $NombreContenedor, '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost') + $argumentos
        if ($Silencioso) { & $script:Herramienta @todo 2>&1 | Out-String } else { & $script:Herramienta @todo }
    } else {
        if ($Archivo) { $argumentos += @('-i', $Archivo) } else { $argumentos += @('-Q', $Consulta) }
        $todo = @('-S', "127.0.0.1,$PuertoMotor") + $argumentos
        if ($Silencioso) { & $script:Sqlcmd @todo 2>&1 | Out-String } else { & $script:Sqlcmd @todo }
    }
}

function Esperar-Motor {
    param([string]$UsuarioSql, [string]$ClaveSql, [switch]$MotorPrevio, [int]$TimeoutSeg = 180)
    # Un TCP connect exitoso NO significa que el motor acepte logins: el puerto
    # queda escuchando antes de terminar de recuperar las bases del sistema (se vio
    # en vivo). Por eso esto intenta un login real.
    Write-Host "Esperando que el motor acepte conexiones en 127.0.0.1:$PuertoMotor…"
    $limite = (Get-Date).AddSeconds($TimeoutSeg)
    while ((Get-Date) -lt $limite) {
        $salida = Invocar-Sqlcmd -UsuarioSql $UsuarioSql -ClaveSql $ClaveSql -Consulta 'select 1' -Silencioso
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Motor listo." -ForegroundColor Green
            return
        }
        # Con un motor de un intento anterior, un "Login failed" que no sea el
        # arranque en modo de actualizacion significa que las claves no coinciden:
        # esperar tres minutos mas no lo va a arreglar.
        if ($MotorPrevio -and $salida -match 'Login failed for user' -and $salida -notmatch 'upgrade mode') {
            throw ("El motor de un intento anterior no acepta las claves guardadas en config\ehs.env. " +
                   "Corre instalacion\desinstalar.ps1 -BorrarDatoTambien (en ese intento todavia no hay " +
                   "dato real) y vuelve a instalar.")
        }
        Start-Sleep -Seconds 3
    }
    throw "El motor no acepto conexiones en 127.0.0.1:$PuertoMotor tras $TimeoutSeg segundos."
}

function Correr-CrearLogins {
    param([string]$UsuarioSql, [string]$ClaveSql)
    Write-Host "Aplicando instalacion/crear-logins.sql (como $UsuarioSql)…"
    Invocar-Sqlcmd -UsuarioSql $UsuarioSql -ClaveSql $ClaveSql `
        -Archivo (Join-Path $PSScriptRoot 'crear-logins.sql') `
        -Variables @("ClaveMigrador=$ClaveMigrador", "ClaveApp=$ClaveApp")
    if ($LASTEXITCODE -ne 0) {
        throw ("crear-logins.sql termino con codigo $LASTEXITCODE (ver el mensaje de SQL Server arriba). " +
               "Si esto viene de un intento anterior a medias, desinstalar.ps1 -BorrarDatoTambien y reinstalar.")
    }
}

function Escribir-Config {
    param([string]$ClaveSaTemporal)
    New-Item -ItemType Directory -Force -Path $CarpetaConfig | Out-Null
    $lineas = @(
        "# Escrito por instalar.ps1 el $(Get-Date -Format 'yyyy-MM-dd HH:mm'). No editar a mano:",
        "# una reinstalacion lo sobrescribe. Ver config\ehs.env.ejemplo para el formato.",
        "SQL_SERVIDOR=127.0.0.1",
        "SQL_PUERTO=$PuertoMotor",
        "SQL_BASE=analitica",
        "SQL_CONFIAR_CERT=1",
        "SQL_CIFRAR=1",
        "SQL_USUARIO=ehs_app",
        "SQL_CLAVE=$ClaveApp",
        "SQL_MIGRADOR_USUARIO=ehs_migrador",
        "SQL_MIGRADOR_CLAVE=$ClaveMigrador",
        "SQL_TIMEOUT_CONEXION_MS=5000",
        "SQL_TIMEOUT_CONSULTA_MS=15000",
        "PUERTO=$PuertoApp",
        "HOST=127.0.0.1",
        "ORIGEN_DATOS=sql",
        "# Lo leen reparar.ps1, respaldar.ps1 y actualizar.ps1. No lo usa la aplicacion.",
        "EHS_MOTOR=$Motor",
        "EHS_CARPETA_RESPALDO=$CarpetaRespaldo"
    )
    if ($script:Sqlcmd) { $lineas += "EHS_SQLCMD=$($script:Sqlcmd)" }
    if ($ClaveSaTemporal) {
        # Solo mientras dura la instalacion, para que un segundo intento tras un
        # error pueda volver a entrar al motor que el primero ya creo. Se borra al
        # final de una instalacion completa: despues nadie necesita sa (ehs_migrador
        # es db_owner y completa cualquier permiso nuevo).
        $lineas += "# TEMPORAL: se borra al terminar la instalacion."
        $lineas += "EHS_CLAVE_SA_INSTALACION=$ClaveSaTemporal"
    }
    [System.IO.File]::WriteAllLines($ArchivoConfig, $lineas, [System.Text.UTF8Encoding]::new($false))
}

# --------------------------------------------------------------- motor nativo

function Preparar-MedioSqlExpress {
    param([string]$Ruta)
    $nombre = Split-Path $Ruta -Leaf
    if ($nombre -ieq 'setup.exe') { return $Ruta }

    $trabajo = Join-Path $env:TEMP 'ehs-sqlexpress'
    New-Item -ItemType Directory -Force -Path $trabajo | Out-Null
    $paquete = $Ruta
    if ($nombre -match 'SSEI') {
        Write-Host "Descargando el medio de SQL Server Express (Core, necesita internet)…"
        $p = Start-Process -FilePath $Ruta -Wait -PassThru `
            -ArgumentList "/ACTION=Download /MEDIAPATH=`"$trabajo`" /MEDIATYPE=Core /QUIET"
        if ($p.ExitCode -ne 0) { throw "El descargador de SQL Server Express termino con codigo $($p.ExitCode)." }
        $paquete = Get-ChildItem $trabajo -Filter 'SQLEXPR*.exe' | Select-Object -First 1 -ExpandProperty FullName
        if (-not $paquete) { throw "El descargador no dejo ningun SQLEXPR*.exe en $trabajo." }
    }

    $extraido = Join-Path $trabajo 'medio'
    $setup = Join-Path $extraido 'setup.exe'
    if (-not (Test-Path $setup)) {
        Write-Host "Extrayendo el medio de instalacion…"
        $p = Start-Process -FilePath $paquete -Wait -PassThru -ArgumentList "/q /x:`"$extraido`""
        if ($p.ExitCode -ne 0) { throw "La extraccion de $paquete termino con codigo $($p.ExitCode)." }
    }
    if (-not (Test-Path $setup)) { throw "No aparecio setup.exe en $extraido." }
    return $setup
}

# SQL Server 2022 deja sqlcmd instalado, pero el PATH de ESTA sesion es el de antes
# de instalar: 'sqlcmd' a secas no se encontraria hasta abrir otra consola. Se busca
# donde lo deja el instalador, y la ruta queda en config (EHS_SQLCMD) para
# respaldar.ps1 y actualizar.ps1.
function Buscar-Sqlcmd {
    $comando = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($comando) { return $comando.Source }
    $candidato = Get-ChildItem 'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\*\Tools\Binn\SQLCMD.EXE' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $candidato) {
        $candidato = Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse -Filter 'SQLCMD.EXE' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    }
    if ($candidato) { return $candidato.FullName }
    throw "SQL Server quedo instalado pero no se encontro sqlcmd.exe. Instala 'Microsoft Command Line Utilities for SQL Server' y vuelve a correr este script."
}

# setup.exe no sabe restringir TCP a una sola IP. Hacen falta DOS cosas, y la
# primera version de este script solo hacia la segunda: apagar "Escuchar en todas"
# (ListenOnAllIPs) y dejar habilitada solo la IP 127.0.0.1. Con ListenOnAllIPs
# encendido, SQL Server IGNORA el "Habilitado" de cada IP y usa IPAll para todas
# las interfaces — el puerto terminaria abierto hacia la red de todas formas.
function Restringir-Loopback {
    $rutaTcp = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.EHSLOCAL\MSSQLServer\SuperSocketNetLib\Tcp'
    if (-not (Test-Path $rutaTcp)) { throw "No existe $rutaTcp — la instancia EHSLOCAL no quedo como se esperaba." }
    Set-ItemProperty $rutaTcp -Name Enabled -Value 1 -ErrorAction Stop
    Set-ItemProperty $rutaTcp -Name ListenOnAllIPs -Value 0 -ErrorAction Stop
    $hayLoopback = $false
    foreach ($sub in Get-ChildItem $rutaTcp | Where-Object { $_.PSChildName -match '^IP\d+$' }) {
        $ruta = $sub.PSPath
        $ip = (Get-ItemProperty $ruta).IpAddress
        if ($ip -eq '127.0.0.1') {
            Set-ItemProperty $ruta -Name Enabled -Value 1 -ErrorAction Stop
            Set-ItemProperty $ruta -Name Active -Value 1 -ErrorAction Stop
            Set-ItemProperty $ruta -Name TcpPort -Value "$PuertoMotor" -ErrorAction Stop
            Set-ItemProperty $ruta -Name TcpDynamicPorts -Value '' -ErrorAction Stop
            $hayLoopback = $true
        } else {
            Set-ItemProperty $ruta -Name Enabled -Value 0 -ErrorAction Stop
        }
    }
    if (-not $hayLoopback) { throw "La instancia no tiene una entrada de IP 127.0.0.1 en su configuracion TCP." }
    Set-ItemProperty "$rutaTcp\IPAll" -Name TcpPort -Value '' -ErrorAction Stop
    Set-ItemProperty "$rutaTcp\IPAll" -Name TcpDynamicPorts -Value '' -ErrorAction Stop
    Restart-Service $NombreServicio -Force -ErrorAction Stop
}

function Confirmar-SoloLoopback {
    param([int]$Puerto, [string]$Que)
    $escuchas = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    $fuera = $escuchas | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') }
    if ($fuera) {
        throw ("$Que escucha en $(($fuera.LocalAddress | Sort-Object -Unique) -join ', '):$Puerto, no solo en 127.0.0.1. " +
               "Eso rompe la condicion de 'nada escucha fuera de 127.0.0.1'.")
    }
    Write-Host "$Que escucha solo en 127.0.0.1:$Puerto." -ForegroundColor Green
}

# "Reparar EHS" corre SIN elevar (quien usa el equipo no es administrador), y
# reiniciar un servicio de Windows necesita permiso explicito. Se le da a esta
# cuenta — y solo sobre este servicio — iniciar, detener y consultar su estado.
function Permitir-ReiniciarServicio {
    $sid = $SidUsuario
    $sddl = ((& sc.exe sdshow $NombreServicio) | Where-Object { $_ -match '^D:' } | Select-Object -First 1)
    if (-not $sddl) { throw "No se pudo leer el descriptor de seguridad de $NombreServicio." }
    # CC/LC/SW (consultar configuracion, estado, dependientes) ademas de iniciar/detener:
    # sin LC, Restart-Service no puede ver cuando el servicio termino de detenerse.
    $ace = "(A;;CCLCSWRPWPDTLOCRRC;;;$sid)"
    if ($sddl -notlike "*;;;$sid)*") {
        $i = $sddl.IndexOf('S:')
        $nuevo = if ($i -ge 0) { $sddl.Substring(0, $i) + $ace + $sddl.Substring($i) } else { $sddl + $ace }
        & sc.exe sdset $NombreServicio $nuevo | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "sc.exe sdset termino con codigo $LASTEXITCODE." }
    }
}

# SQL Server no soporta discos que reporten un sector fisico de mas de 4 KB: en
# Windows 11 algunos NVMe (driver stornvme) reportan 8 o 16 KB, y el setup falla o el
# servicio no arranca (0x851A001A). La solucion oficial de Microsoft es la clave
# ForcedPhysicalSectorSizeInBytes = '* 4095' y reiniciar. Se detecta ANTES de
# instalar: descubrirlo a mitad de setup deja una instalacion rota.
function Revisar-SectorDeDisco {
    $unidad = (Split-Path -Qualifier $CarpetaMotorNativo)
    $info = & fsutil.exe fsinfo sectorinfo $unidad 2>$null
    $fisico = 0
    foreach ($linea in $info) {
        if ($linea -match 'PhysicalBytesPerSectorForAtomicity\s*:\s*(\d+)') { $fisico = [math]::Max($fisico, [int]$Matches[1]) }
        if ($linea -match 'PhysicalBytesPerSectorForPerformance\s*:\s*(\d+)') { $fisico = [math]::Max($fisico, [int]$Matches[1]) }
    }
    Write-Host "Sector fisico de $($unidad): $fisico bytes"
    if ($fisico -le 4096) { return }
    $clave = 'HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device'
    $actual = (Get-ItemProperty $clave -Name ForcedPhysicalSectorSizeInBytes -ErrorAction SilentlyContinue).ForcedPhysicalSectorSizeInBytes
    if ($actual -contains '* 4095') {
        throw ("El disco sigue reportando $fisico bytes aunque la correccion ya esta aplicada: falta reiniciar " +
               "Windows. Reinicia y vuelve a correr este mismo instalador.")
    }
    New-Item -Path $clave -Force | Out-Null
    New-ItemProperty -Path $clave -Name ForcedPhysicalSectorSizeInBytes -PropertyType MultiString -Value @('* 4095') -Force | Out-Null
    throw ("El disco reporta sectores de $fisico bytes, que SQL Server no soporta. Se aplico la correccion " +
           "oficial de Microsoft (ForcedPhysicalSectorSizeInBytes). REINICIA Windows y vuelve a correr este " +
           "mismo instalador: continua desde aqui.")
}

# Con un reinicio pendiente, setup.exe se niega a instalar (regla RebootRequiredCheck)
# con un mensaje que no dice que hacer.
# Hallazgo de la primera corrida real, 28-sep-2026 (equipo de Samuel): esta funcion solo
# miraba dos de las tres senales estandar de reinicio pendiente. La tercera
# (PendingFileRenameOperations — Windows Update, Office Click-to-Run o cualquier
# instalador que reemplaza un archivo en uso la dejan puesta) SI estaba activa ese dia
# (por Office/OneDrive, nada de EHS) y esta funcion no la vio: paso de largo, y
# setup.exe de SQL Server fallo despues con un codigo de salida sin bootstrap log que
# leer (0x84C4000E) — el mismo tipo de fallo silencioso que este chequeo existe para
# evitar, solo que con un mensaje util en vez de un codigo opaco.
function Revisar-ReinicioPendiente {
    $pendiente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                 (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                 [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
    if ($pendiente) {
        throw "Windows tiene un reinicio pendiente (actualizaciones, o un instalador reciente de otro programa). Reinicia y vuelve a correr este instalador."
    }
}

# SQL Server Browser escucha UDP 1434 en TODAS las interfaces. Con puerto fijo no hace
# falta, y el .ini lo deja deshabilitado; esto lo confirma.
function Confirmar-SinBrowser {
    $browser = Get-Service SQLBrowser -ErrorAction SilentlyContinue
    if ($browser -and $browser.Status -eq 'Running') {
        Stop-Service SQLBrowser -Force -ErrorAction SilentlyContinue
        Set-Service SQLBrowser -StartupType Disabled -ErrorAction SilentlyContinue
    }
    if (Get-NetUDPEndpoint -LocalPort 1434 -ErrorAction SilentlyContinue) {
        throw "Algo sigue escuchando en UDP 1434 (SQL Server Browser): rompe 'nada escucha fuera de 127.0.0.1'."
    }
}

# Una carpeta especial de la persona del area (Desktop, Startup), aunque este proceso
# corra con otra cuenta. GetValue sin expandir: expandir %USERPROFILE% o %APPDATA% en
# ESTE proceso daria el perfil de quien eleva, no el de ella. Puede estar redirigida
# a OneDrive.
function Carpeta-DeUsuario {
    param([string]$Nombre, [string]$Defecto)
    $perfil = (Get-CimInstance Win32_UserProfile -Filter "SID='$SidUsuario'" -ErrorAction SilentlyContinue).LocalPath
    $clave = Get-Item "Registry::HKEY_USERS\$SidUsuario\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue
    if ($clave -and $perfil) {
        $valor = $clave.GetValue($Nombre, $null, 'DoNotExpandEnvironmentNames')
        if ($valor) { return $valor.Replace('%USERPROFILE%', $perfil).Replace('%APPDATA%', (Join-Path $perfil 'AppData\Roaming')) }
    }
    if ($perfil) { return Join-Path $perfil $Defecto }
    return $null
}

# ------------------------------------------ credenciales: nuevas o del intento previo

$Previo = Leer-Config $ArchivoConfig
$ClaveMigrador = if ($Previo['SQL_MIGRADOR_CLAVE']) { $Previo['SQL_MIGRADOR_CLAVE'] } else { Nueva-Clave }
$ClaveApp = if ($Previo['SQL_CLAVE']) { $Previo['SQL_CLAVE'] } else { Nueva-Clave }
$ClaveSaPrevia = if ($Previo['EHS_MOTOR'] -eq $Motor) { $Previo['EHS_CLAVE_SA_INSTALACION'] } else { $null }
$script:Sqlcmd = $null
$script:Herramienta = $null

# Un tablero de un intento anterior seguiria ocupando el puerto de la app.
Detener-Tablero -RaizApp $RaizApp
# Versiones anteriores de este instalador arrancaban con tareas programadas.
foreach ($t in $NombreTarea, $NombreTareaRespaldo) {
    if ($esAdmin -and (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue)) {
        Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------- el motor

if ($Motor -eq 'contenedor') {
    $script:Herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $script:Herramienta) {
        throw "Ni docker ni podman estan disponibles. Instala Podman (o Docker con licencia) o usa -Motor nativo."
    }
    $infoMotor = & $script:Herramienta info 2>&1 | Out-String
    # Docker Desktop cerrado: se abre y se espera a su motor, igual que en reparar.ps1,
    # en vez de pedirle a quien instala que lo abra y vuelva a empezar. La primera vez
    # despues de instalar Docker Desktop hay que aceptar sus terminos en su ventana:
    # eso no se puede hacer por la persona, y si no se hace, esto termina en el aviso
    # de siempre al cabo de tres minutos.
    $escritorioDocker = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if ($LASTEXITCODE -ne 0 -and $script:Herramienta -eq 'docker' -and (Test-Path $escritorioDocker) -and
        $infoMotor -notmatch 'Access is denied|acceso denegado|permission denied') {
        Write-Host "Docker Desktop esta cerrado: abriendolo y esperando su motor (hasta 3 minutos)…"
        Start-Process $escritorioDocker
        $limite = (Get-Date).AddSeconds(180)
        do {
            Start-Sleep -Seconds 5
            $infoMotor = & $script:Herramienta info 2>&1 | Out-String
        } while ($LASTEXITCODE -ne 0 -and (Get-Date) -lt $limite)
    }
    if ($LASTEXITCODE -ne 0) {
        # Una cuenta fuera del grupo docker-users no es "Docker cerrado": abrir Docker
        # Desktop y reintentar no lo arregla, y el mensaje generico mandaba justo a eso.
        if ($infoMotor -match 'Access is denied|acceso denegado|permission denied|Acceso denegado') {
            throw ("Docker responde 'acceso denegado': la cuenta $Usuario no esta en el grupo local " +
                   "docker-users. IT la agrega (Administracion de equipos > Usuarios y grupos locales > " +
                   "docker-users), se cierra sesion y se vuelve a correr este instalador.")
        }
        throw ("$($script:Herramienta) esta instalado pero no responde. Abre Docker Desktop (la primera vez hay " +
               "que aceptar sus terminos en su ventana) o inicia la maquina de Podman, espera a que diga " +
               "'Engine running' y vuelve a correr INSTALAR-EHS.cmd.")
    }
    Write-Host "Usando $($script:Herramienta)."
    $procesoPrevio = [bool](& $script:Herramienta ps -a --format '{{.Names}}' | Where-Object { $_ -eq $NombreContenedor })
    # desinstalar.ps1 retira el contenedor pero CONSERVA el volumen, que trae su
    # propia base master con los logins y la clave de sa de la vez anterior: un
    # contenedor nuevo sobre ese volumen es un motor "previo" aunque se acabe de crear.
    $volumenPrevio = [bool](& $script:Herramienta volume ls --format '{{.Name}}' | Where-Object { $_ -eq 'ehs-motor-datos' })
    $motorPrevio = $procesoPrevio -or $volumenPrevio
} else {
    $procesoPrevio = [bool](Get-Service $NombreServicio -ErrorAction SilentlyContinue)
    $motorPrevio = $procesoPrevio
}

$ClaveSa = Nueva-Clave
if (-not $procesoPrevio -and (Puerto-Ocupado $PuertoMotor)) {
    throw ("El puerto $PuertoMotor ya lo usa otro programa. Si es un motor EHS del OTRO modo, corre " +
           "desinstalar.ps1 primero; si no, elige otro con -PuertoMotor.")
}

if ($motorPrevio) {
    Write-Host "Ya hay un motor EHS de un intento anterior: se reutiliza." -ForegroundColor Yellow
    if ($ClaveSaPrevia) {
        $usuarioAdmin = 'sa'; $claveAdmin = $ClaveSaPrevia
    } elseif ($Previo['SQL_MIGRADOR_CLAVE']) {
        $usuarioAdmin = 'ehs_migrador'; $claveAdmin = $ClaveMigrador
    } else {
        # Casi siempre: se instalo antes desde OTRA carpeta (Descargas, el Escritorio). El
        # desinstalar de esta carpeta no sirve: sin su ehs.env no sabe que motor retirar.
        throw ("Hay un motor EHS de un intento anterior, pero no su configuracion (config\ehs.env). " +
               "Sin sus claves no hay forma de entrar. Casi siempre es porque se instalo antes desde " +
               "otra carpeta: corre el desinstalar.ps1 de ESA carpeta (con -BorrarDatoTambien si ahi " +
               "todavia no hay dato real) y vuelve a instalar desde aqui. Ver PASOS-INSTALACION.html, seccion 06.")
    }
} else {
    $usuarioAdmin = 'sa'; $claveAdmin = $ClaveSa
}
New-Item -ItemType Directory -Force -Path $CarpetaRespaldo | Out-Null
Escribir-Config -ClaveSaTemporal $(if ($usuarioAdmin -eq 'sa') { $claveAdmin } else { $null })

if ($Motor -eq 'contenedor') {
    if (-not $procesoPrevio) {
        # Sin internet no hay 'pull': la imagen tiene que venir en el paquete (.tar de
        # docker save) o ya estar cargada. Se retagea a un nombre local propio y se
        # corre con --pull never, para que ni Docker ni Podman intenten salir a la red
        # a buscar una 'latest' que ademas ya no seria la version probada.
        if ($RutaImagen) {
            if (-not (Test-Path $RutaImagen)) { throw "-RutaImagen no existe: $RutaImagen" }
            Write-Host "Cargando la imagen del motor desde $RutaImagen…"
            $cargada = & $script:Herramienta load -i $RutaImagen 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "$($script:Herramienta) load termino con codigo $LASTEXITCODE`n$cargada" }
            $ref = [regex]::Match($cargada, 'Loaded image(?: ID)?:\s*(\S+)').Groups[1].Value
            if (-not $ref) { throw "No se pudo leer que imagen cargo '$($script:Herramienta) load':`n$cargada" }
            & $script:Herramienta tag $ref $ImagenLocal | Out-Null
        }
        & $script:Herramienta image inspect $ImagenLocal *> $null
        if ($LASTEXITCODE -ne 0) {
            # Sin .tar: la imagen oficial si ya esta en el equipo, y si no, descargarla —
            # esto ultimo solo funciona con internet, y se dice asi si falla.
            $oficial = 'mcr.microsoft.com/mssql/server:2022-latest'
            & $script:Herramienta image inspect $oficial *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Descargando la imagen $oficial (necesita internet, ~600 MB)…"
                & $script:Herramienta pull $oficial
                if ($LASTEXITCODE -ne 0) {
                    throw ("No se pudo descargar $oficial. Sin internet, pasa -RutaImagen con el .tar que arma " +
                           "empaquetar.ps1 -ConImagenContenedor.")
                }
            }
            & $script:Herramienta tag $oficial $ImagenLocal | Out-Null
        }
        Write-Host "Creando el contenedor del motor…"
        # TZ: sin ella el contenedor corre en UTC, y sysdatetime() — la hora de cada
        # captura, correccion y rechazo en la bitacora — quedaria 5 horas adelantada.
        & $script:Herramienta run -d --name $NombreContenedor `
            --restart unless-stopped --pull never `
            -e "ACCEPT_EULA=Y" `
            -e "MSSQL_SA_PASSWORD=$ClaveSa" `
            -e "MSSQL_PID=Express" `
            -e "TZ=America/Bogota" `
            -p "127.0.0.1:${PuertoMotor}:1433" `
            -v "ehs-motor-datos:/var/opt/mssql" `
            $ImagenLocal | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$($script:Herramienta) run termino con codigo $LASTEXITCODE." }
    } else {
        & $script:Herramienta start $NombreContenedor | Out-Null
    }
} else {
    if (-not $procesoPrevio) {
        if (-not $RutaInstaladorSqlExpress -or -not (Test-Path $RutaInstaladorSqlExpress)) {
            throw "-RutaInstaladorSqlExpress no se dio o no existe. Ver instalacion/guia-instalacion.md."
        }
        # Sin internet no se puede consultar la revocacion del certificado: se exige
        # que la firma no este alterada y que sea de Microsoft, y cualquier otro estado
        # queda solo como aviso.
        $firma = Get-AuthenticodeSignature $RutaInstaladorSqlExpress
        if ($firma.Status -in @('HashMismatch', 'NotSigned') -or
            -not $firma.SignerCertificate -or $firma.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "El instalador $RutaInstaladorSqlExpress no trae una firma intacta de Microsoft ($($firma.Status))."
        }
        if ($firma.Status -ne 'Valid') { Write-Warning "Firma de Microsoft sin poder validarla en linea ($($firma.Status)); se continua." }
        Revisar-ReinicioPendiente
        Revisar-SectorDeDisco
        $setup = Preparar-MedioSqlExpress $RutaInstaladorSqlExpress

        New-Item -ItemType Directory -Force -Path $CarpetaMotorNativo | Out-Null
        $iniTemporal = Join-Path $env:TEMP 'ehs-configuracion-nativo.ini'
        # El .ini solo lleva constantes ASCII. Lo que depende del equipo (la carpeta de
        # datos, el grupo de administradores) va por linea de comandos, que es Unicode:
        # un .ini en ASCII convertia en '?' una ñ o una tilde en la ruta o en el nombre.
        Copy-Item (Join-Path $PSScriptRoot 'configuracion-nativo.ini') $iniTemporal -Force
        # El grupo local de Administradores por su SID: el nombre esta traducido
        # ('Administradores' en Windows en espanol) y una cuenta de Entra ID puede no
        # resolverse desde setup.exe. Quien pueda elevar en el equipo administra la
        # instancia; ni la app ni quien usa el equipo la necesitan.
        $admins = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value

        Write-Host "Instalando SQL Server 2022 Express (instancia EHSLOCAL)… tarda varios minutos."
        $p = Start-Process -FilePath $setup -Wait -PassThru -ArgumentList (
            "/ConfigurationFile=`"$iniTemporal`" /SAPWD=`"$ClaveSa`" /SQLSYSADMINACCOUNTS=`"$admins`" " +
            "/INSTALLSQLDATADIR=`"$CarpetaMotorNativo`" /IACCEPTSQLSERVERLICENSETERMS /SUPPRESSPRIVACYSTATEMENTNOTICE")
        Remove-Item $iniTemporal -Force -ErrorAction SilentlyContinue
        # 3010 = instalado, pide reiniciar Windows en algun momento (no ahora).
        if ($p.ExitCode -notin @(0, 3010)) {
            throw ("El instalador de SQL Server termino con codigo $($p.ExitCode). El detalle esta en " +
                   "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log\Summary.txt")
        }
    } elseif ((Get-Service $NombreServicio).Status -ne 'Running') {
        Start-Service $NombreServicio -ErrorAction Stop
    }

    # La cuenta virtual del servicio es quien escribe el .bak de respaldar.ps1.
    icacls $CarpetaRespaldo /grant 'NT SERVICE\MSSQL$EHSLOCAL:(OI)(CI)M' | Out-Null
    $script:Sqlcmd = Buscar-Sqlcmd
    # setup deja el servicio en 'Automatico (inicio retrasado)': unos dos minutos
    # despues de encender, el tablero se abriria con la franja en rojo.
    & sc.exe config $NombreServicio start= auto | Out-Null
    Restringir-Loopback
    Permitir-ReiniciarServicio
    Confirmar-SinBrowser
    Escribir-Config -ClaveSaTemporal $(if ($usuarioAdmin -eq 'sa') { $claveAdmin } else { $null })
}

Esperar-Motor -UsuarioSql $usuarioAdmin -ClaveSql $claveAdmin -MotorPrevio:$motorPrevio
Confirmar-SoloLoopback -Puerto $PuertoMotor -Que 'El motor'

# Primera pasada: base, logins, roles. Los GRANT de los procedimientos quedan
# pendientes porque todavia no existen (crear-logins.sql lo avisa, no falla).
Correr-CrearLogins -UsuarioSql $usuarioAdmin -ClaveSql $claveAdmin

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

# Segunda pasada, ya con los procedimientos creados: completa los GRANT EXECUTE.
# Con ehs_migrador (db_owner), no con sa: es la misma identidad que despues usa
# actualizar.ps1, asi que esto prueba tambien que actualizar va a poder hacerlo.
Correr-CrearLogins -UsuarioSql 'ehs_migrador' -ClaveSql $ClaveMigrador

# ------------------------------------------------------- arranque automatico

# Un acceso directo en la carpeta Inicio de la persona del area: Windows lo abre al
# iniciar sesion, sin administrador y sin tarea programada. Apunta a conhost
# --headless para que node corra SIN ventana de consola.
$carpetaInicio = Carpeta-DeUsuario -Nombre 'Startup' -Defecto 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
if (-not $carpetaInicio) { throw "No se pudo ubicar la carpeta Inicio de $Usuario." }
New-Item -ItemType Directory -Force -Path $carpetaInicio | Out-Null
$shell = New-Object -ComObject WScript.Shell
$accesoInicio = $shell.CreateShortcut((Ruta-AccesoInicio -CarpetaInicio $carpetaInicio))
$accesoInicio.TargetPath = "$env:SystemRoot\System32\conhost.exe"
$accesoInicio.Arguments = "--headless `"$NodeExe`" `"$(Join-Path $RaizApp 'servidor.js')`""
$accesoInicio.WorkingDirectory = $RaizApp
$accesoInicio.WindowStyle = 7
$accesoInicio.Description = 'Arranca el tablero EHS al iniciar sesion, sin ventana.'
$accesoInicio.Save()
Write-Host "Arranque automatico: $(Ruta-AccesoInicio -CarpetaInicio $carpetaInicio)"

# Docker Desktop al iniciar sesion: lo abre el propio tablero (src/arranque_motor.js)
# si nadie lo abrio. Editar su settings-store.json no se sostiene: Docker lo reescribe.

# ------------------------------------------------ arrancarlo ya, y comprobarlo

# Si este proceso corre con la cuenta de IT (UAC con otras credenciales), arrancar
# node aqui lo dejaria corriendo como IT: no se arranca, y lo levanta el acceso
# directo de Inicio en el proximo inicio de sesion de la persona.
$salud = $null
if ($Usuario -eq $UsuarioElevado) {
    Iniciar-Tablero -RaizApp $RaizApp -NodeExe $NodeExe
    Write-Host "Comprobando que el tablero responde…"
    $salud = Esperar-Tablero -Puerto $PuertoApp -TimeoutSeg 60
    if (-not $salud) {
        throw ("El tablero no responde en http://127.0.0.1:$PuertoApp (o no llega al motor). " +
               "Prueba a mano: `"$NodeExe`" `"$(Join-Path $RaizApp 'servidor.js')`" y lee el error.")
    }
    if ($salud.modo -ne 'sql') { throw "El tablero respondio en modo '$($salud.modo)', no 'sql': no esta leyendo config\ehs.env." }
    Confirmar-SoloLoopback -Puerto $PuertoApp -Que 'El tablero'
} else {
    Write-Host "Instalado para ${Usuario}: el tablero arranca en su proximo inicio de sesion." -ForegroundColor Yellow
}

# ------------------------------------------------------------- accesos directos

Write-Host "Creando accesos directos en el escritorio…"
$escritorio = Carpeta-DeUsuario -Nombre 'Desktop' -Defecto 'Desktop'
if (-not $escritorio) { $escritorio = [Environment]::GetFolderPath('Desktop') }
# .url y no .lnk: un .lnk apuntando a una URL no es un acceso directo valido de
# Windows; el formato para abrir una direccion en el navegador es el .url.
@(
    '[InternetShortcut]',
    "URL=http://127.0.0.1:$PuertoApp",
    "IconFile=$env:SystemRoot\System32\shell32.dll",
    'IconIndex=13'
) | Set-Content -Path (Join-Path $escritorio 'EHS.url') -Encoding ASCII

$accesoReparar = $shell.CreateShortcut((Join-Path $escritorio 'Reparar EHS.lnk'))
$accesoReparar.TargetPath = 'powershell.exe'
$accesoReparar.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\reparar.ps1`""
$accesoReparar.IconLocation = "$env:SystemRoot\System32\shell32.dll,238"
$accesoReparar.Description = 'Reinicia el motor de EHS y verifica que todo responda'
$accesoReparar.Save()

# ------------------------------------------------------------------------ fin

# La instalacion termino entera: la clave de sa ya no hace falta y no se deja escrita.
# Borrarla de config\ehs.env no alcanza: en modo contenedor tambien queda en la
# variable MSSQL_SA_PASSWORD del contenedor, que 'docker inspect' le muestra a
# cualquiera con acceso a Docker en el equipo. Por eso sa pasa a una clave nueva que
# no se guarda en ningun lado: despues de instalar nadie la necesita (ehs_migrador es
# db_owner y actualizar.ps1 trabaja con el). Si algun dia hiciera falta, en modo
# contenedor se restablece con '/opt/mssql/bin/mssql-conf set-sa-password'.
# Es lo ultimo antes de reescribir la configuracion: si fallara algo antes, un segundo
# intento todavia entra con la clave temporal.
if ($usuarioAdmin -eq 'sa') {
    Invocar-Sqlcmd -UsuarioSql 'sa' -ClaveSql $claveAdmin -Silencioso `
        -Consulta "alter login sa with password = N'$(Nueva-Clave)';" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "La clave de sa quedo cambiada por una que no se guarda en ningun lado." -ForegroundColor Green
    } else {
        Write-Warning ("No se pudo cambiar la clave de sa (codigo $LASTEXITCODE). EHS funciona igual, pero la " +
                       "clave usada al instalar sigue siendo valida.")
    }
}
Escribir-Config -ClaveSaTemporal $null

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Motor      : $Motor, solo en 127.0.0.1:$PuertoMotor"
if ($salud) {
    Write-Host "Tablero    : http://127.0.0.1:$PuertoApp  (motor $($salud.motor), corte $($salud.corte.mes)/$($salud.corte.anio))"
} else {
    Write-Host "Tablero    : http://127.0.0.1:$PuertoApp  (arranca al iniciar sesion $Usuario)"
}
Write-Host "Escritorio : EHS, Reparar EHS"
if ($salud -and -not $NoAbrirNavegador) { Start-Process "http://127.0.0.1:$PuertoApp" }
