# Arrancar, detener y esperar el tablero, sin tarea programada. Lo cargan
# instalar.ps1, reparar.ps1, actualizar.ps1 y desinstalar.ps1 con
# '. "$PSScriptRoot\tablero.ps1"'.
#
# El tablero arranca al iniciar sesion desde un acceso directo en la carpeta Inicio
# de la persona del area (lo crea instalar.ps1), no desde el Programador de tareas:
# registrar una tarea exige un PowerShell elevado, y el modo contenedor se instala
# sin administrador. conhost --headless lanza node SIN ventana de consola (probado:
# MainWindowHandle = 0).

function Procesos-Tablero {
    param([string]$RaizApp)
    $servidor = (Join-Path $RaizApp 'servidor.js').ToLowerInvariant()
    # Por la ruta completa de servidor.js en la linea de comandos, no por nombre de
    # proceso: en el mismo equipo puede haber otros node.exe que no son este tablero.
    @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($servidor) })
}

function Detener-Tablero {
    param([string]$RaizApp)
    foreach ($p in Procesos-Tablero $RaizApp) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

function Iniciar-Tablero {
    param([string]$RaizApp, [string]$NodeExe)
    # @(...) obligatorio: la funcion devuelve nada o un solo proceso (PowerShell
    # desenrolla el arreglo), y con StrictMode '.Count' sobre eso lanza error — en la
    # primera instalacion real salio en pantalla, y con el tablero ya corriendo habria
    # arrancado un segundo node.exe peleando por el mismo puerto.
    if (@(Procesos-Tablero $RaizApp).Count -gt 0) { return }
    $servidor = Join-Path $RaizApp 'servidor.js'
    Start-Process -FilePath "$env:SystemRoot\System32\conhost.exe" -WorkingDirectory $RaizApp -WindowStyle Hidden `
        -ArgumentList @('--headless', "`"$NodeExe`"", "`"$servidor`"")
}

function Esperar-Tablero {
    param([int]$Puerto, [int]$TimeoutSeg = 60)
    $limite = (Get-Date).AddSeconds($TimeoutSeg)
    while ((Get-Date) -lt $limite) {
        try {
            $s = Invoke-RestMethod -Uri "http://127.0.0.1:$Puerto/api/ehs/salud" -TimeoutSec 5
            if ($s.disponible) { return $s }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $null
}

# El node.exe que viaja en el paquete (node\ junto a app\), o el del PATH si no hay.
function Buscar-NodeExe {
    param([string]$RaizApp)
    $empaquetado = Join-Path (Split-Path -Parent $RaizApp) 'node\node.exe'
    if (Test-Path $empaquetado) { return $empaquetado }
    return (Get-Command node -ErrorAction SilentlyContinue).Source
}

# El acceso directo que arranca el tablero al iniciar sesion. Mismo destino que usa
# Iniciar-Tablero, para que Procesos-Tablero reconozca las dos formas de arrancarlo.
function Ruta-AccesoInicio {
    param([string]$CarpetaInicio)
    Join-Path $CarpetaInicio 'EHS Tablero.lnk'
}
