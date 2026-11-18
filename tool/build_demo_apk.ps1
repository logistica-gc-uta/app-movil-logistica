<#
.SYNOPSIS
Compila el APK release de demostración, identificado por versión, entorno y commit.

.DESCRIPTION
Lee la URL de la API de config/<entorno>.json (no versionado; se copia del
.example.json). Exige un árbol de trabajo limpio para que el APK corresponda a
un commit exacto. Deja en build/demo/ el APK, su SHA-256 y un archivo con los
datos de la build. No escribe tokens, contraseñas ni claves del keystore.

.EXAMPLE
.\tool\build_demo_apk.ps1 -Environment staging

.EXAMPLE
.\tool\build_demo_apk.ps1 -Environment lan -AllowDirty
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('emulator', 'lan', 'staging')]
    [string]$Environment,

    # Permite compilar con cambios sin confirmar; la build queda marcada -dirty.
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# --- Configuración del entorno ---------------------------------------------
$configPath = "config/$Environment.json"
if (-not (Test-Path $configPath)) {
    throw "Falta $configPath. Cópialo de config/$Environment.example.json y completa API_BASE_URL."
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$apiUrl = [string]$config.API_BASE_URL
if ([string]$config.APP_ENV -ne $Environment) {
    throw "APP_ENV en $configPath debe ser '$Environment'."
}
if ($apiUrl -match '[<>]') {
    throw "$configPath todavía tiene el valor de ejemplo en API_BASE_URL."
}
$apiUri = $null
if (-not [Uri]::TryCreate($apiUrl, [UriKind]::Absolute, [ref]$apiUri) -or
    ($apiUri.Scheme -ne 'http' -and $apiUri.Scheme -ne 'https')) {
    throw "API_BASE_URL no es una URL http(s) válida: $apiUrl"
}
if ($apiUri.UserInfo) {
    throw 'API_BASE_URL no puede incluir usuario ni contraseña.'
}
$allowHttp = [string]$config.ALLOW_INSECURE_HTTP -eq 'true'
if ($Environment -eq 'staging' -and ($apiUri.Scheme -ne 'https' -or $allowHttp)) {
    throw 'El staging solo se compila con HTTPS y ALLOW_INSECURE_HTTP=false.'
}
if ($apiUri.Scheme -eq 'http' -and -not $allowHttp) {
    throw "API_BASE_URL usa http:// pero ALLOW_INSECURE_HTTP no es 'true': la app no arrancaría."
}

# --- Identidad de la build ---------------------------------------------------
$dirty = git status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer el estado de git.' }
if ($dirty -and -not $AllowDirty) {
    throw 'Hay cambios sin confirmar. El APK debe corresponder a un commit: confirma los cambios o usa -AllowDirty.'
}
$commit = (git rev-parse HEAD).Trim()
$shortCommit = $commit.Substring(0, 7)
if ($dirty) {
    $commit = "$commit-dirty"
    $shortCommit = "$shortCommit-dirty"
}

$pubspec = Get-Content pubspec.yaml -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\S+)') {
    throw 'No se encontró la versión en pubspec.yaml.'
}
$version = $Matches[1]

$flutterVersion = 'desconocida'
try {
    $machine = (flutter --version --machine 2>$null) -join "`n"
    $flutterVersion = ($machine | ConvertFrom-Json).frameworkVersion
} catch {
    Write-Warning 'No se pudo leer la versión de Flutter.'
}

$releaseKeystore = Test-Path 'android/key.properties'
$signing = if ($releaseKeystore) { 'keystore release (android/key.properties)' } else { 'clave debug (solo demostración)' }
if (-not $releaseKeystore) {
    Write-Warning 'android/key.properties no existe: el APK se firma con la clave debug.'
}

# --- Compilación ---------------------------------------------------------------
Write-Host "Compilando Speedrun $version ($Environment, $shortCommit) contra $($apiUri.Scheme)://$($apiUri.Authority)"
flutter build apk --release `
    "--dart-define-from-file=$configPath" `
    "--dart-define=GIT_COMMIT=$shortCommit" `
    "--dart-define=APP_VERSION=$version"
if ($LASTEXITCODE -ne 0) { throw "flutter build apk terminó con código $LASTEXITCODE." }

# --- Artefacto identificado ----------------------------------------------------
$outDir = 'build/demo'
New-Item -ItemType Directory -Force $outDir | Out-Null
$safeVersion = $version -replace '\+', '-b'
$name = "speedrun-$safeVersion-$Environment-$shortCommit"
$apk = Join-Path $outDir "$name.apk"
Copy-Item 'build/app/outputs/flutter-apk/app-release.apk' $apk -Force
$sha256 = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()

$info = @(
    'app: Speedrun (com.logisticagcuta.app_movil_logistica)',
    "version: $version",
    "entorno: $Environment",
    "api: $($apiUri.Scheme)://$($apiUri.Authority)$($apiUri.AbsolutePath.TrimEnd('/'))",
    "commit: $commit",
    "fecha: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    "flutter: $flutterVersion",
    "firma: $signing",
    "sha256: $sha256"
)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines((Join-Path $root "$outDir/$name.txt"), $info, $utf8)
[IO.File]::WriteAllText((Join-Path $root "$apk.sha256"), "$sha256  $name.apk`n", $utf8)

Write-Host ''
Write-Host "APK:     $apk"
Write-Host "SHA-256: $sha256"
Write-Host "Datos:   $outDir/$name.txt"
Write-Host "Instalar: adb install -r `"$apk`""
