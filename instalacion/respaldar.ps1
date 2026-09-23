#Requires -Version 5.1
<#
.SYNOPSIS
    Respalda la base analitica y copia el archivo a OneDrive corporativo.

.DESCRIPTION
    Dos pasos separados a proposito, tal como los describe el encargo: el motor
    escribe el respaldo en su propio disco, y este script lo copia a OneDrive.
    El motor nunca habla con OneDrive directamente.

    Lo dispara la aplicacion (src/respaldo.js): despues de cada captura o
    correccion, y una vez al dia si el ultimo respaldo tiene mas de 20 horas. Se
    puede correr a mano.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

function Leer-Config {
    $ruta = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\ehs.env'
    if (-not (Test-Path $ruta)) { throw "No existe $ruta. ¿Se corrio instalar.ps1?" }
    $variables = @{}
    foreach ($linea in Get-Content $ruta) {
        $t = $linea.Trim().TrimStart([char]0xFEFF)
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 0) { continue }
        $variables[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $variables
}

$cfg = Leer-Config
$carpetaLocal = $cfg['EHS_CARPETA_RESPALDO']
New-Item -ItemType Directory -Force -Path $carpetaLocal | Out-Null
$sello = Get-Date -Format 'yyyyMMdd-HHmmss'
$nombreArchivo = "ehs-analitica-$sello.bak"
$rutaLocal = Join-Path $carpetaLocal $nombreArchivo

# Cada corrida deja su propio registro junto a los respaldos: esto lo dispara la
# aplicacion en segundo plano, sin consola que mirar, asi que
# sin este archivo un fallo seria invisible. /api/ehs/salud lee la fecha del .bak
# mas reciente, y la franja de estado avisa si el respaldo se quedo atras.
Start-Transcript -Path (Join-Path $carpetaLocal 'ultimo-respaldo.log') -Force | Out-Null
Write-Host "=== EHS · respaldar ($sello) ==="

# ------------------------------------------------------------------- el respaldo

# Sin 'compression': SQL Server Express la rechaza (Msg 1844, "not supported on
# Express Edition"), y la primera version de este script la pedia — ningun
# respaldo habria salido nunca, ni el diario ni el de despues de cada captura.
# 'checksum' si esta en Express y hace que un .bak corrupto se note al restaurar.

if ($cfg['EHS_MOTOR'] -eq 'contenedor') {
    $herramienta = @('docker', 'podman') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
    if (-not $herramienta) { throw "Ni docker ni podman estan disponibles." }
    # Dentro del volumen del propio contenedor y despues 'cp' hacia afuera, en vez de
    # montar una carpeta de Windows: el motor corre como el usuario 'mssql' del
    # contenedor, y escribir en una carpeta de Windows montada depende de como cada
    # instalacion de Docker/Podman traduzca los permisos — con 'cp' no depende de nada.
    $rutaEnContenedor = "/var/opt/mssql/respaldo/$nombreArchivo"
    & $herramienta exec ehs-motor mkdir -p /var/opt/mssql/respaldo
    & $herramienta exec ehs-motor /opt/mssql-tools18/bin/sqlcmd -C -b -S localhost `
        -U $cfg['SQL_MIGRADOR_USUARIO'] -P $cfg['SQL_MIGRADOR_CLAVE'] `
        -Q "backup database analitica to disk = N'$rutaEnContenedor' with format, init, checksum;"
    if ($LASTEXITCODE -ne 0) { throw "BACKUP DATABASE termino con codigo $LASTEXITCODE." }
    & $herramienta cp "ehs-motor:$rutaEnContenedor" $rutaLocal
    if ($LASTEXITCODE -ne 0) { throw "No se pudo copiar el respaldo fuera del contenedor (codigo $LASTEXITCODE)." }
    & $herramienta exec ehs-motor rm -f $rutaEnContenedor
} else {
    & $cfg['EHS_SQLCMD'] -C -b -S "$($cfg['SQL_SERVIDOR']),$($cfg['SQL_PUERTO'])" `
        -U $cfg['SQL_MIGRADOR_USUARIO'] -P $cfg['SQL_MIGRADOR_CLAVE'] `
        -Q "backup database analitica to disk = N'$rutaLocal' with format, init, checksum;"
    if ($LASTEXITCODE -ne 0) { throw "BACKUP DATABASE termino con codigo $LASTEXITCODE." }
}

if (-not (Test-Path $rutaLocal)) { throw "El respaldo deberia estar en $rutaLocal y no aparece." }
Write-Host "Respaldo local listo: $rutaLocal" -ForegroundColor Green

# ------------------------------------------------------------------- a OneDrive

# SOLO OneDriveCommercial: es la variable que Windows fija cuando OneDrive para
# empresas esta configurado con la cuenta corporativa. $env:OneDrive a secas puede ser
# una cuenta PERSONAL (asi paso en el equipo de prueba: el respaldo con el dato de la
# empresa termino en un OneDrive personal). Sin cuenta corporativa, el respaldo se
# queda solo en el equipo.
$carpetaOneDrive = $env:OneDriveCommercial
if ($carpetaOneDrive) {
    $destino = Join-Path $carpetaOneDrive 'EHS-respaldo'
    New-Item -ItemType Directory -Force -Path $destino | Out-Null
    Copy-Item $rutaLocal -Destination $destino -Force -ErrorAction Stop
    Write-Host "Copiado a OneDrive: $destino\$nombreArchivo" -ForegroundColor Green
} else {
    Write-Warning ("No hay OneDrive corporativo configurado en este equipo (OneDriveCommercial). " +
                   "El respaldo quedo solo en $rutaLocal.")
}

# Conserva los ultimos 14 respaldos locales: diario mas uno por captura puede sumar
# varios al dia, y esta carpeta no debe crecer sin limite.
$viejos = Get-ChildItem $carpetaLocal -Filter 'ehs-analitica-*.bak' |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 14
if ($viejos) {
    $viejos | Remove-Item -Force
    Write-Host "Se retiraron $(@($viejos).Count) respaldo(s) local(es) mas antiguos."
}

Write-Host "Listo." -ForegroundColor Green
Stop-Transcript | Out-Null
