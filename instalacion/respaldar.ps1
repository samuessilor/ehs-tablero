#Requires -Version 5.1
<#
.SYNOPSIS
    Respalda la base analitica y copia el archivo a OneDrive corporativo.

.DESCRIPTION
    Dos pasos separados a proposito, tal como los describe el encargo: "el
    servicio del motor escribe en una carpeta compartida; la app copia el
    archivo a OneDrive". El motor SOLO sabe escribir en su propio disco (o en la
    carpeta que instalar.ps1 le monto); nunca habla con OneDrive directamente.
    Este script es quien hace el segundo paso.

    Lo corre la tarea programada diaria que crea instalar.ps1, y tambien se
    puede correr a mano o disparado desde la aplicacion despues de una captura
    (ver el comentario en src/datos/escritura_sql.js).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Leer-Config {
    $ruta = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\ehs.env'
    if (-not (Test-Path $ruta)) { throw "No existe $ruta. ¿Se corrio instalar.ps1?" }
    $variables = @{}
    foreach ($linea in Get-Content $ruta) {
        $t = $linea.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 0) { continue }
        $variables[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $variables
}

$cfg = Leer-Config
$sello = Get-Date -Format 'yyyyMMdd-HHmmss'
$nombreArchivo = "ehs-analitica-$sello.bak"

Write-Host "=== EHS · respaldar ($sello) ==="

# ------------------------------------------------------------------- el respaldo

if ($cfg['EHS_MOTOR'] -eq 'contenedor') {
    $rutaEnContenedor = "/var/opt/mssql-respaldo/$nombreArchivo"
    Write-Host "Motor en contenedor: BACKUP DATABASE hacia $rutaEnContenedor…"
    docker exec ehs-motor /opt/mssql-tools18/bin/sqlcmd `
        -C -S localhost -U $cfg['SQL_MIGRADOR_USUARIO'] -P $cfg['SQL_MIGRADOR_CLAVE'] `
        -Q "backup database analitica to disk = N'$rutaEnContenedor' with format, init, compression;"
} else {
    $rutaLocal = Join-Path $cfg['EHS_CARPETA_RESPALDO'] $nombreArchivo
    Write-Host "Motor nativo: BACKUP DATABASE hacia $rutaLocal…"
    & sqlcmd -C -S "$($cfg['SQL_SERVIDOR']),$($cfg['SQL_PUERTO'])" `
        -U $cfg['SQL_MIGRADOR_USUARIO'] -P $cfg['SQL_MIGRADOR_CLAVE'] `
        -Q "backup database analitica to disk = N'$rutaLocal' with format, init, compression;"
}
if ($LASTEXITCODE -ne 0) { throw "BACKUP DATABASE termino con codigo $LASTEXITCODE." }

$rutaLocalFinal = Join-Path $cfg['EHS_CARPETA_RESPALDO'] $nombreArchivo
if (-not (Test-Path $rutaLocalFinal)) {
    throw "El respaldo deberia haber quedado en $rutaLocalFinal y no aparece. " +
          "Si el motor esta en contenedor, revisa que el volumen siga montado."
}
Write-Host "Respaldo local listo: $rutaLocalFinal" -ForegroundColor Green

# ------------------------------------------------------------------- a OneDrive

# OneDriveCommercial es la variable que Windows fija cuando OneDrive para empresas
# ya esta configurado con la cuenta corporativa — es la senal de que existe una
# carpeta que se sincroniza sola, sin que este script sepa nada de como sincroniza.
$carpetaOneDrive = if ($env:OneDriveCommercial) { $env:OneDriveCommercial } else { $env:OneDrive }
if ($carpetaOneDrive) {
    $destino = Join-Path $carpetaOneDrive 'EHS-respaldo'
    New-Item -ItemType Directory -Force -Path $destino | Out-Null
    Copy-Item $rutaLocalFinal -Destination $destino -Force
    Write-Host "Copiado a OneDrive: $destino\$nombreArchivo" -ForegroundColor Green
} else {
    Write-Warning ("No se detecto OneDrive configurado en este equipo (variable OneDriveCommercial " +
                   "ausente). El respaldo quedo solo en $rutaLocalFinal — revisa la sincronizacion de OneDrive.")
}

# Conserva solo los ultimos 14 respaldos locales: un respaldo diario mas uno por
# captura puede acumular varios al dia, y esta carpeta no deberia crecer sin limite.
$viejos = Get-ChildItem $cfg['EHS_CARPETA_RESPALDO'] -Filter 'ehs-analitica-*.bak' |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 14
if ($viejos) {
    $viejos | Remove-Item -Force
    Write-Host "Se retiraron $($viejos.Count) respaldo(s) local(es) mas antiguos."
}

Write-Host "Listo." -ForegroundColor Green
