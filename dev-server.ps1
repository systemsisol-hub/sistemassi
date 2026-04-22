# Script de desarrollo con auto-recompilación
Write-Host "🚀 Servidor de desarrollo Flutter Web"
Write-Host "Monitoreando cambios en lib/ y pubspec.yaml..."
Write-Host ""

$port = 8080
$webDir = "build\web"

# Función para compilar
function Build-Web {
    Write-Host "`n🔨 Compilando..." -ForegroundColor Yellow
    flutter build web --no-tree-shake-icons
    if ($LASTEXITCODE -eq 0) {
        Write-Host ✅ Compilación exitosa -ForegroundColor Green
        return $true
    } else {
        Write-Host ❌ Error de compilación -ForegroundColor Red
        return $false
    }
}

# Compilar inicial
if (!(Build-Web)) {
    exit 1
}

# Iniciar servidor
Write-Host "`n🌐 Iniciando servidor en http://localhost:$port" -ForegroundColor Cyan
Write-Host "Presiona CTRL+C para detener" -ForegroundColor Gray
Write-Host ""

# Monitorear cambios en archivos
$fileSystemWatcher = New-Object System.IO.FileSystemWatcher
$fileSystemWatcher.Path = (Get-Item "lib").FullName
$fileSystemWatcher.IncludeSubdirectories = $true
$fileSystemWatcher.EnableRaisingEvents = $true

# También monitorear pubspec.yaml
$pubspecWatcher = New-Object System.IO.FileSystemWatcher
$pubspecWatcher.Path = (Get-Item ".").FullName
$pubspecWatcher.Filter = "pubspec.yaml"
$pubspecWatcher.EnableRaisingEvents = $true

$lastBuild = Get-Date

function Handle-Change {
    $now = Get-Date
    if ($now - $lastBuild | Select-Object -ExpandProperty TotalSeconds | % { $_ -gt 2 }) {
        $global:lastBuild = $now
        Build-Web
    }
}

$fileSystemWatcher.add_Changed({ Handle-Change })
$fileSystemWatcher.add_Created({ Handle-Change })
$fileSystemWatcher.add_Deleted({ Handle-Change })

$pubspecWatcher.add_Changed({ Handle-Change })

# Iniciar servidor HTTP
npx http-server $webDir -p $port -c-1
