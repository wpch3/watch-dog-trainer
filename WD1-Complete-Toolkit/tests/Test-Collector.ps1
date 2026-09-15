#requires -Version 5.1
# Offline fixture tests. Do not point these tests at a real game/save directory.
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Collect-WD1Info.ps1'
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. $source
$script:passed = 0
function Assert-Wd {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw ('FAIL: ' + $Label) }
    $script:passed++
    Write-Output ('PASS: ' + $Label)
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('wd1-test-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
try {
    Assert-Wd ($parseErrors.Count -eq 0) 'PowerShell AST parses without errors'
    $forbidden = @('Invoke-WebRequest', 'Invoke-RestMethod', 'Invoke-Expression', 'Set-ExecutionPolicy',
        'Set-ItemProperty', 'Remove-ItemProperty', 'Remove-Item', 'Start-Process', 'Stop-Process',
        'Set-NetFirewallProfile', 'Disable-NetAdapter', 'Start-BitsTransfer')
    $commands = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    Assert-Wd (@($commands | Where-Object { $_ -in $forbidden }).Count -eq 0) 'No forbidden network/mutation/launch commands'
    Assert-Wd ((ConvertTo-WdFullPath ('"' + $temp + '"')) -eq $temp) 'Quoted folder path accepted'
    Assert-Wd (Test-WdPathWithin (Join-Path $temp 'game/report') (Join-Path $temp 'game')) 'Child containment detected'
    Assert-Wd (-not (Test-WdPathWithin (Join-Path $temp 'game2') (Join-Path $temp 'game'))) 'Sibling folder not confused with child'

    $steam = Join-Path $temp 'Steam'
    $root = Join-Path $steam 'steamapps/common/Watch_Dogs'
    $bin = Join-Path $root 'bin'
    [void](New-Item -ItemType Directory -Path $bin -Force)
    $exe = Join-Path $bin 'Watch_Dogs.exe'
    $pe = New-Object byte[] 160
    $pe[0] = 0x4D; $pe[1] = 0x5A; $pe[0x3C] = 0x80
    $pe[0x80] = 0x50; $pe[0x81] = 0x45; $pe[0x84] = 0x64; $pe[0x85] = 0x86
    [IO.File]::WriteAllBytes($exe, $pe)
    $before = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    Assert-Wd ((Resolve-WdGameRoot $root) -eq $root) 'Resolve game root'
    Assert-Wd ((Resolve-WdGameRoot $bin) -eq $root) 'Resolve bin selection'
    Assert-Wd ((Resolve-WdGameRoot $exe) -eq $root) 'Resolve executable selection'
    Assert-Wd ((Get-WdPeMachine $exe) -eq 'x64') 'Read PE architecture without loading executable'
    $record = Get-WdFileRecord $root 'bin/Watch_Dogs.exe' -Hash
    Assert-Wd ($record.sha256 -eq $before -and $record.size_bytes -eq 160) 'SHA256 and byte length correct'
    Assert-Wd ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -eq $before) 'Game fixture unchanged after collection'
    Assert-Wd ($null -eq (Get-WdFileRecord $root 'bin/missing.dll' -Hash)) 'Missing file handled'
    $bad = Join-Path $bin 'not.exe'; [IO.File]::WriteAllText($bad, 'not a PE')
    Assert-Wd ((Get-WdPeMachine $bad) -eq 'not_pe') 'Non-PE handled'

    $manifestPath = Join-Path $steam 'steamapps/appmanifest_243470.acf'
    [IO.File]::WriteAllText($manifestPath, @'
"AppState"
{
  "appid" "243470"
  "buildid" "12345678"
  "installdir" "Watch_Dogs"
  "StateFlags" "4"
  "LastOwner" "76561199999999999"
}
'@)
    $manifest = Read-WdManifest $manifestPath
    Assert-Wd ($manifest.build_id -eq '12345678' -and $manifest.appid -eq '243470') 'Whitelist Steam manifest fields'
    Assert-Wd (($manifest | ConvertTo-Json) -notmatch 'LastOwner|76561199999999999') 'Steam owner ID not exported'
    $installs = @(Find-WdSteamInstalls @($steam))
    Assert-Wd ($installs.Count -eq 1 -and $installs[0].root -eq $root) 'Find Steam installation from manifest'
    $raw = [IO.File]::ReadAllText($manifestPath)
    [IO.File]::WriteAllText($manifestPath, $raw.Replace('243470', '447040'))
    Assert-Wd ($null -eq (Read-WdManifest $manifestPath)) 'Reject different Steam AppID'
    [IO.File]::WriteAllText($manifestPath, $raw.Replace('"installdir" "Watch_Dogs"', '"installdir" "../outside"'))
    Assert-Wd (@(Find-WdSteamInstalls @($steam)).Count -eq 0) 'Reject manifest folder traversal'
    [IO.File]::WriteAllText($manifestPath, $raw)

    $launcher = Join-Path $temp 'Ubisoft'
    $accountId = '12345678-1234-1234-1234-123456789abc'
    $save = Join-Path $launcher ('savegames/' + $accountId + '/541')
    [void](New-Item -ItemType Directory -Path $save -Force)
    $saveFile = Join-Path $save '1.save'
    [IO.File]::WriteAllText($saveFile, 'SENSITIVE_FIXTURE_SAVE_CONTENT_DO_NOT_EXPORT')
    $saveBefore = (Get-FileHash -LiteralPath $saveFile -Algorithm SHA256).Hash
    $folders = @(Find-WdSaveFolders @($launcher))
    Assert-Wd ($folders.Count -eq 1 -and $folders[0].folder_code -eq '541') 'Find WD1 save folder'
    $saveRecord = Get-WdSaveRecord $folders[0]
    $saveJson = $saveRecord | ConvertTo-Json -Depth 8
    Assert-Wd ($saveJson -notmatch [regex]::Escape($accountId)) 'Account directory pseudonymized'
    Assert-Wd ($saveJson -notmatch 'SENSITIVE_FIXTURE|private_path') 'Save contents and private path excluded'
    Assert-Wd ($saveJson -notmatch [regex]::Escape($temp)) 'Absolute save location not exported'
    Assert-Wd ($saveRecord.files.Count -eq 1 -and $saveRecord.files[0].name -eq '1.save') 'Save metadata retained'
    Assert-Wd ((Get-FileHash -LiteralPath $saveFile -Algorithm SHA256).Hash -eq $saveBefore) 'Save fixture unchanged'
    Assert-Wd (@(Find-WdSaveFolders @($launcher) $save).Count -eq 1) 'Explicit same save not duplicated'
    Assert-Wd ((Protect-WdLabel ('abc ' + $accountId)) -notmatch $accountId) 'GUID redaction works'

    $docs = Join-Path $temp 'Documents'
    $configDir = Join-Path $docs ('My Games/Watch_Dogs/' + $accountId)
    [void](New-Item -ItemType Directory -Path $configDir -Force)
    [IO.File]::WriteAllText((Join-Path $configDir 'GamerProfile.xml'), '<Profile account="PRIVATE"/>')
    $configs = @(Get-WdConfigRecords $docs)
    $configJson = $configs | ConvertTo-Json -Depth 8
    Assert-Wd ($configs.Count -eq 1) 'Config presence detected'
    Assert-Wd ($configJson -notmatch 'PRIVATE|12345678-1234') 'Config contents and account ID excluded'
    # Exercise the report writer against fixtures only. Registry and environment are mocked;
    # this does not turn this into a Windows runtime compatibility test.
    $script:FixtureSteamRoot = $steam
    $script:FixtureLauncher = $launcher
    function Get-WdRegistryValue {
        param([string]$Key, [string]$Name)
        if ($Name -eq 'SteamPath') { return $script:FixtureSteamRoot }
        if ($Name -eq 'InstallDir' -and $Key -like '*WOW6432Node*') { return $script:FixtureLauncher }
        if ($Name -eq 'CurrentBuildNumber') { return '26100' }
        if ($Name -eq 'ProductName') { return 'Windows 10 Pro' }
        if ($Name -eq 'DisplayVersion') { return '24H2' }
        return $null
    }
    $oldOS = $env:OS; $oldPf = $env:ProgramFiles; $oldPf86 = ${env:ProgramFiles(x86)}
    try {
        $env:OS = 'Windows_NT'
        $env:ProgramFiles = Join-Path $temp 'ProgramFiles'
        ${env:ProgramFiles(x86)} = Join-Path $temp 'ProgramFilesX86'
        $reportDir = Invoke-WdCollection -OutputDirectory (Join-Path $temp 'reports') -NonInteractive
        $reportText = [IO.File]::ReadAllText((Join-Path $reportDir 'WD1-Report.json'))
        $result = $reportText | ConvertFrom-Json
        Assert-Wd ($result.game.steam_manifest.build_id -eq '12345678') 'Full fixture report has correct build ID'
        Assert-Wd ($result.environment.windows_name -eq 'Windows 11 Pro') 'Windows 11 naming corrected from build metadata'
        Assert-Wd ($result.saves.Count -eq 1) 'Single registry result remains an array after fallback paths'
        Assert-Wd ($reportText -notmatch '76561199999999999|SENSITIVE_FIXTURE|12345678-1234') 'Full report omits fixture account and save secrets'
        Assert-Wd ($reportText -notmatch [regex]::Escape($temp)) 'Full report omits absolute fixture paths'
        Assert-Wd (@(Get-ChildItem -LiteralPath $reportDir -File).Count -eq 2) 'Only JSON and text report files produced'
        Assert-Wd ($result.game.compatibility -eq 'NOT_YET_VERIFIED') 'Does not claim trainer compatibility'
        Assert-Wd ((Get-FileHash -LiteralPath $saveFile -Algorithm SHA256).Hash -eq $saveBefore) 'Full collection leaves save unchanged'
        Assert-Wd ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -eq $before) 'Full collection leaves game unchanged'
        $rejected = $false
        try {
            $null = Invoke-WdCollection -GamePath $root -OutputDirectory (Join-Path $root 'reports') -NonInteractive
        } catch { $rejected = $_.Exception.Message -eq 'OUTPUT_MUST_BE_OUTSIDE_GAME_AND_UBISOFT_FOLDERS' }
        Assert-Wd $rejected 'Refuses writing reports inside game directory'
        Assert-Wd (-not (Test-Path -LiteralPath (Join-Path $root 'reports'))) 'Rejected output directory not created'
    } finally {
        $env:OS = $oldOS; $env:ProgramFiles = $oldPf; ${env:ProgramFiles(x86)} = $oldPf86
    }
    Write-Output ('SUMMARY: ' + $script:passed + ' checks passed. Fixture tests only, not a Windows game runtime test.')
} finally {
    # This directory is generated above, never supplied by a user.
    if ($temp -and (Split-Path -Leaf $temp) -like 'wd1-test-*') {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
