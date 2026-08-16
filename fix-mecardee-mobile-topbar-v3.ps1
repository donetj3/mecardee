Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "E:\mecardee-car-wash"
$cssPath = Join-Path $root "app\globals.css"

if (-not (Test-Path -LiteralPath $cssPath)) {
    throw "File not found: $cssPath"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $root "app\globals.css.before-mobile-topbar-v3-$stamp"

Copy-Item -LiteralPath $cssPath -Destination $backupPath -Force

$css = [System.IO.File]::ReadAllText($cssPath)

$patch = @'
/* MECARDEE_MOBILE_TOPBAR_CLEAN_V3 */
@media (max-width: 760px) {
  .topbar {
    width: 100% !important;
    max-width: 100vw !important;
    box-sizing: border-box !important;
    display: grid !important;
    grid-template-columns: 82px minmax(0, 1fr) !important;
    align-items: center !important;
    gap: 8px !important;
    padding-left: max(8px, env(safe-area-inset-left)) !important;
    padding-right: max(8px, env(safe-area-inset-right)) !important;
    overflow: hidden !important;
  }

  .topbar .brand {
    width: 82px !important;
    min-width: 0 !important;
    max-width: 82px !important;
    overflow: hidden !important;
  }

  .topbar .brand > span:not(.brand-mark) {
    display: none !important;
  }

  .topbar .brand-mark.logo-image,
  .topbar .brand-mark.logo-image img {
    display: block !important;
    width: 82px !important;
    min-width: 0 !important;
    max-width: 82px !important;
    height: auto !important;
    object-fit: contain !important;
  }

  .topbar .top-actions {
    width: 100% !important;
    min-width: 0 !important;
    max-width: none !important;
    display: grid !important;
    grid-template-columns: 36px 36px 64px 60px !important;
    justify-content: end !important;
    align-items: center !important;
    gap: 5px !important;
    overflow: visible !important;
  }

  /* Hide every mobile top-bar action first. */
  .topbar .top-actions > * {
    display: none !important;
  }

  /* Show only: notification, settings, export and logout. */
  .topbar .top-actions .notification-button,
  .topbar .top-actions .settings-button,
  .topbar .top-actions .export-button,
  .topbar .top-actions .logout-button {
    box-sizing: border-box !important;
    margin: 0 !important;
    border-radius: 10px !important;
    white-space: nowrap !important;
    overflow: hidden !important;
    line-height: 1 !important;
  }

  .topbar .top-actions .notification-button,
  .topbar .top-actions .settings-button {
    display: grid !important;
    place-items: center !important;
    width: 36px !important;
    min-width: 36px !important;
    max-width: 36px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 !important;
    font-size: 0 !important;
  }

  .topbar .top-actions .notification-button > span {
    display: grid !important;
    place-items: center !important;
    font-size: 18px !important;
    line-height: 1 !important;
  }

  .topbar .top-actions .settings-button svg {
    display: block !important;
    width: 18px !important;
    height: 18px !important;
  }

  .topbar .top-actions .export-button {
    display: grid !important;
    place-items: center !important;
    width: 64px !important;
    min-width: 64px !important;
    max-width: 64px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 8px !important;
    font-size: 0 !important;
  }

  .topbar .top-actions .export-button::after {
    content: "Export" !important;
    display: block !important;
    font-size: 10px !important;
    font-weight: 800 !important;
    line-height: 1 !important;
    letter-spacing: 0 !important;
  }

  .topbar .top-actions .logout-button {
    display: grid !important;
    place-items: center !important;
    width: 60px !important;
    min-width: 60px !important;
    max-width: 60px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 8px !important;
    font-size: 10px !important;
    font-weight: 800 !important;
  }

  .topbar .top-actions .logout-button::after {
    content: none !important;
  }
}

@media (max-width: 370px) {
  .topbar {
    grid-template-columns: 72px minmax(0, 1fr) !important;
    gap: 6px !important;
    padding-left: max(6px, env(safe-area-inset-left)) !important;
    padding-right: max(6px, env(safe-area-inset-right)) !important;
  }

  .topbar .brand,
  .topbar .brand-mark.logo-image,
  .topbar .brand-mark.logo-image img {
    width: 72px !important;
    max-width: 72px !important;
  }

  .topbar .top-actions {
    grid-template-columns: 34px 34px 58px 54px !important;
    gap: 4px !important;
  }

  .topbar .top-actions .notification-button,
  .topbar .top-actions .settings-button {
    width: 34px !important;
    min-width: 34px !important;
    max-width: 34px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
  }

  .topbar .top-actions .export-button {
    width: 58px !important;
    min-width: 58px !important;
    max-width: 58px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
  }

  .topbar .top-actions .logout-button {
    width: 54px !important;
    min-width: 54px !important;
    max-width: 54px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
    font-size: 9px !important;
  }

  .topbar .top-actions .export-button::after {
    font-size: 9px !important;
  }
}
/* END MECARDEE_MOBILE_TOPBAR_CLEAN_V3 */
'@

$patterns = @(
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/\s*'
)

foreach ($pattern in $patterns) {
    $css = [System.Text.RegularExpressions.Regex]::Replace($css, $pattern, "`r`n")
}

$css = $css.TrimEnd() + "`r`n`r`n" + $patch.Trim() + "`r`n"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$locationPushed = $false

try {
    [System.IO.File]::WriteAllText($cssPath, $css, $utf8NoBom)

    Push-Location $root
    $locationPushed = $true

    Write-Host "Running production build..." -ForegroundColor Cyan
    & npm.cmd run build

    if ($LASTEXITCODE -ne 0) {
        throw "Next.js build failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Clean mobile top bar applied successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Mobile now shows only:" -ForegroundColor Green
    Write-Host "  - Notification"
    Write-Host "  - Settings"
    Write-Host "  - Export"
    Write-Host "  - Logout"
    Write-Host ""
    Write-Host "Sync, LIVE and Add Work are hidden only in the mobile top bar." -ForegroundColor Green
    Write-Host "Desktop remains unchanged." -ForegroundColor Green
    Write-Host "Only app\globals.css was changed." -ForegroundColor Green
    Write-Host ""
    Write-Host "Backup: $backupPath" -ForegroundColor Yellow
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $cssPath -Force

    Write-Host ""
    Write-Host "Patch failed. Original CSS restored automatically." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}
