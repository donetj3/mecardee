Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "E:\mecardee-car-wash"
$pagePath = Join-Path $root "app\page.jsx"
$cssPath = Join-Path $root "app\globals.css"

if (-not (Test-Path -LiteralPath $pagePath)) { throw "File not found: $pagePath" }
if (-not (Test-Path -LiteralPath $cssPath)) { throw "File not found: $cssPath" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $root "backup-before-restore-hero-buttons-$stamp"
$backupApp = Join-Path $backupRoot "app"

New-Item -ItemType Directory -Path $backupApp -Force | Out-Null
Copy-Item -LiteralPath $pagePath -Destination (Join-Path $backupApp "page.jsx") -Force
Copy-Item -LiteralPath $cssPath -Destination (Join-Path $backupApp "globals.css") -Force

$page = [System.IO.File]::ReadAllText($pagePath)
$css = [System.IO.File]::ReadAllText($cssPath)

$buttons = @'
        <div className="today-only-actions">
          {isAdmin && <button className="light-button" type="button" onClick={openNewWork}>Add today's work</button>}
          {isAdmin && <button className="credit-action-button" type="button" onClick={openNewCredit}>Add credit</button>}
          <button
            className="ghost-button"
            type="button"
            onClick={() => document.getElementById("transactions")?.scrollIntoView({ behavior: "smooth" })}
          >
            View transaction register
          </button>
        </div>

'@

# Remove any previous copy of this exact action block so the patch is safe to run again.
$page = [System.Text.RegularExpressions.Regex]::Replace(
    $page,
    '(?s)\s*<div className="today-only-actions">.*?</div>\s*',
    "`r`n"
)

$target = '<section className="hero category-hero today-only-hero" id="top">'
if (-not $page.Contains($target)) {
    throw "Could not find the Today-only hero section. No files were changed."
}

$page = $page.Replace(
    $target,
    $target + "`r`n" + $buttons
)

$cssPatch = @'
/* MECARDEE_RESTORE_HERO_BUTTONS_V5 */
.today-only-actions {
  position: relative;
  z-index: 2;
  width: min(100%, 1180px);
  margin: 0 auto 18px;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 12px;
}

.today-only-actions .light-button,
.today-only-actions .credit-action-button,
.today-only-actions .ghost-button {
  min-width: 0;
  min-height: 58px;
  font-size: 15px;
  font-weight: 800;
  border-radius: 16px;
}

.today-only-actions .ghost-button {
  grid-column: 1 / -1;
  width: 100%;
}

@media (max-width: 700px) {
  .today-only-actions {
    margin-bottom: 14px;
    gap: 10px;
  }

  .today-only-actions .light-button,
  .today-only-actions .credit-action-button {
    min-height: 60px;
    padding: 12px 10px;
    font-size: 14px;
    line-height: 1.2;
  }

  .today-only-actions .ghost-button {
    min-height: 54px;
    font-size: 13px;
  }
}

@media (max-width: 380px) {
  .today-only-actions {
    grid-template-columns: 1fr;
  }

  .today-only-actions .ghost-button {
    grid-column: auto;
  }
}
/* END MECARDEE_RESTORE_HERO_BUTTONS_V5 */
'@

$css = [System.Text.RegularExpressions.Regex]::Replace(
    $css,
    '(?s)\s*/\* MECARDEE_RESTORE_HERO_BUTTONS_V5 \*/.*?/\* END MECARDEE_RESTORE_HERO_BUTTONS_V5 \*/\s*',
    "`r`n"
)

$css = $css.TrimEnd() + "`r`n`r`n" + $cssPatch.Trim() + "`r`n"

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
    Write-Host "Buttons restored successfully." -ForegroundColor Green
    Write-Host "The page still starts without a heading." -ForegroundColor Green
    Write-Host "Today's Work remains directly below the three buttons." -ForegroundColor Green
    Write-Host ""
    Write-Host "Backup: $backupRoot" -ForegroundColor Yellow
}
catch {
    Copy-Item -LiteralPath (Join-Path $backupApp "page.jsx") -Destination $pagePath -Force
    Copy-Item -LiteralPath (Join-Path $backupApp "globals.css") -Destination $cssPath -Force

    Write-Host ""
    Write-Host "Patch failed. Original files were restored automatically." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
finally {
    if ($locationPushed) { Pop-Location }
}
