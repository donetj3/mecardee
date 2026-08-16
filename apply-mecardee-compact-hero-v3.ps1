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
$backupRoot = Join-Path $root "backup-before-compact-hero-v3-$stamp"
$backupApp = Join-Path $backupRoot "app"

New-Item -ItemType Directory -Path $backupApp -Force | Out-Null
Copy-Item -LiteralPath $pagePath -Destination (Join-Path $backupApp "page.jsx") -Force
Copy-Item -LiteralPath $cssPath -Destination (Join-Path $backupApp "globals.css") -Force

Write-Host "Backup created:" -ForegroundColor Cyan
Write-Host $backupRoot -ForegroundColor Yellow

$page = [System.IO.File]::ReadAllText($pagePath)
$css = [System.IO.File]::ReadAllText($cssPath)

$newHero = @'
      <section className="hero category-hero compact-dashboard-hero" id="top">
        <div className="hero-copy compact-hero-copy">
          <span className="location-pill">{data.project.location}</span>
          <p className="eyebrow light">CATEGORY & FINANCE CONTROL</p>
          <h1>Mecardee Autocraft</h1>
          <p className="hero-subtitle">Work, budget and finance dashboard.</p>

          <div className="hero-actions compact-hero-actions">
            {isAdmin && <button className="light-button" type="button" onClick={openNewWork}>Add today's work</button>}
            {isAdmin && <button className="credit-action-button" type="button" onClick={openNewCredit}>Add credit</button>}
            <button className="ghost-button" type="button" onClick={() => document.getElementById("transactions")?.scrollIntoView({ behavior: "smooth" })}>
              View transaction register
            </button>
          </div>

          {!isAdmin && <div className="view-only-banner">View-only account - You can filter reports and change your password.</div>}
        </div>

        <article className="hero-today-card hero-today-card-large" aria-label="Today's work">
          <div className="hero-today-heading">
            <div>
              <span className="eyebrow">Daily work register</span>
              <h2>Today's work</h2>
              <p>{formatDate(toDateInput())}</p>
            </div>

            <div className="hero-opening-summary">
              <span>Target opening</span>
              <strong>{formatDate(data.project.openingDate, { day: "numeric", month: "long", year: "numeric" })}</strong>
              <small>{openingDays} days remaining - {activeCategories.length} categories</small>
            </div>
          </div>

          <div className="hero-work-filter">
            <select value={activeCategory} onChange={(event) => setActiveCategory(event.target.value)} aria-label="Filter today's works by category">
              <option value="all">All categories</option>
              {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
            </select>
            <span>{todayWorks.length} today | {openWorks.length} open</span>
          </div>

          <div className="hero-today-list">
            {renderWorkList(
              todayWorks,
              "No work added for today",
              isAdmin ? "Use Add work to record today's site activity." : "No site activity is dated today."
            )}
          </div>
        </article>
      </section>
'@

$heroPattern = '\s*<section className="hero category-hero(?: compact-dashboard-hero)?" id="top">.*?</section>\s*(?=<section className="summary-grid")'
$heroRegex = [System.Text.RegularExpressions.Regex]::new(
    $heroPattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$heroMatches = $heroRegex.Matches($page).Count

if ($heroMatches -ne 1) {
    throw "Safety check failed: expected exactly one dashboard hero section, found $heroMatches. No files were changed."
}

$page = $heroRegex.Replace($page, "`r`n$newHero`r`n`r`n", 1)

$cssPatch = @'
/* MECARDEE_COMPACT_HERO_UI_V3 */
.compact-dashboard-hero {
  grid-template-columns: minmax(250px, .52fr) minmax(520px, 1.48fr);
  grid-template-areas: "copy today";
  gap: clamp(24px, 4vw, 58px);
  min-height: 480px;
  align-items: center;
}

.compact-dashboard-hero .compact-hero-copy {
  grid-area: copy;
  min-width: 0;
  max-width: 390px;
  align-self: center;
}

.compact-dashboard-hero .compact-hero-copy h1 {
  max-width: 360px;
  margin: 14px 0 10px;
  font-size: clamp(34px, 4.1vw, 58px);
  line-height: .98;
  letter-spacing: -2.3px;
}

.compact-dashboard-hero .compact-hero-copy .hero-subtitle {
  max-width: 330px;
  margin: 0;
  font-size: 14px;
  line-height: 1.55;
}

.compact-hero-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: 22px;
}

.compact-hero-actions .ghost-button {
  grid-column: 1 / -1;
}

.compact-dashboard-hero .hero-today-card {
  grid-area: today;
  width: 100%;
  min-width: 0;
  min-height: 410px;
  max-height: 440px;
  align-self: center;
}

@media (max-width: 980px) {
  .compact-dashboard-hero {
    grid-template-columns: minmax(0, 1fr);
    grid-template-areas:
      "copy"
      "today";
    gap: 26px;
    min-height: auto;
    align-items: start;
  }

  .compact-dashboard-hero .compact-hero-copy {
    max-width: 720px;
  }

  .compact-dashboard-hero .compact-hero-copy h1 {
    max-width: none;
    font-size: clamp(36px, 7vw, 58px);
  }

  .compact-dashboard-hero .compact-hero-copy .hero-subtitle {
    max-width: none;
  }

  .compact-dashboard-hero .hero-today-card {
    min-height: 400px;
    max-height: 460px;
  }
}

@media (max-width: 560px) {
  .compact-dashboard-hero {
    gap: 20px;
    padding-top: 28px;
  }

  .compact-dashboard-hero .compact-hero-copy h1 {
    margin: 12px 0 8px;
    font-size: 40px;
    line-height: 1;
    letter-spacing: -1.7px;
  }

  .compact-dashboard-hero .compact-hero-copy .hero-subtitle {
    font-size: 13px;
  }

  .compact-hero-actions {
    grid-template-columns: 1fr 1fr;
    gap: 9px;
    margin-top: 18px;
  }

  .compact-hero-actions button {
    min-width: 0;
    padding-left: 10px;
    padding-right: 10px;
    font-size: 12px;
  }

  .compact-hero-actions .ghost-button {
    grid-column: 1 / -1;
  }

  .compact-dashboard-hero .hero-today-card {
    min-height: 430px;
    max-height: 520px;
  }
}

@media (max-width: 390px) {
  .compact-hero-actions {
    grid-template-columns: 1fr;
  }

  .compact-hero-actions .ghost-button {
    grid-column: auto;
  }
}
/* END MECARDEE_COMPACT_HERO_UI_V3 */
'@

$oldCssPatterns = @(
    '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V1 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V2 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V2 \*/\s*',
    '(?s)\s*/\* MECARDEE_COMPACT_HERO_UI_V3 \*/.*?/\* END MECARDEE_COMPACT_HERO_UI_V3 \*/\s*'
)

foreach ($pattern in $oldCssPatterns) {
    $css = [System.Text.RegularExpressions.Regex]::Replace($css, $pattern, "`r`n")
}

$css = $css.TrimEnd() + "`r`n`r`n" + $cssPatch.Trim() + "`r`n"

if ($page -match 'hero-completion-tile') {
    throw "Safety check failed: the extra hero completion block is still present."
}

if ($page -match 'Every rupee') {
    throw "Safety check failed: the old large hero sentence is still present."
}

if ($page -notmatch 'Mecardee Autocraft') {
    throw "Safety check failed: the compact heading was not inserted."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$locationPushed = $false

try {
    [System.IO.File]::WriteAllText($pagePath, $page, $utf8NoBom)
    [System.IO.File]::WriteAllText($cssPath, $css, $utf8NoBom)

    Push-Location $root
    $locationPushed = $true

    Write-Host ""
    Write-Host "Running production build..." -ForegroundColor Cyan
    & npm.cmd run build

    if ($LASTEXITCODE -ne 0) {
        throw "Next.js build failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Compact hero V3 applied successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Changes:" -ForegroundColor Green
    Write-Host "  - Removed the large 'Every rupee...' heading"
    Write-Host "  - Added the compact 'Mecardee Autocraft' heading"
    Write-Host "  - Removed the extra 51 percent completion block from the hero"
    Write-Host "  - Kept the existing lower completion circle unchanged"
    Write-Host "  - Improved Android and iPhone mobile layout"
    Write-Host ""
    Write-Host "Only these source files were changed:" -ForegroundColor Green
    Write-Host "  app\page.jsx"
    Write-Host "  app\globals.css"
    Write-Host ""
    Write-Host "Database, Supabase queries, API routes, forms and save functions were not modified." -ForegroundColor Green
    Write-Host ""
    Write-Host "Backup location:" -ForegroundColor Cyan
    Write-Host $backupRoot -ForegroundColor Yellow
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
    if ($locationPushed) {
        Pop-Location
    }
}
