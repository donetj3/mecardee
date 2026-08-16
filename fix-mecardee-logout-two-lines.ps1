Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$path = "E:\mecardee-car-wash\app\globals.css"

if (-not (Test-Path -LiteralPath $path)) {
    throw "File not found: $path"
}

$backup = "E:\mecardee-car-wash\app\globals.css.before-logout-label-fix-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $path -Destination $backup -Force

$css = [System.IO.File]::ReadAllText($path)

$old = @'
  .app-shell .topbar .top-actions > button.secondary-button.logout-button::after {
    content: "Out" !important;
    display: block !important;
    font-size: 9px !important;
    font-weight: 800 !important;
    line-height: 1 !important;
  }
'@

$new = @'
  .app-shell .topbar .top-actions > button.secondary-button.logout-button::after {
    content: "Log\A Out" !important;
    display: block !important;
    white-space: pre-line !important;
    text-align: center !important;
    font-size: 8px !important;
    font-weight: 800 !important;
    line-height: .95 !important;
  }
'@

if (-not $css.Contains($old)) {
    throw "Could not find the exact mobile logout label rule. No file was changed."
}

$css = $css.Replace($old, $new)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $css, $utf8NoBom)

Set-Location "E:\mecardee-car-wash"

npm.cmd run build

if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $path -Force
    throw "Build failed. Original CSS was restored."
}

Write-Host ""
Write-Host "Logout label fixed." -ForegroundColor Green
Write-Host "Mobile button now shows:" -ForegroundColor Green
Write-Host "Log"
Write-Host "Out"
Write-Host ""
Write-Host "Backup: $backup" -ForegroundColor Yellow
