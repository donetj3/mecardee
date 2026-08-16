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

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $root "backup-before-final-mobile-header-$stamp"
$backupApp = Join-Path $backupRoot "app"

New-Item -ItemType Directory -Path $backupApp -Force | Out-Null
Copy-Item -LiteralPath $pagePath -Destination (Join-Path $backupApp "page.jsx") -Force
Copy-Item -LiteralPath $cssPath -Destination (Join-Path $backupApp "globals.css") -Force

$page = [System.IO.File]::ReadAllText($pagePath)
$css = [System.IO.File]::ReadAllText($cssPath)

# Give only the topbar Add Work button a unique class.
$plainAddButton = '<button className="primary-button" type="button" onClick={openNewWork}>+ Add work</button>'
$taggedAddButton = '<button className="primary-button topbar-add-work-button" type="button" onClick={openNewWork}>+ Add work</button>'

if ($page.Contains($plainAddButton)) {
    $page = $page.Replace($plainAddButton, $taggedAddButton)
}
elseif (-not $page.Contains($taggedAddButton)) {
    throw "Could not find the topbar Add work button in app\page.jsx. No files were changed."
}

# Remove all previous experimental mobile-header patches from this chat.
$oldPatchPatterns = @(
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_FIT_V2 \*/\s*',
    '(?s)\s*/\* MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/.*?/\* END MECARDEE_MOBILE_TOPBAR_CLEAN_V3 \*/\s*',
    '(?s)\s*/\* MECARDEE_EXACT_MOBILE_HEADER_V4 \*/.*?/\* END MECARDEE_EXACT_MOBILE_HEADER_V4 \*/\s*',
    '(?s)\s*/\* MECARDEE_FINAL_MOBILE_HEADER_V5 \*/.*?/\* END MECARDEE_FINAL_MOBILE_HEADER_V5 \*/\s*'
)

foreach ($pattern in $oldPatchPatterns) {
    $css = [System.Text.RegularExpressions.Regex]::Replace($css, $pattern, "`r`n")
}

$cssPatch = @'
/* MECARDEE_FINAL_MOBILE_HEADER_V5 */
@media (max-width: 620px) {
  /*
   * Mobile header:
   * logo | sync | notification | PDF | settings | logout
   *
   * LIVE and the duplicate topbar Add Work button are hidden.
   */
  .app-shell .topbar {
    width: 100% !important;
    max-width: 100vw !important;
    height: 64px !important;
    box-sizing: border-box !important;
    display: grid !important;
    grid-template-columns: 78px minmax(0, 1fr) !important;
    align-items: center !important;
    justify-content: stretch !important;
    column-gap: 7px !important;
    padding: 0 max(8px, env(safe-area-inset-right)) 0 max(8px, env(safe-area-inset-left)) !important;
    overflow: hidden !important;
  }

  .app-shell .topbar .brand {
    width: 78px !important;
    min-width: 78px !important;
    max-width: 78px !important;
    height: 42px !important;
    gap: 0 !important;
    overflow: hidden !important;
  }

  .app-shell .topbar .brand > span:last-child {
    display: none !important;
  }

  .app-shell .topbar .brand-mark.logo-image,
  .app-shell .topbar .brand-mark.logo-image img {
    display: block !important;
    width: 78px !important;
    min-width: 78px !important;
    max-width: 78px !important;
    height: 42px !important;
    margin: 0 !important;
    object-fit: contain !important;
    object-position: left center !important;
  }

  .app-shell .topbar .top-actions {
    width: 100% !important;
    min-width: 0 !important;
    max-width: none !important;
    height: 40px !important;
    display: grid !important;
    grid-template-columns: 36px 36px 52px 36px 48px !important;
    align-items: center !important;
    justify-content: end !important;
    gap: 4px !important;
    flex-wrap: nowrap !important;
    overflow: hidden !important;
  }

  .app-shell .topbar .top-actions > span.sync-pill {
    display: none !important;
  }

  .app-shell .topbar .top-actions > button.primary-button.topbar-add-work-button {
    display: none !important;
    width: 0 !important;
    min-width: 0 !important;
    height: 0 !important;
    min-height: 0 !important;
    padding: 0 !important;
    margin: 0 !important;
    overflow: hidden !important;
  }

  .app-shell .topbar .top-actions > button.sync-button {
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
    font-size: 0 !important;
    overflow: hidden !important;
  }

  .app-shell .topbar .top-actions > button.sync-button .sync-button-label {
    display: none !important;
  }

  .app-shell .topbar .top-actions > button.sync-button .sync-button-icon {
    display: block !important;
    font-size: 18px !important;
    line-height: 1 !important;
  }

  .app-shell .topbar .top-actions > button.notification-button {
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
    overflow: visible !important;
  }

  .app-shell .topbar .top-actions > button.notification-button > span:first-child::before {
    font-size: 18px !important;
  }

  .app-shell .topbar .top-actions > button.notification-button b {
    top: -3px !important;
    right: -3px !important;
    min-width: 15px !important;
    height: 15px !important;
    padding: 0 3px !important;
    font-size: 8px !important;
    border-width: 1px !important;
  }

  .app-shell .topbar .top-actions > button.export-button {
    display: grid !important;
    place-items: center !important;
    width: 52px !important;
    min-width: 52px !important;
    max-width: 52px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 !important;
    margin: 0 !important;
    border-radius: 9px !important;
    font-size: 0 !important;
    line-height: 1 !important;
    overflow: hidden !important;
    white-space: nowrap !important;
  }

  .app-shell .topbar .top-actions > button.export-button::after {
    content: "PDF" !important;
    display: block !important;
    font-size: 9px !important;
    font-weight: 800 !important;
    line-height: 1 !important;
  }

  .app-shell .topbar .top-actions > button.settings-button {
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
  }

  .app-shell .topbar .top-actions > button.settings-button svg {
    width: 18px !important;
    height: 18px !important;
  }

  .app-shell .topbar .top-actions > button.secondary-button.logout-button {
    display: grid !important;
    place-items: center !important;
    width: 48px !important;
    min-width: 48px !important;
    max-width: 48px !important;
    height: 36px !important;
    min-height: 36px !important;
    max-height: 36px !important;
    padding: 0 !important;
    margin: 0 !important;
    border-radius: 9px !important;
    font-size: 0 !important;
    line-height: 1 !important;
    overflow: hidden !important;
    white-space: nowrap !important;
  }

  .app-shell .topbar .top-actions > button.secondary-button.logout-button::after {
    content: "Out" !important;
    display: block !important;
    font-size: 9px !important;
    font-weight: 800 !important;
    line-height: 1 !important;
  }
}

@media (max-width: 360px) {
  .app-shell .topbar {
    grid-template-columns: 66px minmax(0, 1fr) !important;
    column-gap: 5px !important;
    padding-left: max(5px, env(safe-area-inset-left)) !important;
    padding-right: max(5px, env(safe-area-inset-right)) !important;
  }

  .app-shell .topbar .brand,
  .app-shell .topbar .brand-mark.logo-image,
  .app-shell .topbar .brand-mark.logo-image img {
    width: 66px !important;
    min-width: 66px !important;
    max-width: 66px !important;
  }

  .app-shell .topbar .top-actions {
    grid-template-columns: 33px 33px 45px 33px 42px !important;
    gap: 3px !important;
  }

  .app-shell .topbar .top-actions > button.sync-button,
  .app-shell .topbar .top-actions > button.notification-button,
  .app-shell .topbar .top-actions > button.settings-button {
    width: 33px !important;
    min-width: 33px !important;
    max-width: 33px !important;
    height: 33px !important;
    min-height: 33px !important;
    max-height: 33px !important;
  }

  .app-shell .topbar .top-actions > button.export-button {
    width: 45px !important;
    min-width: 45px !important;
    max-width: 45px !important;
    height: 33px !important;
    min-height: 33px !important;
    max-height: 33px !important;
  }

  .app-shell .topbar .top-actions > button.secondary-button.logout-button {
    width: 42px !important;
    min-width: 42px !important;
    max-width: 42px !important;
    height: 33px !important;
    min-height: 33px !important;
    max-height: 33px !important;
  }
}
/* END MECARDEE_FINAL_MOBILE_HEADER_V5 */
'@

$css = $css.TrimEnd() + "`r`n`r`n" + $cssPatch.Trim() + "`r`n"

if (-not $page.Contains('className="primary-button topbar-add-work-button"')) {
    throw "Safety check failed: the topbar Add work button was not uniquely tagged."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$locationPushed = $false

try {
    [System.IO.File]::WriteAllText($pagePath, $page, $utf8NoBom)
    [System.IO.File]::WriteAllText($cssPath, $css, $utf8NoBom)

    Push-Location $root
    $locationPushed = $true

    Write-Host "Running production build..." -ForegroundColor Cyan
    & npm.cmd run build

    if ($LASTEXITCODE -ne 0) {
        throw "Next.js build failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Final mobile header fix applied successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Mobile header now shows:" -ForegroundColor Green
    Write-Host "  Logo | Sync | Notification | PDF | Settings | Out"
    Write-Host ""
    Write-Host "Hidden only in the mobile topbar:" -ForegroundColor Green
    Write-Host "  LIVE"
    Write-Host "  Duplicate Add work"
    Write-Host ""
    Write-Host "Files changed:" -ForegroundColor Green
    Write-Host "  app\page.jsx  (one unique class added)"
    Write-Host "  app\globals.css"
    Write-Host ""
    Write-Host "Backup: $backupRoot" -ForegroundColor Yellow
}
catch {
    Copy-Item -LiteralPath (Join-Path $backupApp "page.jsx") -Destination $pagePath -Force
    Copy-Item -LiteralPath (Join-Path $backupApp "globals.css") -Destination $cssPath -Force

    Write-Host ""
    Write-Host "Patch failed. Both files were restored automatically." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
}
