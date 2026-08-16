Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "E:\mecardee-car-wash"
$cssPath = Join-Path $root "app\globals.css"

if (-not (Test-Path -LiteralPath $cssPath)) {
    throw "File not found: $cssPath"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $root "app\globals.css.before-mobile-topbar-fix-$stamp"

Copy-Item -LiteralPath $cssPath -Destination $backupPath -Force

$css = [System.IO.File]::ReadAllText($cssPath)

$patch = @'
/* MECARDEE_MOBILE_TOPBAR_FIT_V1 */
@media (max-width: 760px) {
  .topbar {
    width: 100%;
    max-width: 100vw;
    box-sizing: border-box;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    overflow: hidden;
    padding-left: max(10px, env(safe-area-inset-left));
    padding-right: max(10px, env(safe-area-inset-right));
  }

  .topbar .brand {
    flex: 0 1 112px;
    width: 112px;
    min-width: 82px !important;
    max-width: 112px;
    overflow: hidden;
  }

  .topbar .brand > span:not(.brand-mark) {
    display: none !important;
  }

  .topbar .brand-mark.logo-image {
    width: 100%;
    min-width: 0;
    max-width: 112px;
    overflow: hidden;
  }

  .topbar .brand-mark.logo-image img {
    display: block;
    width: 100%;
    max-width: 100%;
    height: auto;
    object-fit: contain;
  }

  .topbar .top-actions {
    flex: 1 1 auto;
    min-width: 0 !important;
    max-width: calc(100vw - 138px);
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 5px;
    overflow: hidden;
  }

  .topbar .top-actions > .sync-pill {
    display: none !important;
  }

  /* These actions already exist in the page content on mobile. */
  .topbar .top-actions .logout-button,
  .topbar .top-actions > .primary-button {
    display: none !important;
  }

  .topbar .top-actions .sync-button,
  .topbar .top-actions .notification-button,
  .topbar .top-actions .export-button,
  .topbar .top-actions .settings-button {
    flex: 0 0 38px !important;
    width: 38px !important;
    min-width: 38px !important;
    max-width: 38px !important;
    height: 38px !important;
    min-height: 38px !important;
    padding: 0 !important;
    border-radius: 10px;
    overflow: hidden;
  }

  .topbar .top-actions .sync-button-label {
    display: none !important;
  }

  .topbar .top-actions .export-button {
    font-size: 0 !important;
    white-space: nowrap;
  }

  .topbar .top-actions .export-button::after {
    content: "PDF";
    display: inline-block;
    font-size: 9px;
    font-weight: 900;
    line-height: 1;
    letter-spacing: .2px;
  }

  .topbar .top-actions .notification-button span,
  .topbar .top-actions .sync-button-icon {
    font-size: 18px;
    line-height: 1;
  }

  .topbar .top-actions .settings-button svg {
    width: 19px;
    height: 19px;
  }
}

@media (max-width: 390px) {
  .topbar {
    gap: 6px;
    padding-left: max(8px, env(safe-area-inset-left));
    padding-right: max(8px, env(safe-area-inset-right));
  }

  .topbar .brand {
    flex-basis: 90px;
    width: 90px;
    max-width: 90px;
  }

  .topbar .brand-mark.logo-image {
    max-width: 90px;
  }

  .topbar .top-actions {
    max-width: calc(100vw - 108px);
    gap: 4px;
  }

  .topbar .top-actions .sync-button,
  .topbar .top-actions .notification-button,
  .topbar .top-actions .export-button,
  .topbar .top-actions .settings-button {
    flex-basis: 35px !important;
    width: 35px !important;
    min-width: 35px !important;
    max-width: 35px !important;
    height: 35px !important;
    min-height: 35px !important;
  }

  .topbar .top-actions .export-button::after {
    font-size: 8px;
  }
}
/* END MECARDEE_MOBILE_TOPBAR_FIT_V1 */
'@

$existingPattern = '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/\s*'
$css = [System.Text.RegularExpressions.Regex]::Replace($css, $existingPattern, "`r`n")
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
    Write-Host "Mobile top bar fixed successfully." -ForegroundColor Green
    Write-Host "Only app\globals.css was changed." -ForegroundColor Green
    Write-Host "Backup: $backupPath" -ForegroundColor Yellow
}
catch {
    Copy-Item -LiteralPath $backupPath -Destination $cssPath -Force

    Write-Host ""
    Write-Host "Patch failed. The original CSS was restored automatically." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}
