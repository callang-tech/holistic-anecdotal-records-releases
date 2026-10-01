param(
    [string]$Updater = "$PSScriptRoot\..\..\build\local_updater\Release\holistic_local_updater.exe"
)
$ErrorActionPreference = 'Stop'
$Updater = (Resolve-Path -LiteralPath $Updater).Path
$projectRoot = (Resolve-Path -LiteralPath "$PSScriptRoot\..\..").Path
$fixtureRoot = Join-Path $projectRoot ('build\updater-validation-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null

function New-Bundle([string]$Name, [bool]$IncludeExe = $true) {
    $bundle = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $bundle 'data\flutter_assets') -Force | Out-Null
    if ($IncludeExe) { Set-Content -LiteralPath (Join-Path $bundle 'holistic_anecdotal_records.exe') -Value 'validation fixture only' }
    Set-Content -LiteralPath (Join-Path $bundle 'flutter_windows.dll') -Value 'validation fixture only'
    Set-Content -LiteralPath (Join-Path $bundle 'data\icudtl.dat') -Value 'validation fixture only'
    Set-Content -LiteralPath (Join-Path $bundle 'preserve.txt') -Value 'must remain unchanged'
    return $bundle
}
function Snapshot-Directory([string]$Directory) {
    foreach ($entry in (Get-ChildItem -LiteralPath $Directory -Force | Sort-Object FullName)) {
        if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $entry.FullName + ':reparse'
        } elseif ($entry.PSIsContainer) {
            $entry.FullName + ':directory'
            Snapshot-Directory $entry.FullName
        } else {
            $entry.FullName + ':' + (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash
        }
    }
}
function Snapshot-Fixture {
    # Never follow junctions when hashing the disposable fixture tree.
    return (@(Snapshot-Directory $fixtureRoot) -join "`n")
}
function Quote-Argument([string]$Value) {
    if ($Value.Contains('"')) { throw 'Unexpected quote in test path' }
    return '"' + [regex]::Replace($Value, '(\\+)$', '$1$1') + '"'
}
function Assert-Rejected([string]$Name, [string]$App, [string]$Source, [string]$Expected, [string[]]$Extra = @()) {
    $before = Snapshot-Fixture
    # ProcessStartInfo captures stderr without PowerShell treating native error
    # output as a script exception. These generated paths cannot contain quotes.
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Updater
    $start.Arguments = '--app-dir ' + (Quote-Argument $App) + ' --source ' + (Quote-Argument $Source) + ' --exe holistic_anecdotal_records.exe ' + ($Extra -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $code = $process.ExitCode
    $process.Dispose()
    $output = $stdout + $stderr
    if ($code -eq 0 -or $output -match 'Copy started' -or $output -notmatch $Expected) {
        throw "FAIL ${Name}: unexpected exit/output: $code $output"
    }
    if ($before -cne (Snapshot-Fixture)) { throw "FAIL ${Name}: fixture files changed" }
    Write-Output "PASS $Name (rejected, no copy, fixture hashes unchanged)"
}

$app = New-Bundle 'app'
$source = New-Bundle 'source'
$noExe = New-Bundle 'missing-exe' $false
$missing = Join-Path $fixtureRoot 'does-not-exist'
Assert-Rejected 'nonexistent application directory' $missing $source 'Cannot open path'
Assert-Rejected 'nonexistent staged source' $app $missing 'Cannot open path'
Assert-Rejected 'same source and target' $app $app 'non-nested'
Assert-Rejected 'case-insensitive same path' $app $app.ToUpperInvariant() 'non-nested'
Assert-Rejected 'source missing application exe' $app $noExe 'Both directories must contain'
Assert-Rejected 'implausible target' $noExe $source 'Both directories must contain'
Assert-Rejected 'drive root' ([System.IO.Path]::GetPathRoot($app)) $source 'drive root'
Assert-Rejected 'nested source' $app (Join-Path $app 'data') 'non-nested'
Assert-Rejected 'nested target' (Join-Path $source 'data') $source 'non-nested'
Assert-Rejected 'Documents root' ([Environment]::GetFolderPath('MyDocuments')) $source 'protected'
Assert-Rejected 'persistent application data' (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'HolisticAnecdotalRecords') $source 'protected'
Assert-Rejected 'persistent data descendant' (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'HolisticAnecdotalRecords\config') $source 'protected'
Assert-Rejected 'profile root' $env:USERPROFILE $source 'protected'
Assert-Rejected 'Windows directory' $env:WINDIR $source 'protected'
Assert-Rejected 'ProgramData root' $env:ProgramData $source 'protected'
Assert-Rejected 'application support' ([Environment]::GetFolderPath('ApplicationData')) $source 'protected'
Assert-Rejected 'wrong executable option' $app $source 'Unknown/duplicate' @('--exe', 'other.exe')
Assert-Rejected 'unrelated PID' $app $source 'PID does not belong' @('--pid', "$PID")

$hardlinkSource = New-Bundle 'hardlink-source'
New-Item -ItemType HardLink -Path (Join-Path $hardlinkSource 'alias.txt') -Target (Join-Path $hardlinkSource 'preserve.txt') | Out-Null
Assert-Rejected 'source hard link' $app $hardlinkSource 'Hard-linked'
$hardlinkTarget = New-Bundle 'hardlink-target'
New-Item -ItemType HardLink -Path (Join-Path $hardlinkTarget 'alias.txt') -Target (Join-Path $hardlinkTarget 'preserve.txt') | Out-Null
Assert-Rejected 'target hard link' $hardlinkTarget $source 'Hard-linked'

$junctionSource = New-Bundle 'junction-source'
New-Item -ItemType Junction -Path (Join-Path $junctionSource 'linked') -Target $source | Out-Null
Assert-Rejected 'source junction' $app $junctionSource 'Reparse points'
$junctionTarget = New-Bundle 'junction-target'
New-Item -ItemType Junction -Path (Join-Path $junctionTarget 'linked') -Target $source | Out-Null
Assert-Rejected 'target junction' $junctionTarget $source 'Reparse points'
Assert-Rejected 'junction ancestor' (Join-Path $junctionTarget 'linked') $source 'Reparse points'

$held = [System.IO.File]::Open((Join-Path $app 'preserve.txt'), 'Open', 'Read', 'Read')
try {
    Assert-Rejected 'target file held against writing' $app $source 'files are in use|Cannot open path'
} finally { $held.Dispose() }

# A disposable copy of the Windows command interpreter supplies a real process
# with the target image name. It only waits on redirected stdin, then exits.
$runningApp = New-Bundle 'running-app'
Copy-Item -LiteralPath "$env:WINDIR\System32\cmd.exe" -Destination (Join-Path $runningApp 'holistic_anecdotal_records.exe')
$startApp = New-Object System.Diagnostics.ProcessStartInfo
$startApp.FileName = Join-Path $runningApp 'holistic_anecdotal_records.exe'
$startApp.Arguments = '/D /Q'
$startApp.UseShellExecute = $false
$startApp.CreateNoWindow = $true
$startApp.RedirectStandardInput = $true
$startApp.RedirectStandardOutput = $true
$startApp.RedirectStandardError = $true
$running = [System.Diagnostics.Process]::Start($startApp)
try {
    Assert-Rejected 'running application' $runningApp $source 'still running'
} finally {
    $running.StandardInput.WriteLine('exit')
    $running.StandardInput.Close()
    $running.WaitForExit()
    $running.Dispose()
}

$collisionSource = New-Bundle 'collision-source'
# Create a directory/file collision using a unique fixture name.
New-Item -ItemType Directory -Path (Join-Path $collisionSource 'collision') | Out-Null
Set-Content -LiteralPath (Join-Path $app 'collision') -Value 'must remain unchanged'
Assert-Rejected 'directory/file collision' $app $collisionSource 'conflicts with a target file'

Write-Output "Validation fixtures retained at $fixtureRoot. No successful replacement or version upgrade was attempted."
