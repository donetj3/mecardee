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
$backupRoot = Join-Path $root "backup-before-hero-layout-v2-$stamp"
$backupApp = Join-Path $backupRoot "app"

New-Item -ItemType Directory -Path $backupApp -Force | Out-Null
Copy-Item -LiteralPath $pagePath -Destination (Join-Path $backupApp "page.jsx") -Force
Copy-Item -LiteralPath $cssPath -Destination (Join-Path $backupApp "globals.css") -Force

Write-Host "Backup created:" -ForegroundColor Cyan
Write-Host $backupRoot -ForegroundColor Yellow

$page = [System.IO.File]::ReadAllText($pagePath)
$css = [System.IO.File]::ReadAllText($cssPath)

$newHero = @'
      <section className="hero category-hero" id="top">
        <div className="hero-copy">
          <span className="location-pill">{data.project.location}</span>
          <p className="eyebrow light">CATEGORY & FINANCE CONTROL</p>
          <h1>Every rupee and<br />every work item.</h1>
          <p className="hero-subtitle">
            Track category budgets, shareholder contributions, daily work and the complete financial register in one shared dashboard.
          </p>
          <div className="hero-actions">
            {isAdmin && <button className="light-button" type="button" onClick={openNewWork}>Add today's work</button>}
            {isAdmin && <button className="credit-action-button" type="button" onClick={openNewCredit}>Add credit</button>}
            <button className="ghost-button" type="button" onClick={() => document.getElementById("transactions")?.scrollIntoView({ behavior: "smooth" })}>
              View transaction register
            </button>
          </div>
          {!isAdmin && <div className="view-only-banner">View-only account - You can filter reports and change your password.</div>}
        </div>

        <aside className="hero-completion-tile" aria-label="Project completion">
          <CompletionDonut value={overallCategoryCompletion} size={126} />
        </aside>

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

$heroPattern = '\s*<section className="hero category-hero" id="top">.*?</section>\s*(?=<section className="summary-grid")'
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
/* MECARDEE_HERO_TODAY_WORK_UI_V2 */
.category-hero {
  grid-template-columns: minmax(340px, .82fr) 150px minmax(480px, 1.15fr);
  grid-template-areas: "copy completion today";
  gap: clamp(18px, 2.2vw, 32px);
  min-height: 520px;
  align-items: center;
}

.category-hero .hero-copy {
  grid-area: copy;
  min-width: 0;
  align-self: center;
}

.hero-completion-tile {
  grid-area: completion;
  position: relative;
  z-index: 1;
  width: 150px;
  height: 150px;
  min-width: 0;
  display: grid;
  place-items: center;
  align-self: start;
  justify-self: center;
  margin-top: 18px;
}

.hero-completion-tile .category-donut::before {
  inset: 11px;
}

.hero-completion-tile .category-donut > div {
  padding: 13px;
}

.hero-completion-tile .category-donut strong {
  font-size: 29px;
  letter-spacing: -1.2px;
}

.hero-completion-tile .category-donut span {
  max-width: 82px;
  font-size: 7px;
  line-height: 1.25;
  letter-spacing: .9px;
}

.hero-today-card {
  grid-area: today;
  position: relative;
  z-index: 1;
  min-width: 0;
  width: 100%;
  min-height: 410px;
  max-height: 430px;
  overflow: hidden;
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr);
  gap: 14px;
  padding: 20px;
  border: 1px solid rgba(255,255,255,.2);
  border-radius: 22px;
  background: rgba(250,252,249,.98);
  color: var(--ink);
  box-shadow: 0 24px 60px rgba(0,0,0,.22);
  text-align: left;
  align-self: stretch;
}

.hero-today-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
}

.hero-today-heading h2 {
  margin: 5px 0 3px;
  font-family: "Manrope", sans-serif;
  font-size: clamp(25px, 2vw, 32px);
  line-height: 1.05;
  letter-spacing: -1.2px;
}

.hero-today-heading p {
  margin: 0;
  color: var(--muted);
  font-size: 12px;
}

.hero-opening-summary {
  flex: 0 0 auto;
  min-width: 170px;
  display: grid;
  justify-items: end;
  gap: 3px;
  padding: 10px 12px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: white;
  text-align: right;
}

.hero-opening-summary span {
  color: var(--muted);
  font-size: 8px;
  font-weight: 800;
  letter-spacing: 1.1px;
  text-transform: uppercase;
}

.hero-opening-summary strong {
  font-size: 13px;
  line-height: 1.25;
}

.hero-opening-summary small {
  color: var(--muted);
  font-size: 9px;
  line-height: 1.3;
}

.hero-work-filter {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 9px;
  border: 1px solid var(--line);
  border-radius: 13px;
  background: white;
}

.hero-work-filter select {
  min-width: 0;
  flex: 1;
  border: 0;
  outline: 0;
  padding: 9px 10px;
  border-radius: 9px;
  background: var(--paper);
  color: var(--ink);
  font-size: 12px;
}

.hero-work-filter span {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 10px;
  white-space: nowrap;
}

.hero-today-list {
  min-height: 0;
  overflow-y: auto;
  padding-right: 4px;
  scrollbar-width: thin;
}

.hero-today-list .work-card {
  grid-template-columns: 8px minmax(0, 1fr);
  gap: 10px;
  align-items: start;
  padding: 12px;
  border-radius: 13px;
}

.hero-today-list .work-card .status-dot {
  width: 8px;
  height: 8px;
  margin-top: 6px;
}

.hero-today-list .work-card-copy h3 {
  margin: 5px 0 0;
  font-size: 14px;
  letter-spacing: -.2px;
}

.hero-today-list .task-meta {
  gap: 6px;
}

.hero-today-list .task-meta > span {
  font-size: 8px;
}

.hero-today-list .report-entry-badge,
.hero-today-list .work-card-copy > p,
.hero-today-list .work-details {
  display: none;
}

.hero-today-list .work-card-actions {
  grid-column: 2;
  justify-content: flex-start;
  gap: 6px;
  margin-top: 3px;
}

.hero-today-list .work-card-actions button {
  padding: 6px 8px;
  border-radius: 7px;
  font-size: 8px;
}

.hero-today-list .compact-work-empty {
  min-height: 245px;
  display: grid;
  place-content: center;
  padding: 18px;
  border-radius: 15px;
  background: white;
}

.hero-today-list .compact-work-empty > span {
  width: 40px;
  height: 40px;
  font-size: 19px;
}

.hero-today-list .compact-work-empty h3 {
  margin: 10px 0 5px;
  font-size: 16px;
}

.hero-today-list .compact-work-empty p {
  margin: 0;
  font-size: 10px;
}

.open-work-heading-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  flex-wrap: wrap;
}

.open-work-filter {
  margin-top: 18px;
}

@media (max-width: 1180px) {
  .category-hero {
    grid-template-columns: minmax(300px, .72fr) 132px minmax(410px, 1.08fr);
    gap: 18px;
  }

  .hero-completion-tile {
    width: 132px;
    height: 132px;
  }

  .hero-completion-tile .category-donut {
    width: 116px !important;
    height: 116px !important;
  }

  .hero-today-card {
    min-height: 390px;
    max-height: 410px;
    padding: 17px;
  }
}

@media (max-width: 980px) {
  .category-hero {
    grid-template-columns: 142px minmax(0, 1fr);
    grid-template-areas:
      "copy copy"
      "completion today";
    align-items: start;
    gap: 22px;
    text-align: left;
  }

  .category-hero .hero-copy {
    max-width: 760px;
  }

  .hero-completion-tile {
    width: 142px;
    height: 142px;
    margin-top: 12px;
  }

  .hero-today-card {
    min-height: 390px;
    max-height: 430px;
  }
}

@media (max-width: 720px) {
  .category-hero {
    grid-template-columns: minmax(0, 1fr);
    grid-template-areas:
      "copy"
      "today"
      "completion";
    gap: 20px;
  }

  .hero-today-card {
    min-height: 400px;
    max-height: 450px;
  }

  .hero-completion-tile {
    width: 126px;
    height: 126px;
    margin: 0 auto;
  }

  .hero-completion-tile .category-donut {
    width: 112px !important;
    height: 112px !important;
  }
}

@media (max-width: 560px) {
  .hero-today-card {
    min-height: 430px;
    max-height: 500px;
    padding: 14px;
    border-radius: 17px;
  }

  .hero-today-heading {
    flex-direction: column;
    gap: 10px;
  }

  .hero-today-heading h2 {
    font-size: 25px;
  }

  .hero-opening-summary {
    width: 100%;
    min-width: 0;
    justify-items: start;
    text-align: left;
  }

  .hero-work-filter {
    align-items: stretch;
    flex-direction: column;
    gap: 7px;
  }

  .hero-work-filter span {
    padding: 0 5px 2px;
  }

  .hero-today-list .compact-work-empty {
    min-height: 190px;
  }

  .open-work-heading-actions {
    width: 100%;
    justify-content: flex-start;
  }
}
/* END MECARDEE_HERO_TODAY_WORK_UI_V2 */
'@

$oldCssPatterns = @(
    '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V1 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V1 \*/\s*',
    '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V2 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V2 \*/\s*'
)

foreach ($pattern in $oldCssPatterns) {
    $css = [System.Text.RegularExpressions.Regex]::Replace($css, $pattern, "`r`n")
}

$css = $css.TrimEnd() + "`r`n`r`n" + $cssPatch.Trim() + "`r`n"

if ($page -match 'hero-add-work-button') {
    throw "Safety check failed: duplicate Add work button is still present inside the Today card."
}

if ($page -match 'hero-work-area') {
    throw "Safety check failed: old two-column hero wrapper is still present."
}

if ($page -notmatch 'hero-completion-tile') {
    throw "Safety check failed: completion tile was not inserted."
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
    Write-Host "Hero layout V2 applied successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Changes:" -ForegroundColor Green
    Write-Host "  - Today's work moved into the large right-side area"
    Write-Host "  - Completion donut moved into its own small square area"
    Write-Host "  - Duplicate Add work button removed from the Today card"
    Write-Host "  - Hero text changed to ASCII to remove broken apostrophes and symbols"
    Write-Host "  - Responsive tablet and mobile layouts added"
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
