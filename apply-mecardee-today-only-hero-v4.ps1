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
$backupRoot = Join-Path $root "backup-before-today-only-hero-$stamp"
$backupApp = Join-Path $backupRoot "app"

New-Item -ItemType Directory -Path $backupApp -Force | Out-Null
Copy-Item -LiteralPath $pagePath -Destination (Join-Path $backupApp "page.jsx") -Force
Copy-Item -LiteralPath $cssPath -Destination (Join-Path $backupApp "globals.css") -Force

Write-Host "Backup created:" -ForegroundColor Cyan
Write-Host $backupRoot -ForegroundColor Yellow

$page = [System.IO.File]::ReadAllText($pagePath)
$css = [System.IO.File]::ReadAllText($cssPath)

$newHero = @'
      <section className="hero category-hero today-only-hero" id="top">
        <article className="hero-today-card today-only-card" aria-label="Today's work">
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
            <select
              value={activeCategory}
              onChange={(event) => setActiveCategory(event.target.value)}
              aria-label="Filter today's works by category"
            >
              <option value="all">All categories</option>
              {activeCategories.map((category) => (
                <option value={category.id} key={category.id}>{category.name}</option>
              ))}
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

$heroPattern = '\s*<section className="hero category-hero[^"]*" id="top">.*?</section>\s*(?=<section className="summary-grid")'
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
/* MECARDEE_TODAY_ONLY_HERO_V4 */
.today-only-hero {
  display: block !important;
  min-height: auto !important;
  padding: clamp(28px, 4vw, 52px) clamp(18px, 5vw, 72px) clamp(34px, 5vw, 64px) !important;
  text-align: left !important;
}

.today-only-hero .today-only-card {
  position: relative;
  z-index: 1;
  width: min(100%, 1180px);
  min-width: 0;
  min-height: 360px;
  max-height: none;
  margin: 0 auto;
  padding: clamp(18px, 2.3vw, 28px);
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr);
  gap: 16px;
  overflow: hidden;
  border: 1px solid rgba(255,255,255,.22);
  border-radius: 24px;
  background: rgba(250,252,249,.985);
  color: var(--ink);
  box-shadow: 0 26px 70px rgba(0,0,0,.22);
}

.today-only-hero .hero-today-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 22px;
}

.today-only-hero .hero-today-heading h2 {
  margin: 6px 0 3px;
  font-family: "Manrope", sans-serif;
  font-size: clamp(28px, 3vw, 42px);
  line-height: 1;
  letter-spacing: -1.7px;
}

.today-only-hero .hero-today-heading p {
  margin: 0;
  color: var(--muted);
  font-size: 12px;
}

.today-only-hero .hero-opening-summary {
  flex: 0 0 auto;
  min-width: 220px;
  display: grid;
  justify-items: end;
  gap: 3px;
  padding: 11px 14px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: white;
  text-align: right;
}

.today-only-hero .hero-opening-summary span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 800;
  letter-spacing: 1.1px;
  text-transform: uppercase;
}

.today-only-hero .hero-opening-summary strong {
  font-size: 14px;
  line-height: 1.25;
}

.today-only-hero .hero-opening-summary small {
  color: var(--muted);
  font-size: 9px;
  line-height: 1.3;
}

.today-only-hero .hero-work-filter {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: white;
}

.today-only-hero .hero-work-filter select {
  min-width: 0;
  flex: 1;
  border: 0;
  outline: 0;
  padding: 10px 11px;
  border-radius: 10px;
  background: var(--paper);
  color: var(--ink);
  font: inherit;
  font-size: 13px;
}

.today-only-hero .hero-work-filter span {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 10px;
  white-space: nowrap;
}

.today-only-hero .hero-today-list {
  min-height: 0;
  max-height: 470px;
  overflow-y: auto;
  padding-right: 4px;
  scrollbar-width: thin;
}

.today-only-hero .hero-today-list .compact-work-empty {
  min-height: 220px;
  display: grid;
  place-content: center;
  padding: 22px;
  border-radius: 16px;
  background: white;
}

.today-only-hero .hero-today-list .compact-work-empty > span {
  width: 44px;
  height: 44px;
  font-size: 21px;
}

.today-only-hero .hero-today-list .compact-work-empty h3 {
  margin: 11px 0 5px;
  font-size: 17px;
}

.today-only-hero .hero-today-list .compact-work-empty p {
  margin: 0;
  font-size: 11px;
}

.today-only-hero .hero-today-list .work-card {
  border-radius: 14px;
}

@media (max-width: 700px) {
  .today-only-hero {
    padding: 18px 14px 30px !important;
  }

  .today-only-hero .today-only-card {
    min-height: 0;
    padding: 16px;
    gap: 13px;
    border-radius: 20px;
  }

  .today-only-hero .hero-today-heading {
    flex-direction: column;
    gap: 11px;
  }

  .today-only-hero .hero-today-heading h2 {
    font-size: 30px;
  }

  .today-only-hero .hero-opening-summary {
    width: 100%;
    min-width: 0;
    justify-items: start;
    text-align: left;
  }

  .today-only-hero .hero-work-filter {
    align-items: stretch;
    flex-direction: column;
    gap: 7px;
  }

  .today-only-hero .hero-work-filter span {
    padding: 0 5px 2px;
  }

  .today-only-hero .hero-today-list {
    max-height: none;
  }

  .today-only-hero .hero-today-list .compact-work-empty {
    min-height: 210px;
  }
}

@media (max-width: 390px) {
  .today-only-hero {
    padding-left: 10px !important;
    padding-right: 10px !important;
  }

  .today-only-hero .today-only-card {
    padding: 14px;
    border-radius: 17px;
  }

  .today-only-hero .hero-today-heading h2 {
    font-size: 27px;
  }
}
/* END MECARDEE_TODAY_ONLY_HERO_V4 */
'@

$oldCssPatterns = @(
    '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V1 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V2 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V2 \*/\s*',
    '(?s)\s*/\* MECARDEE_COMPACT_HERO_UI_V3 \*/.*?/\* END MECARDEE_COMPACT_HERO_UI_V3 \*/\s*',
    '(?s)\s*/\* MECARDEE_TODAY_ONLY_HERO_V4 \*/.*?/\* END MECARDEE_TODAY_ONLY_HERO_V4 \*/\s*'
)

foreach ($pattern in $oldCssPatterns) {
    $css = [System.Text.RegularExpressions.Regex]::Replace($css, $pattern, "`r`n")
}

$css = $css.TrimEnd() + "`r`n`r`n" + $cssPatch.Trim() + "`r`n"

$forbiddenHeroText = @(
    "Every rupee",
    "Mecardee Autocraft",
    "Work, budget and finance dashboard.",
    "hero-completion-tile",
    "compact-hero-actions"
)

foreach ($forbidden in $forbiddenHeroText) {
    if ($page.Contains($forbidden)) {
        throw "Safety check failed: unwanted hero content is still present: $forbidden"
    }
}

if (-not $page.Contains('className="hero category-hero today-only-hero"')) {
    throw "Safety check failed: the Today-only hero was not inserted."
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
    Write-Host "Today-only hero applied successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Removed from the hero:" -ForegroundColor Green
    Write-Host "  - Location and category labels"
    Write-Host "  - Mecardee Autocraft heading"
    Write-Host "  - Subtitle"
    Write-Host "  - Hero action buttons"
    Write-Host "  - Extra completion circle"
    Write-Host ""
    Write-Host "The page now starts directly with the premium Today's work card." -ForegroundColor Green
    Write-Host ""
    Write-Host "Only these source files were changed:" -ForegroundColor Green
    Write-Host "  app\page.jsx"
    Write-Host "  app\globals.css"
    Write-Host ""
    Write-Host "Database, Supabase queries, APIs, forms and save actions were not modified." -ForegroundColor Green
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
