param(
    [Parameter(Mandatory = $true)] [string] $DotnetRoot,
    [Parameter(Mandatory = $true)] [string] $RuntimeVersion,
    [string] $Output
)

$ErrorActionPreference = 'Stop'
if (-not $Output) { $Output = Join-Path $PSScriptRoot 'artifacts/releases' }
$root = Split-Path -Parent $PSScriptRoot
$dotnetRootPath = (Resolve-Path -LiteralPath $DotnetRoot).Path
$dotnet = Join-Path $dotnetRootPath 'dotnet.exe'
$project = Join-Path $PSScriptRoot 'ShotMap.Windows/ShotMap.Windows.csproj'
$version = ([xml](Get-Content -LiteralPath $project -Raw)).Project.PropertyGroup.Version
if ($version -notmatch '^\d+\.\d+\.\d+-preview\.\d+$' -or $RuntimeVersion -notmatch '^10\.0\.\d+$') {
    throw 'Expected a preview app version and a .NET 10 patch runtime version.'
}

$commit = git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not read the source commit.' }
$changes = git -C $root status --porcelain --untracked-files=all -- windows
if ($LASTEXITCODE -ne 0 -or $changes) { throw 'Commit the reviewed Windows sources before packaging.' }

$name = "ShotMap-$version-windows-x64"
$build = Join-Path $Output $name
if (Test-Path -LiteralPath $build) { throw "Output already exists: $build" }
$build = (New-Item -ItemType Directory -Path $build).FullName
$stage = Join-Path $build $name
$zip = Join-Path $build "$name.zip"

& $dotnet publish $project -c Release -r win-x64 --self-contained false -warnaserror `
    --artifacts-path (Join-Path $build 'build') -o $stage `
    -p:ContinuousIntegrationBuild=true -p:DebugType=None -p:AppHostRelativeDotNet=dotnet
if ($LASTEXITCODE -ne 0) { throw 'ShotMap publish failed.' }

$licenses = (New-Item -ItemType Directory -Path (Join-Path $stage 'LICENSES')).FullName
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $licenses 'ShotMap-MIT.txt')
Copy-Item -LiteralPath (Join-Path $root 'ThirdPartyLicenses/TablerIcons-MIT.txt') -Destination $licenses
Copy-Item -LiteralPath (Join-Path $dotnetRootPath 'LICENSE.txt') -Destination (Join-Path $licenses 'DotNet-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $dotnetRootPath 'ThirdPartyNotices.txt') -Destination (Join-Path $licenses 'DotNet-ThirdPartyNotices.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PORTABLE-README.txt') -Destination (Join-Path $stage 'README.txt')

foreach ($component in 'host/fxr', 'shared/Microsoft.NETCore.App', 'shared/Microsoft.WindowsDesktop.App') {
    $from = Join-Path $dotnetRootPath "$component/$RuntimeVersion"
    $to = (New-Item -ItemType Directory -Path (Join-Path $stage "dotnet/$component") -Force).FullName
    Copy-Item -LiteralPath (Resolve-Path -LiteralPath $from).Path -Recurse -Destination $to
}

$app = Join-Path $stage 'ShotMap.exe'
$signature = (Get-AuthenticodeSignature -LiteralPath $app).Status.ToString()
[ordered]@{
    version = $version
    architecture = 'win-x64'
    sourceCommit = $commit
    desktopRuntime = $RuntimeVersion
    appAuthenticode = $signature
    bundledFfmpeg = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'build-info.json') -Encoding ASCII

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse -Force) {
        $entry = $file.FullName.Substring($build.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $archive.Dispose()
}
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
"$sha  $name.zip" | Set-Content -LiteralPath "$zip.sha256" -Encoding ASCII
Get-Item -LiteralPath $zip, "$zip.sha256"
