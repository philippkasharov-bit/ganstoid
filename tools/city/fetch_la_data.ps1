# MR1: downloads the real-LA source data for the map area. Run on a PC with internet
# (the build sandbox cannot reach these servers). Output goes to tools\city\osm\.
#   osm_full.json        everything OpenStreetMap has in the area: roads, sidewalks, crossings,
#                        buildings with their tags, land use, parking lots, barriers, trees,
#                        signals, bus stops, rail, water (Overpass API, ODbL)
#   parcels\page_N.json  LA County Assessor parcels: real lot lines, use type, year built, units
# Progress and the result are written to tools\city\osm\fetch.log (last line DONE or ERROR ...).
param([switch]$OsmOnly)   # skip the parcels (already downloaded)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$out = Join-Path $PSScriptRoot 'osm'
$log = Join-Path $out 'fetch.log'
$S, $W, $N, $E = 34.021, -118.2745, 34.075, -118.2095    # same box as osm_import.py
function Say($t) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) }
New-Item -ItemType Directory -Force (Join-Path $out 'parcels') | Out-Null
Set-Content -Path $log -Value ''
try {
  if (-not $OsmOnly) {
    $parcels = 'https://public.gis.lacounty.gov/public/rest/services/LACounty_Cache/LACounty_Parcel/MapServer/0/query'
    $fields = 'OBJECTID,AIN,UseCode,UseType,UseDescription,YearBuilt1,Units1,SQFTmain1,SitusHouseNo,SitusStreet'
    # Asked for cell by cell: this server answers a small box correctly but loses the
    # area filter as soon as results are paged (by offset or by id), so no answer may
    # reach its 1000-record limit. A cell that does is split into four.
    $cells = New-Object System.Collections.Queue
    $nx, $ny = 12, 10
    for ($i = 0; $i -lt $nx; $i++) { for ($j = 0; $j -lt $ny; $j++) {
        # each value in its own brackets: in PowerShell the comma binds tighter than arithmetic
        $cells.Enqueue(@(($W + ($E - $W) * $i / $nx), ($S + ($N - $S) * $j / $ny), ($W + ($E - $W) * ($i + 1) / $nx), ($S + ($N - $S) * ($j + 1) / $ny)))
    } }
    $page = 0
    $total = 0
    while ($cells.Count -gt 0) {
        $c = $cells.Dequeue()
        $box = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:F6},{1:F6},{2:F6},{3:F6}', $c[0], $c[1], $c[2], $c[3])   # points, not decimal commas
        $file = Join-Path $out ("parcels\page_{0}.json" -f $page)
        $url = "$parcels`?where=1%3D1&geometry=$box&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects" +
            "&outFields=$fields&outSR=4326&geometryPrecision=6&f=geojson"
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri $url -OutFile $file
        $n = @((Get-Content $file -Raw | ConvertFrom-Json).features).Count
        if ($n -ge 1000) {
            Remove-Item $file
            $mx = ($c[0] + $c[2]) / 2; $my = ($c[1] + $c[3]) / 2
            $cells.Enqueue(@($c[0], $c[1], $mx, $my)); $cells.Enqueue(@($mx, $c[1], $c[2], $my))
            $cells.Enqueue(@($c[0], $my, $mx, $c[3])); $cells.Enqueue(@($mx, $my, $c[2], $c[3]))
            continue
        }
        $total += $n
        $page++
        if ($page % 10 -eq 0) { Say "parcels: $page cells done, $($cells.Count) to go, $total parcels so far" }
    }
    Say "parcels: $total in $page cells (lots on a cell edge are counted twice; the importer drops the copies)"
  }
    Say 'asking Overpass for the full OSM extract (can take a few minutes)'
    $q = "[out:json][timeout:600][maxsize:1073741824];(node($S,$W,$N,$E)(if:count_tags()>0);way($S,$W,$N,$E);relation($S,$W,$N,$E)[type=multipolygon];);out tags geom;"
    $osm = Join-Path $out 'osm_full.json'
    foreach ($server in 'https://maps.mail.ru/osm/tools/overpass/api/interpreter', 'https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter') {
        try {
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Method Post -Uri $server -Body @{ data = $q } -OutFile $osm
            if ((Get-Item $osm).Length -gt 5MB) { Say "osm from $server : $([int]((Get-Item $osm).Length / 1MB)) MB"; break }
            Say "osm from $server : answer too small, trying the next server"
        } catch { Say "osm from $server failed: $($_.Exception.Message)" }
    }
    if (-not (Test-Path $osm) -or (Get-Item $osm).Length -le 5MB) { throw 'no Overpass server returned the extract' }
    Say 'DONE'
} catch { Say "ERROR $($_.Exception.Message)" }
