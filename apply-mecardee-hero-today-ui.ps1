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
$backupRoot = Join-Path $root "backup-before-hero-today-work-$stamp"
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
          <span className="location-pill">⌖ {data.project.location}</span>
          <p className="eyebrow light">CATEGORY & FINANCE CONTROL</p>
          <h1>Every rupee and<br />every work item.</h1>
          <p className="hero-subtitle">
            Track category budgets, shareholder contributions, daily work and the complete financial register in one shared dashboard.
          </p>
          <div className="hero-actions">
            {isAdmin && <button className="light-button" type="button" onClick={openNewWork}>Add today’s work</button>}
            {isAdmin && <button className="credit-action-button" type="button" onClick={openNewCredit}>Add credit</button>}
            <button className="ghost-button" type="button" onClick={() => document.getElementById("transactions")?.scrollIntoView({ behavior: "smooth" })}>
              View transaction register ↓
            </button>
          </div>
          {!isAdmin && <div className="view-only-banner">View-only account · You can filter reports and change your password.</div>}
        </div>

        <div className="hero-work-area">
          <article className="hero-today-card" aria-label="Today’s work">
            <div className="hero-today-heading">
              <div>
                <span className="eyebrow">Daily work register</span>
                <h2>Today’s work</h2>
                <p>{formatDate(toDateInput())}</p>
              </div>
              {isAdmin && <button className="primary-button hero-add-work-button" type="button" onClick={openNewWork}>＋ Add work</button>}
            </div>

            <div className="hero-work-filter">
              <select value={activeCategory} onChange={(event) => setActiveCategory(event.target.value)} aria-label="Filter today’s works by category">
                <option value="all">All categories</option>
                {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
              </select>
              <span>{todayWorks.length} today · {openWorks.length} open</span>
            </div>

            <div className="hero-today-list">
              {renderWorkList(
                todayWorks,
                "No work added for today",
                isAdmin ? "Use Add work to record today’s site activity." : "No site activity is dated today."
              )}
            </div>
          </article>

          <aside className="hero-status category-hero-status compact-category-status" aria-label="Project completion">
            <CompletionDonut value={overallCategoryCompletion} size={112} />
            <div className="opening-meta">
              <span>Target opening</span>
              <strong>{formatDate(data.project.openingDate, { day: "numeric", month: "long", year: "numeric" })}</strong>
              <small>{openingDays} days remaining · {activeCategories.length} categories</small>
            </div>
          </aside>
        </div>
      </section>
'@

$newWorks = @'
      <section className="section-block works-section" id="works">
        <div className="section-heading work-heading">
          <div>
            <span className="eyebrow">Pending work register</span>
            <h2>Open works</h2>
            <p className="work-section-description">All incomplete works, sorted from newest work date to oldest.</p>
          </div>
          <div className="open-work-heading-actions">
            <span className="open-work-count">{openWorks.length} pending</span>
            {isAdmin && <button className="primary-button" type="button" onClick={openNewWork}>＋ Add work</button>}
          </div>
        </div>

        <div className="work-filter-panel work-category-filter open-work-filter">
          <select value={activeCategory} onChange={(event) => setActiveCategory(event.target.value)} aria-label="Filter open works by category">
            <option value="all">All categories</option>
            {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
          </select>
          <span>{openWorks.length} open</span>
        </div>

        <div className="work-list open-work-list">
          {renderWorkList(
            openWorks,
            "No open work",
            "Every recorded work item has been completed."
          )}
        </div>
      </section>
'@

$heroPattern = '\s*<section className="hero category-hero" id="top">.*?</section>\s*(?=<section className="summary-grid")'
$worksPattern = '\s*<section className="section-block works-section" id="works">.*?</section>\s*(?=<section className="section-block financial-report-section")'

$heroRegex = [System.Text.RegularExpressions.Regex]::new(
    $heroPattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$worksRegex = [System.Text.RegularExpressions.Regex]::new(
    $worksPattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$heroMatches = $heroRegex.Matches($page).Count
$worksMatches = $worksRegex.Matches($page).Count

if ($heroMatches -ne 1) {
    throw "Safety check failed: expected exactly one dashboard hero section, found $heroMatches. No files were changed."
}

if ($worksMatches -ne 1) {
    throw "Safety check failed: expected exactly one works section, found $worksMatches. No files were changed."
}

$page = $heroRegex.Replace($page, "`r`n$newHero`r`n`r`n", 1)
$page = $worksRegex.Replace($page, "`r`n$newWorks`r`n`r`n", 1)

$cssPatch = @'
/* MECARDEE_HERO_TODAY_WORK_UI_V1 */
.category-hero {
  grid-template-columns: minmax(320px, .9fr) minmax(560px, 1.25fr);
  gap: clamp(28px, 4vw, 58px);
  min-height: 450px;
}

.hero-work-area {
  position: relative;
  z-index: 1;
  min-width: 0;
  width: 100%;
  display: grid;
  grid-template-columns: minmax(0, 1fr) 150px;
  gap: 16px;
  align-items: stretch;
}

.hero-today-card {
  min-width: 0;
  max-height: 340px;
  overflow: hidden;
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr);
  gap: 12px;
  padding: 16px;
  border: 1px solid rgba(255,255,255,.2);
  border-radius: 20px;
  background: rgba(250,252,249,.97);
  color: var(--ink);
  box-shadow: 0 22px 55px rgba(0,0,0,.2);
  text-align: left;
}

.hero-today-heading {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 14px;
}

.hero-today-heading h2 {
  margin: 4px 0 2px;
  font-family: "Manrope", sans-serif;
  font-size: 24px;
  line-height: 1.05;
  letter-spacing: -1px;
}

.hero-today-heading p {
  margin: 0;
  color: var(--muted);
  font-size: 11px;
}

.hero-add-work-button {
  flex: 0 0 auto;
  min-height: 36px;
  padding: 9px 12px;
  font-size: 11px;
}

.hero-work-filter {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: white;
}

.hero-work-filter select {
  min-width: 0;
  flex: 1;
  border: 0;
  outline: 0;
  padding: 7px 8px;
  border-radius: 8px;
  background: var(--paper);
  color: var(--ink);
  font-size: 11px;
}

.hero-work-filter span {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: 10px;
  white-space: nowrap;
}

.hero-today-list {
  min-height: 0;
  max-height: 210px;
  overflow-y: auto;
  padding-right: 3px;
  scrollbar-width: thin;
}

.hero-today-list .work-card {
  grid-template-columns: 7px minmax(0, 1fr);
  gap: 9px;
  align-items: start;
  padding: 11px;
  border-radius: 12px;
}

.hero-today-list .work-card .status-dot {
  width: 7px;
  height: 7px;
  margin-top: 6px;
}

.hero-today-list .work-card-copy h3 {
  margin: 5px 0 0;
  font-size: 13px;
  letter-spacing: -.2px;
}

.hero-today-list .task-meta {
  gap: 5px;
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
  gap: 5px;
  margin-top: 2px;
}

.hero-today-list .work-card-actions button {
  padding: 5px 7px;
  border-radius: 7px;
  font-size: 8px;
}

.hero-today-list .compact-work-empty {
  min-height: 126px;
  display: grid;
  place-content: center;
  padding: 14px;
  border-radius: 13px;
  background: white;
}

.hero-today-list .compact-work-empty > span {
  width: 34px;
  height: 34px;
  font-size: 17px;
}

.hero-today-list .compact-work-empty h3 {
  margin: 9px 0 4px;
  font-size: 14px;
}

.hero-today-list .compact-work-empty p {
  margin: 0;
  font-size: 10px;
}

.compact-category-status {
  min-width: 0;
  width: 100%;
  align-content: center;
  justify-self: stretch;
  gap: 13px;
  padding: 12px 6px;
}

.compact-category-status .category-donut::before {
  inset: 10px;
}

.compact-category-status .category-donut > div {
  padding: 12px;
}

.compact-category-status .category-donut strong {
  font-size: 25px;
  letter-spacing: -1px;
}

.compact-category-status .category-donut span {
  max-width: 75px;
  font-size: 7px;
  letter-spacing: .8px;
}

.compact-category-status .opening-meta {
  gap: 4px;
  text-align: center;
}

.compact-category-status .opening-meta strong {
  font-size: 13px;
  line-height: 1.25;
}

.compact-category-status .opening-meta small {
  max-width: 135px;
  font-size: 9px;
  line-height: 1.35;
  text-align: center;
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

@media (max-width: 1100px) {
  .category-hero {
    grid-template-columns: minmax(300px, .8fr) minmax(500px, 1.2fr);
    gap: 28px;
  }

  .hero-work-area {
    grid-template-columns: minmax(0, 1fr) 136px;
  }
}

@media (max-width: 1050px) {
  .category-hero {
    grid-template-columns: 1fr;
    text-align: left;
  }

  .hero-work-area {
    max-width: 760px;
    margin: 0 auto;
  }

  .hero-today-card {
    width: 100%;
  }
}

@media (max-width: 700px) {
  .hero-work-area {
    grid-template-columns: 1fr;
  }

  .compact-category-status {
    grid-template-columns: auto minmax(0, 1fr);
    align-items: center;
    justify-items: start;
    gap: 14px;
    padding: 12px;
    border: 1px solid rgba(255,255,255,.12);
    border-radius: 16px;
    background: rgba(255,255,255,.05);
  }

  .compact-category-status .category-donut {
    width: 92px !important;
    height: 92px !important;
  }

  .compact-category-status .category-donut::before {
    inset: 9px;
  }

  .compact-category-status .opening-meta {
    justify-items: start;
    text-align: left;
  }

  .compact-category-status .opening-meta small {
    max-width: none;
    text-align: left;
  }
}

@media (max-width: 520px) {
  .hero-today-card {
    max-height: 390px;
    padding: 13px;
    border-radius: 16px;
  }

  .hero-today-heading h2 {
    font-size: 21px;
  }

  .hero-work-filter {
    align-items: stretch;
    flex-direction: column;
    gap: 6px;
  }

  .hero-work-filter span {
    padding: 0 4px 2px;
  }

  .open-work-heading-actions {
    width: 100%;
    justify-content: flex-start;
  }
}
/* END MECARDEE_HERO_TODAY_WORK_UI_V1 */
'@

$existingCssPatchPattern = '(?s)\s*/\* MECARDEE_HERO_TODAY_WORK_UI_V1 \*/.*?/\* END MECARDEE_HERO_TODAY_WORK_UI_V1 \*/\s*'
$css = [System.Text.RegularExpressions.Regex]::Replace(
    $css,
    $existingCssPatchPattern,
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

    Write-Host ""
    Write-Host "Running production build..." -ForegroundColor Cyan
    & npm.cmd run build

    if ($LASTEXITCODE -ne 0) {
        throw "Next.js build failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "UI patch applied successfully." -ForegroundColor Green
    Write-Host "Only these live source files were changed:" -ForegroundColor Green
    Write-Host "  app\page.jsx"
    Write-Host "  app\globals.css"
    Write-Host ""
    Write-Host "The database, Supabase queries, API routes, forms and save functions were not modified." -ForegroundColor Green
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
