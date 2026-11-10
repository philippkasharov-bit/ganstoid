# MR1: downloads the real-LA source data for the map area. Run on a PC with internet
# (the build sandbox cannot reach these servers). Output goes to tools\city\osm\.
#   osm_full.json        everything OpenStreetMap has in the area: roads, sidewalks, crossings,
#                        buildings with their tags, land use, parking lots, barriers, trees,
#                        signals, bus stops, rail, water (Overpass API, ODbL)
#   parcels\page_N.json  LA County Assessor parcels: real lot lines, use type, year built, units
# Progress and the result are written to tools\city\osm\fetch.log (last line DONE or ERROR ...).
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
    $parcels = 'https://public.gis.lacounty.gov/public/rest/services/LACounty_Cache/LACounty_Parcel/MapServer/0/query'
    $fields = 'AIN,UseCode,UseType,UseDescription,YearBuilt1,Units1,SQFTmain1,SitusHouseNo,SitusStreet'
    $page = 0
    while ($true) {
        $file = Join-Path $out ("parcels\page_{0}.json" -f $page)
        $url = "$parcels`?where=1%3D1&geometry=$W,$S,$E,$N&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects" +
            "&outFields=$fields&outSR=4326&geometryPrecision=6&orderByFields=OBJECTID&resultOffset=$($page * 1000)&resultRecordCount=1000&f=geojson"
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri $url -OutFile $file
        $n = ((Get-Content $file -Raw | ConvertFrom-Json).features).Count
        Say "parcels page $page : $n"
        if ($n -lt 1000) { break }
        $page++
    }
    Say 'parcels complete; asking Overpass for the full OSM extract (can take a few minutes)'
    $q = "[out:json][timeout:600][maxsize:1073741824];(node($S,$W,$N,$E)[~`".`"~`".`"];way($S,$W,$N,$E);relation($S,$W,$N,$E)[type=multipolygon];);out tags geom;"
    $osm = Join-Path $out 'osm_full.json'
    foreach ($server in 'https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter') {
        try {
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Method Post -Uri $server -Body @{ data = $q } -OutFile $osm
            if ((Get-Item $osm).Length -gt 5MB) { Say "osm from $server : $([int]((Get-Item $osm).Length / 1MB)) MB"; break }
            Say "osm from $server : answer too small, trying the next server"
        } catch { Say "osm from $server failed: $($_.Exception.Message)" }
    }
    if (-not (Test-Path $osm) -or (Get-Item $osm).Length -le 5MB) { throw 'no Overpass server returned the extract' }
    Say 'DONE'
} catch { Say "ERROR $($_.Exception.Message)" }
