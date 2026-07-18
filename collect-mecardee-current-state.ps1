param(
  [Parameter(Mandatory = $false)]
  [string]$ProjectPath = "E:\mecardee-car-wash"
)

$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path $ProjectPath).Path

$required = @(
  "app\page.jsx",
  "app\globals.css",
  "app\layout.jsx",
  "app\api\report\route.jsx",
  "lib\supabase.js",
  "package.json"
)

foreach ($relativePath in $required) {
  $fullPath = Join-Path $ProjectPath $relativePath
  if (-not (Test-Path $fullPath)) {
    throw "Required project file was not found: $fullPath"
  }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$workDir = Join-Path $env:TEMP "mecardee-current-state-$stamp"
$zipPath = Join-Path $ProjectPath "mecardee-current-state-$stamp.zip"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null

foreach ($relativePath in $required) {
  $source = Join-Path $ProjectPath $relativePath
  $destination = Join-Path $workDir $relativePath
  New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
  Copy-Item $source $destination -Force
}

$migrationSource = Join-Path $ProjectPath "supabase\migrations"
if (Test-Path $migrationSource) {
  $migrationDestination = Join-Path $workDir "supabase\migrations"
  New-Item -ItemType Directory -Force -Path $migrationDestination | Out-Null
  Copy-Item (Join-Path $migrationSource "*") $migrationDestination -Recurse -Force
}

$info = New-Object System.Collections.Generic.List[string]
$info.Add("Mecardee current-state package")
$info.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$info.Add("Project: $ProjectPath")
$info.Add("")
$info.Add("=== GIT STATUS ===")
$info.AddRange([string[]](& git -C $ProjectPath status --short 2>&1))
$info.Add("")
$info.Add("=== LAST COMMIT ===")
$info.AddRange([string[]](& git -C $ProjectPath log -1 --oneline 2>&1))
$info.Add("")
$info.Add("=== PATCH MARKERS ===")
$markers = Select-String `
  -Path (Join-Path $ProjectPath "app\page.jsx"), (Join-Path $ProjectPath "app\globals.css") `
  -Pattern "MECARDEE_[A-Z0-9_]+" `
  -AllMatches

foreach ($marker in $markers) {
  $info.Add("$($marker.Path):$($marker.LineNumber): $($marker.Line.Trim())")
}

[System.IO.File]::WriteAllLines(
  (Join-Path $workDir "CURRENT_STATE.txt"),
  $info,
  [System.Text.UTF8Encoding]::new($false)
)

if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $workDir "*") -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $workDir -Recurse -Force

Write-Host ""
Write-Host "Current Mecardee source package created:" -ForegroundColor Green
Write-Host $zipPath -ForegroundColor Cyan
Write-Host ""
Write-Host "This package does not include .env.local, database passwords, node_modules, .next, or Git credentials." -ForegroundColor DarkGray
