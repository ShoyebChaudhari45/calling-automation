# Rudvaya AI Lead Automation - one-time n8n setup for a new machine
# Run with: powershell -ExecutionPolicy Bypass -File setup-n8n.ps1
# (n8n must NOT be running while this runs - it writes to n8n's database.)
#
# Does README section 1 (community node), section 2-4 (n8n credentials) and section 5 (import +
# wiring + activation) automatically:
#   1. installs the n8n-nodes-bolna community node into ~/.n8n/nodes
#   2. creates the 3 credentials with the exact IDs the workflow JSON files
#      reference, so every node is already wired - only the SECRETS are left
#      blank (Supabase DB password, OpenAI key, Bolna key); paste those in the
#      n8n UI afterwards. Existing credentials are never overwritten.
#   3. rewrites the 3 "Read ... Page" file paths to this folder's real path
#      and imports all 7 workflows (fixed IDs => cross-workflow links intact)
#   4. publishes (activates) all 7 workflows
# Safe to re-run: credentials are skipped if present, workflows are upserted.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# --- 0. prerequisites -------------------------------------------------------
$nodeVersion = [version]((node -v).TrimStart('v'))
if ($nodeVersion -lt [version]"22.16.0") { throw "Node.js >= 22.16 required (found $nodeVersion). Install Node 22 LTS from nodejs.org." }
if (-not (Get-Command n8n -ErrorAction SilentlyContinue)) { throw "n8n not found. Run: npm install -g n8n@2.22.6" }
if (Get-NetTCPConnection -LocalPort 5678 -State Listen -ErrorAction SilentlyContinue) { throw "n8n is running on port 5678 - stop it (close its window) and re-run this script." }

$tmp = Join-Path $env:TEMP ("rudvaya-setup-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $tmp | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false   # n8n's JSON.parse chokes on a BOM

try {
    # --- 1. Bolna community node --------------------------------------------
    $nodesDir = Join-Path $env:USERPROFILE ".n8n\nodes"
    if (-not (Test-Path (Join-Path $nodesDir "node_modules\n8n-nodes-bolna"))) {
        Write-Host "Installing n8n-nodes-bolna..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Force $nodesDir | Out-Null
        if (-not (Test-Path (Join-Path $nodesDir "package.json"))) {
            [IO.File]::WriteAllText((Join-Path $nodesDir "package.json"), '{"name":"installed-nodes","private":true,"dependencies":{}}', $utf8)
        }
        Push-Location $nodesDir
        try { npm install n8n-nodes-bolna@0.1.2 --no-fund --no-audit; if ($LASTEXITCODE) { throw "npm install n8n-nodes-bolna failed" } }
        finally { Pop-Location }
    } else { Write-Host "n8n-nodes-bolna already installed." -ForegroundColor Green }

    # --- 2. credentials (placeholders with fixed IDs) -----------------------
    $creds = @(
        @{ id = "32a87679-ef80-4766-b60d-01651c64da42"; name = "Rudvaya Supabase Postgres"; type = "postgres"
           data = @{ host = "aws-0-ap-south-1.pooler.supabase.com"; port = 5432; database = "postgres"
                     user = "postgres.nfciihzwqgqmtchcpxhz"; password = ""; ssl = "require"
                     allowUnauthorizedCerts = $true; maxConnections = 100 } },
        @{ id = "b763713c-92f4-4805-b42a-f076ab934e56"; name = "Rudvaya OpenAI"; type = "openAiApi"
           data = @{ apiKey = ""; url = "https://api.openai.com/v1" } },
        @{ id = "99cabbde-0c3d-408d-a325-142bccdfb89e"; name = "Rudvaya Bolna API"; type = "bolnaApi"
           data = @{ apiKey = "" } }
    )
    $missing = @()
    foreach ($c in $creds) {
        # export:credentials errors out when the id doesn't exist; output stays encrypted and is deleted right away
        $probe = Join-Path $tmp "probe.json"
        n8n export:credentials --id=$($c.id) --output=$probe 2>$null | Out-Null
        $exists = Test-Path $probe
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
        if ($exists) { Write-Host "Credential '$($c.name)' already exists - left untouched." -ForegroundColor Green }
        else { $missing += $c }
    }
    if ($missing.Count) {
        $credFile = Join-Path $tmp "credentials.json"
        [IO.File]::WriteAllText($credFile, (ConvertTo-Json @($missing) -Depth 5), $utf8)
        n8n import:credentials --input=$credFile
        if ($LASTEXITCODE) { throw "n8n import:credentials failed" }
        Write-Host "Created $($missing.Count) credential(s) - secrets still need to be pasted in the n8n UI." -ForegroundColor Yellow
    }

    # --- 3. workflows: fix page paths, import -------------------------------
    $wfDir = Join-Path $tmp "workflows"
    New-Item -ItemType Directory -Force $wfDir | Out-Null
    $pagesJson = (Join-Path $root "pages").Replace('\', '\\')
    foreach ($f in Get-ChildItem (Join-Path $root "workflows") -Filter "WF-*.json") {
        $text = [IO.File]::ReadAllText($f.FullName, $utf8)
        $text = [regex]::Replace($text, '("fileSelector"\s*:\s*")[^"]*?\\\\pages\\\\([\w-]+\.html")',
            { param($m) $m.Groups[1].Value + $pagesJson + '\\' + $m.Groups[2].Value })
        [IO.File]::WriteAllText((Join-Path $wfDir $f.Name), $text, $utf8)
    }
    Write-Host "Importing workflows..." -ForegroundColor Cyan
    n8n import:workflow --separate --input=$wfDir
    if ($LASTEXITCODE) { throw "n8n import:workflow failed" }

    # --- 4. publish / activate ----------------------------------------------
    foreach ($f in Get-ChildItem $wfDir -Filter "WF-*.json") {
        $id = ([IO.File]::ReadAllText($f.FullName, $utf8) | ConvertFrom-Json).id
        n8n publish:workflow --id=$id
        if ($LASTEXITCODE) { throw "Publishing $($f.Name) ($id) failed" }
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Setup done. Next:" -ForegroundColor Green
Write-Host "  1. Start n8n:  start-n8n.bat"
Write-Host "  2. http://localhost:5678 -> Credentials -> paste the secret into each of:"
Write-Host "       Rudvaya Supabase Postgres (DB password), Rudvaya OpenAI (API key), Rudvaya Bolna API (API key)"
Write-Host "  3. Open http://localhost:5678/webhook/dashboard"
