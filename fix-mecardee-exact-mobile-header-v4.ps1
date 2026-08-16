Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "E:\mecardee-car-wash"
$pagePath = Join-Path $root "app\page.jsx"
$cssPath = Join-Path $root "app\globals.css"

if (-not (Test-Path -LiteralPath $pagePath)) {
    throw "File not found: $pagePath"
}

if (-not (Test-Path -LiteralPath $cssPath)) {
    throw "File not found: $cssPath"
}

$page = [System.IO.File]::ReadAllText($pagePath)

$requiredTopbarClasses = @(
    'className="sync-button"',
    'className="notification-button"',
    'className="export-button"',
    'className="settings-button"',
    'className="secondary-button logout-button"',
    'className="primary-button" type="button" onClick={openNewWork}'
)

foreach ($requiredClass in $requiredTopbarClasses) {
    if (-not $page.Contains($requiredClass)) {
        throw "Safety check failed. Current page.jsx does not contain: $requiredClass"
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $root "app\globals.css.before-exact-mobile-header-$stamp"

Copy-Item -LiteralPath $cssPath -Destination $backupPath -Force

$css = [System.IO.File]::ReadAllText($cssPath)

$patch = @'
/* MECARDEE_EXACT_MOBILE_HEADER_V4 */
@media (max-width: 620px) {
  /*
   * Exact current topbar order:
   * logo | Sync | Live | bell | Export PDF | settings | Log out | Add work
   *
   * Mobile keeps:
   * logo | Sync | bell | PDF | settings | Out
   *
   * Live and the duplicate topbar Add work button are hidden only on mobile.
   */
  .topbar {
    width: 100% !important;
    max-width: 100vw !important;
    height: 64px !important;
    box-sizing: border-box !important;
    display: grid !important;
    grid-template-columns: 88px minmax(0, 1fr) !important;
    align-items: center !important;
    justify-content: initial !important;
    gap: 8px !important;
    padding-left: max(10px, env(safe-area-inset-left)) !important;
    padding-right: max(10px, env(safe-area-inset-right)) !important;
    overflow: hidden !important;
  }

  .topbar .brand {
    width: 88px !important;
    min-width: 88px !important;
    max-width: 88px !important;
    gap: 0 !important;
    overflow: hidden !important;
  }

  .topbar .brand > span:last-child {
    display: none !important;
  }

  .topbar .brand-mark.logo-image {
    width: 88px !important;
    min-width: 88px !important;
    max-width: 88px !important;
    height: 42px !important;
    margin: 0 !important;
    overflow: hidden !important;
  }

  .topbar .brand-mark.logo-image img {
    width: 88px !important;
    max-width: 88px !important;
    height: 42px !important;
    object-fit: contain !important;
    object-position: left center !important;
  }

  .topbar .top-actions {
    width: 100% !important;
    min-width: 0 !important;
    max-width: none !important;
    display: grid !important;
    grid-template-columns: 36px 36px 56px 36px 50px !important;
    align-items: center !important;
    justify-content: end !important;
    gap: 4px !important;
    overflow: visible !important;
  }

  .topbar .sync-pill {
    display: none !important;
  }

  .topbar .top-actions > .primary-button {
    display: none !important;
  }

  .topbar .sync-button,
  .topbar .notification-button,
  .topbar .settings-button {
    display: grid !important;
    place-items: center !important;
    width: 36px !important;
    min-width: 36px !important;
    max-width: 36px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 !important;
    margin: 0 !important;
    border-radius: 9px !important;
    overflow: hidden !important;
    font-size: 0 !important;
    line-height: 1 !important;
  }

  .topbar .sync-button-label {
    display: none !important;
  }

  .topbar .sync-button-icon {
    display: block !important;
    font-size: 18px !important;
    line-height: 1 !important;
  }

  .topbar .notification-button > span:first-child::before {
    font-size: 18px !important;
  }

  .topbar .notification-button b {
    top: -2px !important;
    right: -2px !important;
    min-width: 15px !important;
    height: 15px !important;
    padding: 0 3px !important;
    font-size: 8px !important;
    border-width: 1px !important;
  }

  .topbar .settings-button svg {
    display: block !important;
    width: 18px !important;
    height: 18px !important;
  }

  .topbar .export-button {
    display: grid !important;
    place-items: center !important;
    width: 56px !important;
    min-width: 56px !important;
    max-width: 56px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 6px !important;
    margin: 0 !important;
    border-radius: 9px !important;
    overflow: hidden !important;
    white-space: nowrap !important;
    font-size: 0 !important;
    line-height: 1 !important;
  }

  .topbar .export-button::after {
    content: "PDF" !important;
    display: block !important;
    font-size: 10px !important;
    font-weight: 800 !important;
    line-height: 1 !important;
  }

  .topbar .logout-button {
    display: grid !important;
    place-items: center !important;
    width: 50px !important;
    min-width: 50px !important;
    max-width: 50px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 6px !important;
    margin: 0 !important;
    border-radius: 9px !important;
    overflow: hidden !important;
    white-space: nowrap !important;
    font-size: 0 !important;
    line-height: 1 !important;
  }

  .topbar .logout-button::after {
    content: "Out" !important;
    display: block !important;
    font-size: 10px !important;
    font-weight: 800 !important;
    line-height: 1 !important;
  }
}

@media (max-width: 360px) {
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
    min-width: 72px !important;
    max-width: 72px !important;
  }

  .topbar .top-actions {
    grid-template-columns: 34px 34px 50px 34px 44px !important;
    gap: 3px !important;
  }

  .topbar .sync-button,
  .topbar .notification-button,
  .topbar .settings-button {
    width: 34px !important;
    min-width: 34px !important;
    max-width: 34px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
  }

  .topbar .export-button {
    width: 50px !important;
    min-width: 50px !important;
    max-width: 50px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
  }

  .topbar .logout-button {
    width: 44px !important;
    min-width: 44px !important;
    max-width: 44px !important;
    height: 34px !important;
    min-height: 34px !important;
    max-height: 34px !important;
  }

  .topbar .export-button::after,
  .topbar .logout-button::after {
    font-size: 9px !important;
  }
}
/* END MECARDEE_EXACT_MOBILE_HEADER_V4 */
'@

# Remove only mobile-header experiments previously supplied in this chat.
$oldPatchPatterns = @(
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/\s*',
    '(?s)\s*/\* MECARDEE_EXACT_MOBILE_HEADER_V4 \*/.*?/\* END MECARDEE_EXACT_MOBILE_HEADER_V4 \*/\s*'
)

foreach ($pattern in $oldPatchPatterns) {
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
    Write-Host "Exact mobile header fix applied." -ForegroundColor Green
    Write-Host ""
    Write-Host "Mobile header:" -ForegroundColor Green
    Write-Host "  Logo | Sync | Notification | PDF | Settings | Out"
    Write-Host ""
    Write-Host "Hidden only on mobile:" -ForegroundColor Green
    Write-Host "  Live status"
    Write-Host "  Duplicate topbar Add work button"
    Write-Host ""
    Write-Host "Desktop header is unchanged." -ForegroundColor Green
    Write-Host "Only app\globals.css was changed." -ForegroundColor Green
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
