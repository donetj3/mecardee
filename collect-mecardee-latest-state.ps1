param(
  [Parameter(Mandatory = $false)]
  [string]$ProjectPath = "E:\mecardee-car-wash"
)

$ErrorActionPreference = "Stop"
$ProjectPath = (Resolve-Path $ProjectPath).Path

$include = @(
  "app\page.jsx",
  "app\globals.css",
  "app\layout.jsx",
  "app\api\report\route.jsx",
  "lib\supabase.js",
  "package.json",
  ".gitignore"
)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempRoot = Join-Path $env:TEMP "mecardee-latest-state-$stamp"
$zipPath = Join-Path $ProjectPath "mecardee-latest-state-$stamp.zip"

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

foreach ($relative in $include) {
  $source = Join-Path $ProjectPath $relative

  if (Test-Path $source) {
    $destination = Join-Path $tempRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item $source $destination -Force
  }
}

$migrationsSource = Join-Path $ProjectPath "supabase\migrations"

if (Test-Path $migrationsSource) {
  $migrationsDestination = Join-Path $tempRoot "supabase\migrations"
  New-Item -ItemType Directory -Force -Path $migrationsDestination | Out-Null
  Copy-Item (Join-Path $migrationsSource "*") $migrationsDestination -Recurse -Force
}

$state = New-Object System.Collections.Generic.List[string]
$state.Add("Mecardee latest source state")
$state.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$state.Add("Project: $ProjectPath")
$state.Add("")
$state.Add("=== GIT STATUS ===")
$state.AddRange([string[]](& git -C $ProjectPath status --short 2>&1))
$state.Add("")
$state.Add("=== LAST FIVE COMMITS ===")
$state.AddRange([string[]](& git -C $ProjectPath log -5 --oneline 2>&1))
$state.Add("")
$state.Add("=== PATCH MARKERS ===")

$markerFiles = @(
  (Join-Path $ProjectPath "app\page.jsx"),
  (Join-Path $ProjectPath "app\globals.css")
) | Where-Object { Test-Path $_ }

if ($markerFiles.Count -gt 0) {
  $markers = Select-String `
    -Path $markerFiles `
    -Pattern "MECARDEE_[A-Z0-9_]+" `
    -AllMatches

  foreach ($marker in $markers) {
    $state.Add("$($marker.Path):$($marker.LineNumber): $($marker.Line.Trim())")
  }
}

[System.IO.File]::WriteAllLines(
  (Join-Path $tempRoot "CURRENT_STATE.txt"),
  $state,
  [System.Text.UTF8Encoding]::new($false)
)

if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Compress-Archive `
  -Path (Join-Path $tempRoot "*") `
  -DestinationPath $zipPath `
  -CompressionLevel Optimal

Remove-Item $tempRoot -Recurse -Force

Write-Host ""
Write-Host "Latest Mecardee source package created:" -ForegroundColor Green
Write-Host $zipPath -ForegroundColor Cyan
Write-Host ""
Write-Host "Excluded: .env.local, passwords, service-role keys, node_modules, .next, backups and Git credentials." -ForegroundColor DarkGray
