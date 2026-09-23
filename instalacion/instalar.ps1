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
    modos: la unica diferencia es como aparece el motor.

    Se corre en un PowerShell elevado ("Ejecutar como administrador") COMO LA
    CUENTA DE QUIEN VA A USAR EL EQUIPO, no con otra cuenta de administrador: la
    tarea programada, los accesos directos y el permiso para "Reparar" quedan a
    nombre de la cuenta que corre este script.

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
    Incluye la migracion 0008 (datos de ejemplo). NO usar en una instalacion
    real del area: un sitio real no debe arrancar con datos de otro ya cargados.

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
$Usuario = "$env:USERDOMAIN\$env:USERNAME"

Write-Host "=== EHS · instalar ($Motor) ===" -ForegroundColor Cyan
Write-Host "Carpeta de la aplicacion : $RaizApp"
Write-Host "node.exe                : $NodeExe"
Write-Host "Cuenta                  : $Usuario"
Write-Host ""

# ------------------------------------------------------ administrador, lo primero

# En LOS DOS MODOS, no solo en nativo: registrar la tarea programada necesita un
# proceso elevado aunque la tarea misma corra despues sin privilegios — probado en
# vivo, Register-ScheduledTask y schtasks.exe responden "Acceso denegado" con un
# token filtrado por UAC aunque la cuenta sea administradora. Se comprueba antes de
# tocar nada, para no dejar una instalacion a medias.
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $esAdmin) {
    throw ("Este instalador necesita PowerShell como Administrador — una sola vez, solo " +
           "durante la instalacion (ni el motor ni el tablero corren despues con privilegios " +
           "de sistema). Es el UNICO permiso que pide instalacion/requisitos-it.md.")
}

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
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $sddl = ((& sc.exe sdshow $NombreServicio) | Where-Object { $_ -match '^D:' } | Select-Object -First 1)
    if (-not $sddl) { throw "No se pudo leer el descriptor de seguridad de $NombreServicio." }
    $ace = "(A;;RPWPDTLOCRRC;;;$sid)"
    if ($sddl -notlike "*;;;$sid)*") {
        $i = $sddl.IndexOf('S:')
        $nuevo = if ($i -ge 0) { $sddl.Substring(0, $i) + $ace + $sddl.Substring($i) } else { $sddl + $ace }
        & sc.exe sdset $NombreServicio $nuevo | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "sc.exe sdset termino con codigo $LASTEXITCODE." }
    }
}

# ------------------------------------------ credenciales: nuevas o del intento previo

$Previo = Leer-Config $ArchivoConfig
$ClaveMigrador = if ($Previo['SQL_MIGRADOR_CLAVE']) { $Previo['SQL_MIGRADOR_CLAVE'] } else { Nueva-Clave }
$ClaveApp = if ($Previo['SQL_CLAVE']) { $Previo['SQL_CLAVE'] } else { Nueva-Clave }
$ClaveSaPrevia = if ($Previo['EHS_MOTOR'] -eq $Motor) { $Previo['EHS_CLAVE_SA_INSTALACION'] } else { $null }
$script:Sqlcmd = $null
$script:Herramienta = $null

# Un tablero de un intento anterior seguiria ocupando el puerto de la app.
Stop-ScheduledTask -TaskName $NombreTarea -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# ------------------------------------------------------------------- el motor

if ($Motor -eq 'contenedor') {
    $script:Herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $script:Herramienta) {
        throw "Ni docker ni podman estan disponibles. Instala Podman (o Docker con licencia) o usa -Motor nativo."
    }
    & $script:Herramienta info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "$($script:Herramienta) esta instalado pero no responde. Abre Docker Desktop / inicia la maquina de Podman y vuelve a correr este script."
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
        throw ("Hay un motor EHS de un intento anterior, pero no su configuracion (config\ehs.env). " +
               "Sin sus claves no hay forma de entrar. Corre desinstalar.ps1 -BorrarDatoTambien y vuelve a instalar.")
    }
} else {
    $usuarioAdmin = 'sa'; $claveAdmin = $ClaveSa
}
New-Item -ItemType Directory -Force -Path $CarpetaRespaldo | Out-Null
Escribir-Config -ClaveSaTemporal $(if ($usuarioAdmin -eq 'sa') { $claveAdmin } else { $null })

if ($Motor -eq 'contenedor') {
    if (-not $procesoPrevio) {
        Write-Host "Creando el contenedor del motor…"
        & $script:Herramienta run -d --name $NombreContenedor `
            --restart unless-stopped `
            -e "ACCEPT_EULA=Y" `
            -e "MSSQL_SA_PASSWORD=$ClaveSa" `
            -e "MSSQL_PID=Express" `
            -p "127.0.0.1:${PuertoMotor}:1433" `
            -v "ehs-motor-datos:/var/opt/mssql" `
            mcr.microsoft.com/mssql/server:2022-latest | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$($script:Herramienta) run termino con codigo $LASTEXITCODE." }
    } else {
        & $script:Herramienta start $NombreContenedor | Out-Null
    }
} else {
    if (-not $procesoPrevio) {
        if (-not $RutaInstaladorSqlExpress -or -not (Test-Path $RutaInstaladorSqlExpress)) {
            throw "-RutaInstaladorSqlExpress no se dio o no existe. Ver instalacion/guia-instalacion.md."
        }
        $firma = Get-AuthenticodeSignature $RutaInstaladorSqlExpress
        if ($firma.Status -ne 'Valid' -or $firma.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "El instalador $RutaInstaladorSqlExpress no trae una firma valida de Microsoft ($($firma.Status))."
        }
        $setup = Preparar-MedioSqlExpress $RutaInstaladorSqlExpress

        New-Item -ItemType Directory -Force -Path $CarpetaMotorNativo | Out-Null
        $iniTemporal = Join-Path $env:TEMP 'ehs-configuracion-nativo.ini'
        $ini = Get-Content (Join-Path $PSScriptRoot 'configuracion-nativo.ini') -Raw
        $ini = $ini.Replace('__CUENTA_ADMINISTRADORA__', $Usuario).Replace('__CARPETA_DATOS__', $CarpetaMotorNativo)
        Set-Content -Path $iniTemporal -Value $ini -Encoding ASCII

        Write-Host "Instalando SQL Server 2022 Express (instancia EHSLOCAL)… tarda varios minutos."
        $p = Start-Process -FilePath $setup -Wait -PassThru -ArgumentList (
            "/ConfigurationFile=`"$iniTemporal`" /SAPWD=`"$ClaveSa`" /IACCEPTSQLSERVERLICENSETERMS")
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
    Restringir-Loopback
    Permitir-ReiniciarServicio
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

# S4U ("ejecutar tanto si el usuario inicio sesion como si no", sin guardar su
# clave): la tarea corre fuera del escritorio, asi que node no abre ninguna ventana
# de consola. -Hidden solo la oculta en el Programador de tareas; no esconde la
# ventana del programa. Y sin limite de tiempo: el defecto es 72 horas, y el
# Programador de tareas mataria el tablero al tercer dia sin cerrar sesion.
Write-Host "Registrando el arranque automatico…"
$principal = New-ScheduledTaskPrincipal -UserId $Usuario -LogonType S4U -RunLevel Limited
$alIniciar = New-ScheduledTaskTrigger -AtLogOn -User $Usuario
$ajustesTablero = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$accion = New-ScheduledTaskAction -Execute $NodeExe -Argument '"servidor.js"' -WorkingDirectory $RaizApp
Register-ScheduledTask -TaskName $NombreTarea -Action $accion -Trigger $alIniciar -Principal $principal `
    -Settings $ajustesTablero -Force -ErrorAction Stop `
    -Description 'Arranca el tablero EHS al iniciar sesion. Sin privilegios de sistema, sin ventana.' | Out-Null

# SQL Server Express no trae SQL Server Agent (es Standard+): el respaldo diario se
# programa por fuera del motor.
$ajustesRespaldo = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$accionRespaldo = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\respaldar.ps1`""
Register-ScheduledTask -TaskName $NombreTareaRespaldo -Action $accionRespaldo `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '20:00') -Principal $principal `
    -Settings $ajustesRespaldo -Force -ErrorAction Stop `
    -Description 'Respaldo diario de la base EHS a la carpeta local que sincroniza OneDrive.' | Out-Null

Start-ScheduledTask -TaskName $NombreTarea -ErrorAction Stop

# ------------------------------------------------ comprobar que de verdad responde

Write-Host "Comprobando que el tablero responde…"
$limite = (Get-Date).AddSeconds(60)
$salud = $null
while ((Get-Date) -lt $limite) {
    try {
        $salud = Invoke-RestMethod -Uri "http://127.0.0.1:$PuertoApp/api/ehs/salud" -TimeoutSec 5
        if ($salud.disponible) { break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $salud -or -not $salud.disponible) {
    throw ("La tarea '$NombreTarea' arranco pero el tablero no responde en http://127.0.0.1:$PuertoApp " +
           "(o no llega al motor). Revisa en el Programador de tareas el ultimo resultado de esa tarea.")
}
if ($salud.modo -ne 'sql') { throw "El tablero respondio en modo '$($salud.modo)', no 'sql': no esta leyendo config\ehs.env." }
Confirmar-SoloLoopback -Puerto $PuertoApp -Que 'El tablero'

# ------------------------------------------------------------- accesos directos

Write-Host "Creando accesos directos en el escritorio…"
$escritorio = [Environment]::GetFolderPath('Desktop')
# .url y no .lnk: un .lnk apuntando a una URL no es un acceso directo valido de
# Windows; el formato para abrir una direccion en el navegador es el .url.
@(
    '[InternetShortcut]',
    "URL=http://127.0.0.1:$PuertoApp",
    "IconFile=$env:SystemRoot\System32\shell32.dll",
    'IconIndex=13'
) | Set-Content -Path (Join-Path $escritorio 'EHS.url') -Encoding ASCII

$shell = New-Object -ComObject WScript.Shell
$accesoReparar = $shell.CreateShortcut((Join-Path $escritorio 'Reparar EHS.lnk'))
$accesoReparar.TargetPath = 'powershell.exe'
$accesoReparar.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\reparar.ps1`""
$accesoReparar.IconLocation = "$env:SystemRoot\System32\shell32.dll,238"
$accesoReparar.Description = 'Reinicia el motor de EHS y verifica que todo responda'
$accesoReparar.Save()

# ------------------------------------------------------------------------ fin

# La instalacion termino entera: la clave de sa ya no hace falta y no se deja escrita.
Escribir-Config -ClaveSaTemporal $null

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Motor      : $Motor, solo en 127.0.0.1:$PuertoMotor"
Write-Host "Tablero    : http://127.0.0.1:$PuertoApp  (motor $($salud.motor), corte $($salud.corte.mes)/$($salud.corte.anio))"
Write-Host "Escritorio : EHS, Reparar EHS"
if (-not $NoAbrirNavegador) { Start-Process "http://127.0.0.1:$PuertoApp" }
