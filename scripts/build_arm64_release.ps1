param(
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDirectory '..')
$flutter = $env:FLUTTER_BIN
if ([string]::IsNullOrWhiteSpace($flutter)) {
  $flutter = 'flutter'
}

if (-not (Test-Path -LiteralPath $flutter)) {
  throw "Flutter executable not found: $flutter. Set FLUTTER_BIN to override it."
}

$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$versionLine = Get-Content -Encoding UTF8 -LiteralPath $pubspecPath |
  Where-Object { $_ -match '^version:\s*(.+)$' } |
  Select-Object -First 1
if ($versionLine -notmatch '^version:\s*(.+)$') {
  throw 'Could not read version from pubspec.yaml.'
}

$version = $Matches[1].Trim()
$safeVersion = $version -replace '[^\w.+-]', '_'
$releaseDirectory = Join-Path $repoRoot 'release'
$sourceApk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
$targetApk = Join-Path $releaseDirectory "LoveDiary-$safeVersion-arm64-v8a-release.apk"

Push-Location $repoRoot
try {
  if (-not $SkipBuild) {
    & $flutter build apk --release --target-platform android-arm64 --split-per-abi
  }

  if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Expected APK was not produced: $sourceApk"
  }

  New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
  Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
  Write-Host "Arm64 release APK copied to: $targetApk"
} finally {
  Pop-Location
}
