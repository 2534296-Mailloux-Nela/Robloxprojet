# Build and inspect a disposable Rojo place. Never use the original .rbxl as output.
param([Parameter(Mandatory = $true)][string] $RojoPath)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$build = Join-Path $root 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$place = Join-Path $build 'RestaurantSlice-validation.rbxlx'
$mapFile = Join-Path $build 'RestaurantSlice-sourcemap.json'
if (-not (Test-Path -PathType Leaf $RojoPath)) { throw "Rojo executable not found: $RojoPath" }
if (-not (Test-Path -PathType Leaf (Join-Path $root 'default.project.json'))) { throw 'Project configuration not found' }
& $RojoPath build (Join-Path $root 'default.project.json') -o $place
if ($LASTEXITCODE -ne 0) { throw "Rojo build failed ($LASTEXITCODE)" }
& $RojoPath sourcemap --include-non-scripts (Join-Path $root 'default.project.json') -o $mapFile
if ($LASTEXITCODE -ne 0) { throw "Rojo sourcemap failed ($LASTEXITCODE)" }

# Path -> expected Roblox class and, for scripts, the source file Rojo must embed.
$expected = @{
    '/ReplicatedStorage' = @('ReplicatedStorage')
    '/ReplicatedStorage/Remotes' = @('Folder')
    '/ReplicatedStorage/Remotes/ActionRequest' = @('RemoteEvent')
    '/ReplicatedStorage/Remotes/ActionResult' = @('RemoteEvent')
    '/ReplicatedStorage/Remotes/StateDelta' = @('RemoteEvent')
    '/ReplicatedStorage/Remotes/SnapshotRequest' = @('RemoteEvent')
    '/ReplicatedStorage/Remotes/StateSnapshot' = @('RemoteEvent')
    '/ReplicatedStorage/Shared' = @('Folder')
    '/ReplicatedStorage/Shared/Protocol' = @('ModuleScript', 'src/shared/Protocol.luau')
    '/ServerScriptService' = @('ServerScriptService')
    '/ServerScriptService/Bootstrap' = @('Script', 'src/server/Bootstrap.server.luau')
    '/ServerScriptService/Infrastructure' = @('Folder')
    '/ServerScriptService/Infrastructure/NetworkService' = @('ModuleScript', 'src/server/Infrastructure/NetworkService.luau')
    '/ServerScriptService/Services' = @('Folder')
    '/ServerScriptService/Services/GameService' = @('ModuleScript', 'src/server/Services/GameService.luau')
    '/StarterPlayer' = @('StarterPlayer')
    '/StarterPlayer/StarterPlayerScripts' = @('StarterPlayerScripts')
    '/StarterPlayer/StarterPlayerScripts/Bootstrap' = @('LocalScript', 'src/client/Bootstrap.client.luau')
    '/StarterPlayer/StarterPlayerScripts/Controllers' = @('Folder')
    '/StarterPlayer/StarterPlayerScripts/Controllers/InputController' = @('ModuleScript', 'src/client/Controllers/InputController.luau')
    '/StarterPlayer/StarterPlayerScripts/Controllers/UIController' = @('ModuleScript', 'src/client/Controllers/UIController.luau')
}
function Check-Node([string] $path, [string] $class, [string] $source) {
    if (-not $expected.ContainsKey($path)) { throw "Unexpected instance: $path ($class)" }
    $want = $expected[$path]
    if ($class -cne $want[0]) { throw "Wrong class at ${path}: $class, expected $($want[0])" }
    if ($want.Count -gt 1) {
        if ($source -cne $want[1]) { throw "Wrong source path at ${path}: $source, expected $($want[1])" }
    } elseif ($source) { throw "Unexpected source at ${path}: $source" }
}

$map = Get-Content -Raw -LiteralPath $mapFile | ConvertFrom-Json
if ($map.className -cne 'DataModel') { throw 'Sourcemap root must be DataModel' }
$mapSeen = @{}
function Walk-Map($node, [string] $parent) {
    foreach ($child in $node.children) {
        $path = "$parent/$($child.name)"
        if ($mapSeen.ContainsKey($path)) { throw "Duplicate sourcemap instance: $path" }
        $mapSeen[$path] = $true
        $source = if ($child.filePaths) { if ($child.filePaths.Count -ne 1) { throw "Multiple source paths at $path" }; $child.filePaths[0] } else { '' }
        Check-Node $path $child.className $source
        Walk-Map $child $path
    }
}
Walk-Map $map ''
if ($mapSeen.Count -ne $expected.Count) { throw "Sourcemap has $($mapSeen.Count) instances, expected $($expected.Count)" }

$xml = New-Object System.Xml.XmlDocument
$xml.Load($place)
if ($xml.roblox.version -cne '4') { throw 'Unexpected place XML version' }
$xmlSeen = @{}
$sourceCount = 0
function Walk-Xml($parent, [string] $prefix) {
    foreach ($item in $parent.ChildNodes | Where-Object { $_.LocalName -eq 'Item' }) {
        $nameNode = $item.SelectSingleNode('./Properties/string[@name="Name"]')
        if ($null -eq $nameNode -or -not $nameNode.InnerText) { throw "Unnamed instance under $prefix" }
        $path = "$prefix/$($nameNode.InnerText)"
        if ($xmlSeen.ContainsKey($path)) { throw "Duplicate XML instance: $path" }
        $xmlSeen[$path] = $true
        $want = $expected[$path]
        if ($null -eq $want) { throw "Unexpected XML instance: $path" }
        $sourceNode = $item.SelectSingleNode('./Properties/*[@name="Source"]')
        $source = if ($want.Count -gt 1) { $want[1] } else { '' }
        Check-Node $path $item.class $source
        if ($source) {
            if ($null -eq $sourceNode) { throw "Missing embedded Source: $path" }
            $actual = $sourceNode.InnerText.Replace("`r`n", "`n")
            $original = [System.IO.File]::ReadAllText((Join-Path $root $source)).Replace("`r`n", "`n")
            if ($actual -cne $original) { throw "Embedded Source differs from $source" }
            $script:sourceCount++
        } elseif ($null -ne $sourceNode) { throw "Unexpected embedded Source: $path" }
        Walk-Xml $item $path
    }
}
Walk-Xml $xml.roblox ''
if ($xmlSeen.Count -ne $expected.Count) { throw "XML has $($xmlSeen.Count) instances, expected $($expected.Count)" }

# Static contract only: verify that both endpoints refer to the mapped remotes
# and that the declared protocol actions/version agree with the current slice.
$protocol = [System.IO.File]::ReadAllText((Join-Path $root 'src/shared/Protocol.luau'))
if ($protocol -notmatch '(?m)^Protocol\.VERSION\s*=\s*1\s*$') { throw 'Protocol version is not 1' }
$declared = [regex]::Matches($protocol, '(?m)^\s*([A-Za-z]+)\s*=\s*\{[^\r\n]*\},?\s*$') | ForEach-Object { $_.Groups[1].Value }
$actions = @('SetReady', 'PickUp', 'PutDown', 'BeginWork', 'EndWork', 'TakeOrder', 'Serve', 'NextDay')
if (@($declared).Count -ne $actions.Count -or @($declared | Where-Object { $actions -cnotcontains $_ }).Count -ne 0) { throw "Unexpected protocol actions: $($declared -join ', ')" }
$remotes = @('ActionRequest', 'ActionResult', 'StateDelta', 'SnapshotRequest', 'StateSnapshot')
foreach ($file in @('src/client/Bootstrap.client.luau', 'src/server/Infrastructure/NetworkService.luau')) {
    $text = [System.IO.File]::ReadAllText((Join-Path $root $file))
    foreach ($remote in $remotes) {
        if (-not $text.Contains((':WaitForChild("{0}")' -f $remote))) { throw "$file does not bind $remote" }
    }
}
Write-Output "PASS: Rojo build + sourcemap + XML: $($xmlSeen.Count) instances, 5 RemoteEvents, $sourceCount exact embedded scripts"
Write-Output 'PASS: Static protocol v1: 8 actions, 5 remotes referenced by both endpoints'
Write-Output "Generated (ignored): $place"
