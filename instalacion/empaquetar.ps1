#Requires -Version 5.1
<#
.SYNOPSIS
    Arma el paquete distribuible: la app, node.exe portable, y un .zip listo
    para copiar al equipo del area. Corre en la maquina de desarrollo, nunca en
    la de destino.

.DESCRIPTION
    node.exe adentro de la carpeta del paquete es lo que hace que el equipo del
    area no necesite instalar Node: instalar.ps1 lo usa directamente si existe
    (ver su variable $NodeBundle), y solo cae al node del PATH cuando no lo
    encuentra — que es exactamente lo que pasa al correr instalar.ps1 sin haber
    empaquetado antes, para poder probarlo en la maquina de desarrollo.

    node_modules se copia TAL COMO ESTA en app\ (con --omit=dev ya aplicado, si
    se corrio npm install --omit=dev antes de empaquetar): el hallazgo de la
    auditoria de Fase A fue que la produccion son 83 paquetes / 50 MB, cero
    binarios nativos, asi que copiar la carpeta entera sin reconstruir nada
    funciona igual en el equipo de destino siempre que sea el mismo Windows x64.

.PARAMETER CarpetaSalida
    Donde queda el paquete armado (una carpeta y un .zip al lado). Por defecto,
    una carpeta 'paquete' junto a app\.

.PARAMETER RutaNodePortable
    Ruta a un node.exe de Windows x64 ya descargado (el .zip "win-x64" de
    nodejs.org, extraido). Sin este parametro, el paquete queda SIN node.exe
    propio — instalar.ps1 seguira funcionando en la maquina de desarrollo (usa
    el node del PATH), pero el paquete no cumple "cero Node en el equipo del
    area" hasta que se le agregue.
#>
[CmdletBinding()]
param(
    [string]$CarpetaSalida,
    [string]$RutaNodePortable
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RaizApp = Split-Path -Parent $PSScriptRoot
if (-not $CarpetaSalida) { $CarpetaSalida = Join-Path (Split-Path -Parent $RaizApp) 'paquete' }
$CarpetaPaqueteApp = Join-Path $CarpetaSalida 'app'
$CarpetaPaqueteNode = Join-Path $CarpetaSalida 'node'

Write-Host "=== EHS · empaquetar ===" -ForegroundColor Cyan
Write-Host "Origen : $RaizApp"
Write-Host "Salida : $CarpetaSalida"

if (Test-Path $CarpetaSalida) {
    Write-Host "La carpeta de salida ya existe: se limpia antes de armar de nuevo."
    Remove-Item $CarpetaSalida -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $CarpetaPaqueteApp | Out-Null

# ------------------------------------------------------------------- copiar la app

# robocopy y no Copy-Item -Recurse: reporta que se quedo afuera, y /XD/​/XF son mas
# claros de leer despues que reconstruir una lista de exclusiones con -Exclude
# (que ademas en Copy-Item solo filtra por nombre de archivo, no por carpeta).
$excluirCarpetas = @('.git', 'config', 'node_modules\.bin')
$excluirArchivos = @('.env', 'ehs.env')

robocopy $RaizApp $CarpetaPaqueteApp /E /XD $excluirCarpetas /XF $excluirArchivos /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy fallo copiando la app (codigo $LASTEXITCODE)." }

# node_modules SI se copia (robocopy /E lo incluye): es la app entera, produccion
# incluida, tal como quedo instalada en la maquina de desarrollo. Si se empaqueta
# sin haber corrido antes 'npm install --omit=dev', el paquete carga tambien
# eslint/prettier/echarts-fuente de mas — no rompe nada, solo pesa mas de lo
# necesario. empaquetar.ps1 no lo hace por su cuenta para no dejar la maquina de
# desarrollo sin sus propias devDependencies a medio trabajo.
if (-not (Test-Path (Join-Path $CarpetaPaqueteApp 'node_modules'))) {
    Write-Warning "No hay node_modules en el origen. Corre 'npm install --omit=dev' en app\ antes de empaquetar."
}

# La plantilla de configuracion SI viaja (sin credenciales); el archivo real,
# si existiera en la maquina de desarrollo, se excluyo arriba a proposito.
New-Item -ItemType Directory -Force -Path (Join-Path $CarpetaPaqueteApp 'config') | Out-Null
Copy-Item (Join-Path $RaizApp 'config\ehs.env.ejemplo') -Destination (Join-Path $CarpetaPaqueteApp 'config\ehs.env.ejemplo')

# ------------------------------------------------------------------- node portable

if ($RutaNodePortable -and (Test-Path $RutaNodePortable)) {
    Write-Host "Copiando node.exe portable…"
    New-Item -ItemType Directory -Force -Path $CarpetaPaqueteNode | Out-Null
    $origenNode = Join-Path $RutaNodePortable 'node.exe'
    if (-not (Test-Path $origenNode)) { throw "No se encontro node.exe en $RutaNodePortable." }
    Copy-Item $origenNode -Destination $CarpetaPaqueteNode
} else {
    Write-Warning ("Sin -RutaNodePortable: el paquete queda SIN node.exe propio. " +
                   "instalar.ps1 usara el node del PATH — valido para probar en la maquina de desarrollo, " +
                   "no para el equipo del area (requisito: cero Node instalado ahi).")
}

# ------------------------------------------------------------------------- zip

$rutaZip = "$CarpetaSalida.zip"
if (Test-Path $rutaZip) { Remove-Item $rutaZip -Force }
Write-Host "Comprimiendo…"
Compress-Archive -Path "$CarpetaSalida\*" -DestinationPath $rutaZip -CompressionLevel Optimal

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host "Paquete: $rutaZip"
Write-Host "En el equipo de destino: extraer, y correr instalacion\instalar.ps1 -Motor nativo|contenedor"
Write-Host "desde dentro de app\ (ver instalacion\requisitos-it.md)."
