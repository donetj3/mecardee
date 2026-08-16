Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "E:\mecardee-car-wash"
$cssPath = Join-Path $root "app\globals.css"

if (-not (Test-Path -LiteralPath $cssPath)) {
    throw "File not found: $cssPath"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $root "app\globals.css.before-topbar-rollback-$stamp"

Copy-Item -LiteralPath $cssPath -Destination $backupPath -Force

$css = [System.IO.File]::ReadAllText($cssPath)
$original = $css

$patterns = @(
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/\s*'
)

foreach ($pattern in $patterns) {
    $css = [System.Text.RegularExpressions.Regex]::Replace($css, $pattern, "`r`n")
}

if ($css -eq $original) {
    Write-Warning "No mobile topbar patch blocks were found. Nothing was changed."
    exit 0
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$locationPushed = $false

try {
    [System.IO.File]::WriteAllText($cssPath, $css.TrimEnd() + "`r`n", $utf8NoBom)

    Push-Location $root
    $locationPushed = $true

    Write-Host "Running production build..." -ForegroundColor Cyan
    & npm.cmd run build

    if ($LASTEXITCODE -ne 0) {
        throw "Next.js build failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Mobile topbar rollback completed." -ForegroundColor Green
    Write-Host "Your old header CSS is restored." -ForegroundColor Green
    Write-Host "Sync is no longer hidden by my mobile patches." -ForegroundColor Green
    Write-Host ""
    Write-Host "Only app\globals.css was changed." -ForegroundColor Green
    Write-Host "Backup: $backupPath" -ForegroundColor Yellow
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $cssPath -Force

    Write-Host ""
    Write-Host "Rollback failed. Original CSS restored automatically." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}
