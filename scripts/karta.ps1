<#
.SYNOPSIS
    Karta Navigation Platform — Windows PowerShell Task Runner (Phase 1)
.EXAMPLE
    .\scripts\karta.ps1 up
    .\scripts\karta.ps1 pipeline -Region sg
    .\scripts\karta.ps1 postgis-load
    .\scripts\karta.ps1 test-api
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet("env", "up", "down", "logs", "ps", "pipeline", "pmtiles", "valhalla-build", "postgis-load", "tolls-load", "redis-sync", "test-api", "web-build", "flutter-test")]
    [string]$Task = "ps",

    [string]$Region = "all",
    [switch]$SkipPmtiles,
    [switch]$SkipGtfs,
    [switch]$RefreshOsm
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "[karta] Created .env from .env.example" -ForegroundColor Cyan
}

$ComposeFile = "infra/docker/docker-compose.yml"
$BaseArgs = @("compose", "-f", $ComposeFile, "--env-file", ".env")

switch ($Task) {
    "env" {
        Write-Host "[karta] .env is ready." -ForegroundColor Green
    }
    "up" {
        & docker @BaseArgs up -d --build postgres redis pmtiles valhalla karta-api
    }
    "down" {
        & docker @BaseArgs down
    }
    "logs" {
        & docker @BaseArgs logs -f --tail=100
    }
    "ps" {
        & docker @BaseArgs ps
    }
    "pipeline" {
        & docker @BaseArgs up -d postgres redis
        $pipeArgs = @("bash", "/pipelines/scripts/run_all.sh", "--region", $Region)
        if ($SkipPmtiles) { $pipeArgs += "--skip-pmtiles" }
        if ($SkipGtfs)    { $pipeArgs += "--skip-gtfs" }
        if ($RefreshOsm)  { $pipeArgs += "--refresh-osm" }
        & docker @BaseArgs --profile pipeline run --rm pipeline @pipeArgs
    }
    "pmtiles" {
        $pbf = if ($Region -eq "all") { "malaysia-singapore-brunei-latest.osm.pbf" } else { "regions/$Region.osm.pbf" }
        $out = if ($Region -eq "all") { "my-sg-bn-full.pmtiles" } else { "$Region.pmtiles" }
        & docker @BaseArgs --profile pipeline run --rm planetiler --download --osm-path="/data/raw/osm/$pbf" --output="/data/pmtiles/$out" --force
    }
    "valhalla-build" {
        & docker @BaseArgs --profile pipeline run --rm valhalla-builder /pipelines/scripts/05_build_valhalla.sh --region $Region
    }
    "postgis-load" {
        & docker @BaseArgs up -d postgres redis
        & docker @BaseArgs --profile pipeline run --rm pipeline bash /pipelines/scripts/06_ingest_postgis.sh --region $Region
        & docker @BaseArgs --profile pipeline run --rm pipeline python3 /pipelines/scripts/07_load_tolls.py
        & docker @BaseArgs --profile pipeline run --rm pipeline python3 /pipelines/scripts/08_sync_redis_geo.py
    }
    "tolls-load" {
        & docker @BaseArgs up -d postgres redis
        & docker @BaseArgs --profile pipeline run --rm pipeline python3 /pipelines/scripts/07_load_tolls.py
        & docker @BaseArgs --profile pipeline run --rm pipeline python3 /pipelines/scripts/08_sync_redis_geo.py
    }
    "redis-sync" {
        & docker @BaseArgs up -d postgres redis
        & docker @BaseArgs --profile pipeline run --rm pipeline python3 /pipelines/scripts/08_sync_redis_geo.py
    }
    "test-api" {
        & docker @BaseArgs build karta-api
        & docker @BaseArgs run --rm --no-deps karta-api pytest -v
    }
    "web-build" {
        Push-Location "apps/karta_app"
        try {
            & flutter build web --release
        } finally {
            Pop-Location
        }
    }
    "flutter-test" {
        & flutter analyze apps/karta_app packages/karta_design_system packages/karta_api_client packages/karta_navigation_core packages/karta_map_engine packages/karta_offline_routing packages/karta_automotive_bridge
        Push-Location "apps/karta_app"
        try { & flutter test } finally { Pop-Location }
        Push-Location "packages/karta_design_system"
        try { & flutter test } finally { Pop-Location }
        Push-Location "packages/karta_navigation_core"
        try { & flutter test } finally { Pop-Location }
        Push-Location "packages/karta_api_client"
        try { & dart test } finally { Pop-Location }
        Push-Location "packages/karta_offline_routing"
        try { & flutter test } finally { Pop-Location }
        Push-Location "packages/karta_map_engine"
        try { & flutter test } finally { Pop-Location }
        Push-Location "packages/karta_automotive_bridge"
        try { & flutter test } finally { Pop-Location }
    }
}
