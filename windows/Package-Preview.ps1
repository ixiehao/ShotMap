param(
    [Parameter(Mandatory = $true)] [string] $DotnetRoot,
    [Parameter(Mandatory = $true)] [string] $RuntimeVersion,
    [Parameter(Mandatory = $true)] [string] $MediaRoot,
    [Parameter(Mandatory = $true)] [string] $MediaSourceDirectory,
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
$inputs = [ordered]@{
    'ffmpeg-9.1.tar.xz' = '1a4d394ae63d190a526cd052eb4415c156b5c5e2df37efab41a7de0b8fde2433'
    'libwebp-1.6.0.tar.gz' = 'e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564'
    'zlib-1.4.tar.gz' = '02dd159783677a749c04adbdd02b55b8a2bcc7e054f51b76b549199a916ad584'
}
$mediaSourcePath = (Resolve-Path -LiteralPath $MediaSourceDirectory).Path
foreach ($inputArchive in $inputs.Keys) {
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $mediaSourcePath $inputArchive)).Hash
    if ($sha -ne $inputs[$inputArchive]) { throw "Unexpected SHA-256 for $inputArchive" }
}
$mediaPath = (Resolve-Path -LiteralPath $MediaRoot).Path
$sourceName = "ShotMap-$version-ffmpeg-source"
$mediaDir = Join-Path $mediaPath 'bin'
$ffmpeg = (Resolve-Path -LiteralPath (Join-Path $mediaDir 'ffmpeg.exe')).Path
$ffprobe = (Resolve-Path -LiteralPath (Join-Path $mediaDir 'ffprobe.exe')).Path
$ffmpegVersion = & $ffmpeg -version
if ($LASTEXITCODE -ne 0 -or $ffmpegVersion[0] -notmatch '^ffmpeg version 9\.1\b' -or
    ($ffmpegVersion -join ' ') -match '--enable-(gpl|nonfree|version3)' -or
    ($ffmpegVersion -join ' ') -notmatch '--enable-libwebp') {
    throw 'The FFmpeg binary is not the expected LGPL build with libwebp.'
}
$probeVersion = & $ffprobe -version
if ($LASTEXITCODE -ne 0 -or $probeVersion[0] -notmatch '^ffprobe version 9\.1\b') { throw 'Unexpected ffprobe version.' }
$mediaFiles = @(Get-ChildItem -LiteralPath $mediaDir -File | Where-Object {
    $_.Name -in 'ffmpeg.exe', 'ffprobe.exe' -or $_.Extension -eq '.dll'
})
foreach ($library in 'avcodec', 'avformat', 'avfilter', 'avutil', 'swresample', 'swscale') {
    if (-not ($mediaFiles.Name -match "^$library-\d+\.dll$")) { throw "Missing shared library: $library" }
}
$build = Join-Path $Output $name
if (Test-Path -LiteralPath $build) { throw "Output already exists: $build" }
$build = (New-Item -ItemType Directory -Path $build).FullName
$stage = Join-Path $build $name
$zip = Join-Path $build "$name.zip"
$sourceStage = (New-Item -ItemType Directory -Path (Join-Path $build $sourceName)).FullName
$sourceZip = Join-Path $build "$sourceName.zip"

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
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PORTABLE-MEDIA.md') -Destination (Join-Path $licenses 'FFmpeg-sources.md')
Copy-Item -LiteralPath (Join-Path $mediaPath 'licenses') -Recurse -Destination (Join-Path $licenses 'FFmpeg')
$bundledBin = (New-Item -ItemType Directory -Path (Join-Path $stage 'ffmpeg/bin')).FullName
Copy-Item -LiteralPath $mediaFiles.FullName -Destination $bundledBin

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
    bundledFfmpeg = $true
    ffmpeg = '9.1'
    libwebp = '1.6.0'
    zlib = '1.4'
    mediaSourceArchive = "$sourceName.zip"
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'build-info.json') -Encoding ASCII

foreach ($inputArchive in $inputs.Keys) {
    Copy-Item -LiteralPath (Join-Path $mediaSourcePath $inputArchive) -Destination $sourceStage
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PORTABLE-MEDIA.md'), (Join-Path $PSScriptRoot 'Build-PortableMedia.sh') -Destination $sourceStage
($ffmpegVersion + $probeVersion) | Set-Content -LiteralPath (Join-Path $sourceStage 'configuration.txt') -Encoding ASCII
$inputs.GetEnumerator() | ForEach-Object { "$($_.Value)  $($_.Key)" } |
    Set-Content -LiteralPath (Join-Path $sourceStage 'sources.sha256') -Encoding ASCII

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function Write-ReleaseZip([string] $Directory, [string] $Destination) {
    $prefix = Split-Path -Parent $Directory
    $archive = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $Directory -File -Recurse -Force) {
            $entry = $file.FullName.Substring($prefix.Length + 1).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        $archive.Dispose()
    }
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    "$sha  $(Split-Path -Leaf $Destination)" | Set-Content -LiteralPath "$Destination.sha256" -Encoding ASCII
}
Write-ReleaseZip $stage $zip
Write-ReleaseZip $sourceStage $sourceZip
Get-Item -LiteralPath $zip, "$zip.sha256", $sourceZip, "$sourceZip.sha256"
