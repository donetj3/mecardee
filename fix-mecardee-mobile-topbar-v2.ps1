Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "E:\mecardee-car-wash"
$cssPath = Join-Path $root "app\globals.css"

if (-not (Test-Path -LiteralPath $cssPath)) {
    throw "File not found: $cssPath"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $root "app\globals.css.before-mobile-topbar-v2-$stamp"

Copy-Item -LiteralPath $cssPath -Destination $backupPath -Force

$css = [System.IO.File]::ReadAllText($cssPath)

$patch = @'
/* MECARDEE_MOBILE_TOPBAR_FIT_V2 */
@media (max-width: 760px) {
  .topbar {
    width: 100% !important;
    max-width: 100vw !important;
    box-sizing: border-box !important;
    display: grid !important;
    grid-template-columns: 88px minmax(0, 1fr) !important;
    align-items: center !important;
    gap: 8px !important;
    padding-left: max(10px, env(safe-area-inset-left)) !important;
    padding-right: max(10px, env(safe-area-inset-right)) !important;
    overflow: hidden !important;
  }

  .topbar .brand {
    width: 88px !important;
    min-width: 0 !important;
    max-width: 88px !important;
    overflow: hidden !important;
  }

  .topbar .brand > span:not(.brand-mark) {
    display: none !important;
  }

  .topbar .brand-mark.logo-image,
  .topbar .brand-mark.logo-image img {
    display: block !important;
    width: 88px !important;
    min-width: 0 !important;
    max-width: 88px !important;
    height: auto !important;
    object-fit: contain !important;
  }

  .topbar .top-actions {
    width: 100% !important;
    min-width: 0 !important;
    max-width: none !important;
    display: grid !important;
    grid-template-columns: repeat(5, 34px) !important;
    justify-content: end !important;
    align-items: center !important;
    gap: 4px !important;
    overflow: visible !important;
  }

  .topbar .top-actions > .sync-pill {
    display: none !important;
  }

  /*
   * Add Work already exists directly below the header on mobile.
   * Hide only the final header button to prevent duplication.
   */
  .topbar .top-actions > button:last-child {
    display: none !important;
  }

  .topbar .top-actions > button:not(:last-child) {
    display: grid !important;
    place-items: center !important;
    width: 34px !important;
    min-width: 34px !important;
    max-width: 34px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
    padding: 0 !important;
    margin: 0 !important;
    border-radius: 9px !important;
    overflow: hidden !important;
    white-space: nowrap !important;
    font-size: 0 !important;
    line-height: 1 !important;
  }

  .topbar .top-actions > button:not(:last-child) > svg {
    display: block !important;
    width: 18px !important;
    height: 18px !important;
  }

  .topbar .top-actions > button:not(:last-child) > span {
    display: grid !important;
    place-items: center !important;
    font-size: 17px !important;
    line-height: 1 !important;
  }

  .topbar .top-actions .export-button::after {
    content: "PDF" !important;
    display: block !important;
    font-size: 8px !important;
    font-weight: 900 !important;
    line-height: 1 !important;
    letter-spacing: .15px !important;
  }

  .topbar .top-actions .logout-button::after {
    content: "OUT" !important;
    display: block !important;
    font-size: 7px !important;
    font-weight: 900 !important;
    line-height: 1 !important;
    letter-spacing: .2px !important;
  }

  .topbar .top-actions .notification-button::after,
  .topbar .top-actions .settings-button::after {
    content: none !important;
  }
}

@media (max-width: 370px) {
  .topbar {
    grid-template-columns: 78px minmax(0, 1fr) !important;
    gap: 6px !important;
    padding-left: max(8px, env(safe-area-inset-left)) !important;
    padding-right: max(8px, env(safe-area-inset-right)) !important;
  }

  .topbar .brand,
  .topbar .brand-mark.logo-image,
  .topbar .brand-mark.logo-image img {
    width: 78px !important;
    max-width: 78px !important;
  }

  .topbar .top-actions {
    grid-template-columns: repeat(5, 32px) !important;
    gap: 3px !important;
  }

  .topbar .top-actions > button:not(:last-child) {
    width: 32px !important;
    min-width: 32px !important;
    max-width: 32px !important;
    height: 32px !important;
    min-height: 32px !important;
    max-height: 32px !important;
  }
}
/* END MECARDEE_MOBILE_TOPBAR_FIT_V2 */
'@

# Remove both earlier versions so only one mobile header patch controls the layout.
$patterns = @(
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/\s*'
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
    Write-Host "Mobile top bar V2 fixed successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Mobile header now shows:" -ForegroundColor Green
    Write-Host "  - Logo"
    Write-Host "  - Sync"
    Write-Host "  - Alerts"
    Write-Host "  - PDF"
    Write-Host "  - Settings"
    Write-Host "  - Logout as a compact OUT button"
    Write-Host ""
    Write-Host "The duplicate header Add Work button is hidden on mobile." -ForegroundColor Green
    Write-Host "Desktop is unchanged." -ForegroundColor Green
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
