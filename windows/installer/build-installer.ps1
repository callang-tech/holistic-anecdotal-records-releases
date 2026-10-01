[CmdletBinding()]
param([string]$CompilerPath)
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$release = Join-Path $project 'build\windows\x64\runner\Release'
$script = Join-Path $PSScriptRoot 'HolisticAnecdotalRecords.iss'
$versionLine = Select-String -LiteralPath (Join-Path $project 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
if (-not $versionLine) { throw 'Expected a numeric pubspec version: x.y.z+build.' }
$version = $versionLine.Matches[0].Groups[1].Value
$fullVersion = "$version+$($versionLine.Matches[0].Groups[2].Value)"
$exe = Join-Path $release 'holistic_anecdotal_records.exe'
if ((Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -ne $fullVersion) {
    throw 'Release executable version differs from pubspec. Rebuild the Windows release.'
}
$assetVersion = Select-String -LiteralPath (Join-Path $release 'data\flutter_assets\pubspec.yaml') -Pattern '^version:\s*(\S+)'
if ($assetVersion.Matches[0].Groups[1].Value -ne $fullVersion) { throw 'Bundled pubspec version differs.' }
$reference = 'assets\database\locations.db'
if ((Get-FileHash -LiteralPath (Join-Path $project $reference)).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $release "data\flutter_assets\$reference")).Hash) {
    throw 'Bundled location reference database differs from the source asset.'
}
# Inspect only the explicit program payload; never enumerate user-data folders.
$payload = @(Get-Content -LiteralPath $script | ForEach-Object {
    if ($_ -match '^Source: "\{#ReleaseDir\}\\([^"]+)"') { $Matches[1] }
})
# JNI is built only when JVM support is available; no other payload is optional.
$optionalPayload = @('dartjni.dll')
foreach ($relative in $payload) {
    if ($relative.Contains('*') -or
        ($relative -notin $optionalPayload -and -not (Test-Path -LiteralPath (Join-Path $release $relative) -PathType Leaf))) {
        throw "Missing or unsafe payload entry: $relative"
    }
}
foreach ($dll in Get-ChildItem -LiteralPath $release -Filter '*.dll' -File) {
    if ($dll.Name -notin $payload) { throw "Review new runtime DLL and update allowlist: $($dll.Name)" }
}
Write-Host "Validated $($payload.Count) program files from $release; version $fullVersion."
if (-not $CompilerPath) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $CompilerPath = $command.Source }
    else {
        foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
            foreach ($major in @(6, 7)) {
                $candidate = Join-Path $base "Inno Setup $major\ISCC.exe"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $CompilerPath = $candidate; break }
            }
            if ($CompilerPath) { break }
        }
    }
}
if (-not $CompilerPath) { throw 'Inno Setup compiler ISCC.exe not found. Install Inno Setup 6.3+ separately, then rerun; no software was installed.' }
& $CompilerPath "/DAppVersion=$version" $script
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed ($LASTEXITCODE)." }
Write-Host "Compiled build\installer\HolisticAnecdotalRecords-Setup-$version.exe. Installer NOT run."
