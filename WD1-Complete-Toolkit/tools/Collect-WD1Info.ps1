#requires -Version 5.1
<#
WD1 project environment collector 0.1.0
Read-only toward game files, save files, registry and processes.
Writes only two local reports under OutputDirectory. No network, injection,
account login, file upload, software installation or execution-policy changes.
Review this source before running. Extract outside your game installation.
Dot-sourcing defines the functions only, for unit tests.
#>
[CmdletBinding()]
param(
    [string]$GamePath = '',
    [string]$UbisoftConnectPath = '',
    [string]$SaveGamePath = '',
    [string]$OutputDirectory = '',
    [switch]$NonInteractive
)

function ConvertTo-WdFullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $clean = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    return [IO.Path]::GetFullPath($clean)
}

function Test-WdPathWithin {
    param([string]$Child, [string]$Parent)
    if (-not $Child -or -not $Parent) { return $false }
    $c = (ConvertTo-WdFullPath $Child).TrimEnd([char[]]'\/')
    $p = (ConvertTo-WdFullPath $Parent).TrimEnd([char[]]'\/')
    return ($c.Equals($p, [StringComparison]::OrdinalIgnoreCase) -or
        $c.StartsWith($p + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
}

function Protect-WdLabel {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $value = $Text -replace '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<ACCOUNT>'
    if ($env:USERNAME) {
        $value = [regex]::Replace($value, [regex]::Escape($env:USERNAME), '<USER>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return ($value -replace '[\r\n\t]', ' ')
}

function Get-WdRegistryValue {
    param([string]$Key, [string]$Name)
    try {
        $item = Get-ItemProperty -LiteralPath $Key -ErrorAction Stop
        $property = $item.PSObject.Properties[$Name]
        if ($property) { return [string]$property.Value }
    } catch { }
    return $null
}

function Read-WdManifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        # Whitelist fields: never export LastOwner or the original manifest.
        $raw = [IO.File]::ReadAllText($Path)
        $fields = @{}
        foreach ($key in @('appid', 'buildid', 'installdir', 'StateFlags')) {
            $match = [regex]::Match($raw, '(?im)^\s*"' + [regex]::Escape($key) + '"\s*"([^"\r\n]*)"')
            if ($match.Success) { $fields[$key] = $match.Groups[1].Value }
        }
        if ($fields['appid'] -ne '243470') { return $null }
        return [pscustomobject]@{
            appid = $fields['appid']; build_id = $fields['buildid']
            install_dir = $fields['installdir']; state_flags = $fields['StateFlags']
        }
    } catch { return $null }
}

function Get-WdLibraryPaths {
    param([string]$SteamRoot)
    if (-not $SteamRoot) { return }
    ConvertTo-WdFullPath $SteamRoot
    $vdf = Join-Path $SteamRoot 'steamapps/libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        try {
            $raw = [IO.File]::ReadAllText($vdf)
            foreach ($m in [regex]::Matches($raw, '(?im)^\s*"path"\s*"([^"\r\n]+)"')) {
                ConvertTo-WdFullPath ($m.Groups[1].Value.Replace('\\', '\'))
            }
            # Also support old libraryfolders.vdf syntax.
            foreach ($m in [regex]::Matches($raw, '(?im)^\s*"\d+"\s*"([A-Za-z]:[^"\r\n]+)"')) {
                ConvertTo-WdFullPath ($m.Groups[1].Value.Replace('\\', '\'))
            }
        } catch { }
    }
}

function Find-WdSteamInstalls {
    param([string[]]$SteamRoots)
    $libraries = @($SteamRoots | ForEach-Object { Get-WdLibraryPaths $_ } | Sort-Object -Unique)
    foreach ($library in $libraries) {
        $manifestPath = Join-Path $library 'steamapps/appmanifest_243470.acf'
        $manifest = Read-WdManifest $manifestPath
        if ($manifest -and $manifest.install_dir) {
            # A manifest's folder name is data, not an arbitrary path to traverse.
            if ($manifest.install_dir -match '[\\/]' -or $manifest.install_dir -in @('.', '..')) { continue }
            $root = Join-Path (Join-Path $library 'steamapps/common') $manifest.install_dir
            if (Test-Path -LiteralPath $root -PathType Container) {
                [pscustomobject]@{ root = $root; manifest = $manifest }
            }
        }
    }
}

function Resolve-WdGameRoot {
    param([string]$Path)
    $root = ConvertTo-WdFullPath $Path
    if (-not $root) { throw 'GAME_FOLDER_REQUIRED' }
    if (Test-Path -LiteralPath $root -PathType Leaf) { $root = Split-Path -Parent $root }
    if ((Split-Path -Leaf $root) -ieq 'bin') { $root = Split-Path -Parent $root }
    foreach ($candidate in @('bin/Watch_Dogs.exe', 'bin/WatchDogs.exe', 'Watch_Dogs.exe', 'WatchDogs.exe')) {
        if (Test-Path -LiteralPath (Join-Path $root $candidate) -PathType Leaf) { return $root }
    }
    throw 'WATCH_DOGS_EXE_NOT_FOUND'
}

function Get-WdPeMachine {
    param([string]$Path)
    $stream = $null
    $reader = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $reader = New-Object IO.BinaryReader($stream)
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { return 'not_pe' }
        [void]$stream.Seek(0x3C, [IO.SeekOrigin]::Begin)
        $offset = $reader.ReadUInt32()
        if ($offset -gt ($stream.Length - 6)) { return 'invalid_pe' }
        [void]$stream.Seek($offset, [IO.SeekOrigin]::Begin)
        if ($reader.ReadUInt32() -ne 0x00004550) { return 'invalid_pe' }
        switch ($reader.ReadUInt16()) {
            0x8664 { return 'x64' }
            0x014C { return 'x86' }
            0xAA64 { return 'arm64' }
            default { return 'other' }
        }
    } catch { return 'unreadable' }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Get-WdFileRecord {
    param([string]$Root, [string]$RelativePath, [switch]$Hash)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return [pscustomobject]@{ relative_path = (Protect-WdLabel $RelativePath); status = 'link_skipped' }
        }
        $sha = $null
        if ($Hash) { $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash }
        $pe = $null
        $version = $null
        if ($item.Extension -in @('.exe', '.dll')) {
            $pe = Get-WdPeMachine $path
            $version = Protect-WdLabel ([string]$item.VersionInfo.FileVersion)
        }
        return [pscustomobject]@{
            relative_path = (Protect-WdLabel $RelativePath.Replace('\', '/'))
            size_bytes = $item.Length; last_write_utc = $item.LastWriteTimeUtc.ToString('o')
            file_version = $version; pe_machine = $pe; sha256 = $sha; status = 'read'
        }
    } catch {
        return [pscustomobject]@{ relative_path = (Protect-WdLabel $RelativePath); status = 'read_failed' }
    }
}

function Find-WdSaveFolders {
    param([string[]]$LauncherRoots, [string]$ExplicitSavePath = '')
    $found = @()
    $accountNumber = 0
    foreach ($launcher in @($LauncherRoots | Sort-Object -Unique)) {
        $saveRoot = Join-Path $launcher 'savegames'
        if (-not (Test-Path -LiteralPath $saveRoot -PathType Container)) { continue }
        foreach ($account in @(Get-ChildItem -LiteralPath $saveRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if (($account.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $accountNumber++
            foreach ($code in @('541', '274')) {
                $folder = Join-Path $account.FullName $code
                if (Test-Path -LiteralPath $folder -PathType Container) {
                    $dir = Get-Item -LiteralPath $folder -ErrorAction SilentlyContinue
                    if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    $found += [pscustomobject]@{
                        private_path = $folder
                        public_path = ('<UBISOFT_CONNECT>/savegames/<ACCOUNT_{0:D2}>/{1}' -f $accountNumber, $code)
                        folder_code = $code
                    }
                }
            }
        }
    }
    if ($ExplicitSavePath) {
        $explicit = ConvertTo-WdFullPath $ExplicitSavePath
        if (-not (Test-Path -LiteralPath $explicit -PathType Container)) { throw 'SAVE_FOLDER_NOT_FOUND' }
        $code = Split-Path -Leaf $explicit
        if ($code -notin @('541', '274')) { throw 'SELECT_ONLY_WD1_SAVE_FOLDER_541_OR_274' }
        if (-not @($found | Where-Object { (ConvertTo-WdFullPath $_.private_path) -eq $explicit }).Count) {
            $found += [pscustomobject]@{
                private_path = $explicit; public_path = ('<SELECTED_WD1_SAVE>/' + $code); folder_code = $code
            }
        }
    }
    return $found
}

function Get-WdSaveRecord {
    param($Folder)
    $files = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder.private_path -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        # No save contents or hashes are read/exported in this preparation step.
        $files += [pscustomobject]@{
            name = (Protect-WdLabel $file.Name); size_bytes = $file.Length
            last_write_utc = $file.LastWriteTimeUtc.ToString('o')
        }
    }
    return [pscustomobject]@{
        location = $Folder.public_path; folder_code = $Folder.folder_code; files = $files
        active_save_confirmed = $false
    }
}

function Get-WdConfigRecords {
    param([string]$DocumentsRoot)
    $root = Join-Path $DocumentsRoot 'My Games/Watch_Dogs'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
    $i = 0
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $i++
        $file = Join-Path $dir.FullName 'GamerProfile.xml'
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $info = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
            [pscustomobject]@{
                location = ('<DOCUMENTS>/My Games/Watch_Dogs/<PROFILE_{0:D2}>/GamerProfile.xml' -f $i)
                size_bytes = $info.Length; last_write_utc = $info.LastWriteTimeUtc.ToString('o')
                contents_exported = $false
            }
        }
    }
}

function Test-WdReparseAncestor {
    param([string]$Path)
    $current = ConvertTo-WdFullPath $Path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    return $false
}

function Invoke-WdCollection {
    param([string]$GamePath, [string]$UbisoftConnectPath, [string]$SaveGamePath,
          [string]$OutputDirectory, [switch]$NonInteractive)
    if ($env:OS -ne 'Windows_NT') { throw 'WINDOWS_REQUIRED' }
    $ErrorActionPreference = 'Stop'
    Write-Host 'WD1 只读环境检测 0.1.0' -ForegroundColor Cyan
    Write-Host '不联网、不上传、不修改游戏/存档，不需要管理员权限。'
    Write-Host '输出报告不包含完整安装路径、账号目录名或 Steam LastOwner。'
    Write-Host ''

    $steamRoots = @(@(
        (Get-WdRegistryValue 'HKCU:\Software\Valve\Steam' 'SteamPath')
        (Get-WdRegistryValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath')
    ) | Where-Object { $_ })
    if (${env:ProgramFiles(x86)}) { $steamRoots += Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    $installs = @(Find-WdSteamInstalls @($steamRoots))
    if (-not $GamePath) {
        if ($installs.Count -eq 1) {
            $GamePath = $installs[0].root
            Write-Host '已找到 Steam 的 Watch_Dogs 安装目录。'
        } elseif ($NonInteractive) {
            throw 'SPECIFY_GAME_PATH'
        } else {
            Write-Host 'Steam → 库 → 看门狗 → 属性 → 已安装文件 → 浏览。'
            Write-Host '复制含 bin 和 data_win64 的游戏文件夹路径。'
            $GamePath = Read-Host '粘贴游戏目录（不是 Steam 库页面的网址）'
        }
    }
    $root = Resolve-WdGameRoot $GamePath
    if (Test-WdReparseAncestor $root) { throw 'GAME_PATH_IS_LINK_USE_REAL_FOLDER_PATH' }

    $manifest = $null
    foreach ($install in $installs) {
        if ((ConvertTo-WdFullPath $install.root) -eq $root) { $manifest = $install.manifest; break }
    }
    if (-not $manifest) {
        $possibleSteamApps = Split-Path -Parent (Split-Path -Parent $root)
        if ($possibleSteamApps) {
            $candidateManifest = Read-WdManifest (Join-Path $possibleSteamApps 'appmanifest_243470.acf')
            if ($candidateManifest -and $candidateManifest.install_dir -eq (Split-Path -Leaf $root)) {
                $manifest = $candidateManifest
            }
        }
    }

    $launchers = @(@(
        $UbisoftConnectPath
        (Get-WdRegistryValue 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher' 'InstallDir')
        (Get-WdRegistryValue 'HKLM:\SOFTWARE\Ubisoft\Launcher' 'InstallDir')
    ) | Where-Object { $_ })
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }) {
        $launchers += Join-Path $pf 'Ubisoft/Ubisoft Game Launcher'
    }
    $launchers = @($launchers | ForEach-Object { ConvertTo-WdFullPath $_ } | Sort-Object -Unique)
    if ($UbisoftConnectPath -and -not (Test-Path -LiteralPath (ConvertTo-WdFullPath $UbisoftConnectPath) -PathType Container)) {
        throw 'UBISOFT_CONNECT_FOLDER_NOT_FOUND'
    }
    foreach ($launcher in $launchers) {
        if ((Test-Path -LiteralPath $launcher) -and (Test-WdReparseAncestor $launcher)) {
            throw 'UBISOFT_PATH_IS_LINK_USE_REAL_FOLDER_PATH'
        }
    }
    if ($SaveGamePath -and (Test-WdReparseAncestor $SaveGamePath)) { throw 'SAVE_PATH_IS_LINK_USE_REAL_FOLDER_PATH' }
    $saveFolders = @(Find-WdSaveFolders $launchers $SaveGamePath)
    $saves = @($saveFolders | ForEach-Object { Get-WdSaveRecord $_ })

    Write-Host '正在读取关键文件的 SHA-256；大型 DLL 可能需要一点时间……'
    $keyFiles = @(
        'bin/Watch_Dogs.exe', 'bin/WatchDogs.exe', 'Watch_Dogs.exe', 'WatchDogs.exe',
        'bin/Disrupt_b64.dll', 'bin/steam_api64.dll', 'bin/uplay_r1_loader64.dll',
        'bin/ubiorbitapi_r2_loader64.dll', 'bin/systemdetection64.dll',
        'bin/dinput8.dll', 'bin/dsound.dll', 'bin/dxgi.dll', 'bin/d3d11.dll',
        'bin/version.dll', 'bin/NexusTools.asi'
    )
    $files = @($keyFiles | ForEach-Object { Get-WdFileRecord $root $_ -Hash } | Where-Object { $_ })
    $archives = @()
    $dataPath = Join-Path $root 'data_win64'
    if (Test-Path -LiteralPath $dataPath -PathType Container) {
        if (Test-WdReparseAncestor $dataPath) { throw 'DATA_PATH_IS_LINK_USE_REAL_FOLDER_PATH' }
        foreach ($file in @(Get-ChildItem -LiteralPath $dataPath -File -ErrorAction SilentlyContinue)) {
            if ($file.Extension -in @('.dat', '.fat')) {
                $rel = 'data_win64/' + $file.Name
                $doHash = ($file.Extension -ieq '.fat' -and $file.Length -le 8388608)
                $archives += Get-WdFileRecord $root $rel -Hash:$doHash
            }
        }
    }
    $mods = @()
    $modRoot = Join-Path $dataPath 'mods'
    if (Test-Path -LiteralPath $modRoot -PathType Container) {
        if (-not (Test-WdReparseAncestor $modRoot)) {
            $mods = @(Get-ChildItem -LiteralPath $modRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Protect-WdLabel $_.Name })
        }
    }
    $asiNames = @()
    $binPath = Join-Path $root 'bin'
    if (Test-Path -LiteralPath $binPath -PathType Container) {
        if (Test-WdReparseAncestor $binPath) { throw 'BIN_PATH_IS_LINK_USE_REAL_FOLDER_PATH' }
        $asiNames = @(Get-ChildItem -LiteralPath $binPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ieq '.asi' } | ForEach-Object { Protect-WdLabel $_.Name })
    }
    $docRoot = [Environment]::GetFolderPath('MyDocuments')
    $configs = @()
    if ($docRoot) { $configs = @(Get-WdConfigRecords $docRoot) }
    $running = @()
    foreach ($name in @('Watch_Dogs', 'WatchDogs', 'steam', 'UbisoftConnect', 'upc', 'UbisoftGameLauncher')) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) { $running += $name }
    }
    $winKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = Get-WdRegistryValue $winKey 'CurrentBuildNumber'
    $osName = Get-WdRegistryValue $winKey 'ProductName'
    if ($build -match '^\d+$' -and [int]$build -ge 22000 -and $osName -like '*Windows 10*') {
        $osName = $osName -replace 'Windows 10', 'Windows 11'
    }
    $publicManifest = $null
    if ($manifest) {
        $publicManifest = [pscustomobject]@{
            appid = $manifest.appid; build_id = $manifest.build_id; state_flags = $manifest.state_flags
        }
    }
    $report = [ordered]@{
        schema_version = '1.0'; tool_version = '0.1.0'; generated_at_utc = [DateTime]::UtcNow.ToString('o')
        privacy = [ordered]@{
            network_used = $false; uploaded = $false; game_or_save_writes = $false
            save_contents_exported = $false; absolute_paths_exported = $false; account_ids_exported = $false
            note = 'Inspect before sharing: custom mod/file labels may still contain personal text.'
        }
        environment = [ordered]@{
            windows_name = (Protect-WdLabel $osName); windows_build = $build
            display_version = (Get-WdRegistryValue $winKey 'DisplayVersion')
            os_64_bit = [Environment]::Is64BitOperatingSystem
            powershell_version = $PSVersionTable.PSVersion.ToString()
        }
        game = [ordered]@{
            requested_steam_appid = '243470'; steam_manifest = $publicManifest
            compatibility = 'NOT_YET_VERIFIED'; edition_ownership = 'NOT_DETECTED_BY_THIS_TOOL'
            key_files = $files; archive_metadata = $archives; mod_folder_names = $mods; asi_file_names = $asiNames
        }
        saves = $saves; configs = $configs; running_relevant_process_names = $running
        cloud_sync = 'NOT_DETECTED: do not infer cloud state from this report'
        notes = @(
            'Save folder presence does not prove which save is currently active.'
            'DLC archive presence does not prove ownership or successful DLC activation.'
            'File fingerprints identify this installation; no game compatibility is certified.'
            'Only 541/274 save folders under known launchers or an explicit selection are inspected.'
            'No Steam/Ubisoft credentials, keys, login config, registry exports or process memory are collected.'
        )
    }

    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'reports'
    }
    $outputRoot = ConvertTo-WdFullPath $OutputDirectory
    foreach ($protectedPath in @($root) + $launchers + @($saveFolders | ForEach-Object { $_.private_path })) {
        if (Test-WdPathWithin $outputRoot $protectedPath) { throw 'OUTPUT_MUST_BE_OUTSIDE_GAME_AND_UBISOFT_FOLDERS' }
    }
    if (Test-WdReparseAncestor $outputRoot) { throw 'OUTPUT_LINK_NOT_ALLOWED_SELECT_NORMAL_FOLDER' }
    $sessionName = 'WD1-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $destination = Join-Path $outputRoot $sessionName
    [void](New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop)
    $jsonPath = Join-Path $destination 'WD1-Report.json'
    $txtPath = Join-Path $destination 'WD1-Report.txt'
    $utf8 = New-Object Text.UTF8Encoding($true)
    $json = $report | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($jsonPath, $json, $utf8)
    $lines = @(
        'WD1 项目环境报告（不是修改器，也不是兼容性认证）'
        ('生成时间 UTC：' + $report.generated_at_utc)
        ('系统：' + $osName + ' / Build ' + $build)
        ('Steam Build ID：' + $(if ($manifest) { $manifest.build_id } else { '未识别；需要补充' }))
        'DLC 授权与云同步状态：未检测；请另外确认。'
        '安装目录使用相对路径表示；存档账号目录已替换为别名。'
        ''
        '关键文件：'
    )
    foreach ($file in $files) {
        $lines += ($file.relative_path + ' | ' + $file.status)
        if ($file.status -eq 'read') {
            $lines += ('  Version=' + $file.file_version + '; PE=' + $file.pe_machine + '; Bytes=' + $file.size_bytes)
            $lines += ('  SHA256=' + $file.sha256)
        }
    }
    $lines += ''; $lines += '候选存档位置（不等于已确认活动存档）：'
    if ($saves.Count -eq 0) { $lines += '未找到；可能是自定义 Ubisoft 路径，或还没产生存档。' }
    foreach ($save in $saves) {
        $lines += $save.location
        foreach ($file in $save.files) {
            $lines += ('  ' + $file.name + ' | ' + $file.size_bytes + ' bytes | ' + $file.last_write_utc)
        }
    }
    $lines += ''; $lines += '仅输出本地报告，不复制存档，不读取存档内容，不上传。'
    $lines += '上传前请自己打开报告检查。只需发 WD1-Report.json，无须同时发 txt。'
    [IO.File]::WriteAllText($txtPath, ($lines -join [Environment]::NewLine), $utf8)
    Write-Host ''
    Write-Host '报告已生成：' -ForegroundColor Green
    Write-Host $destination
    Write-Host '请打开并检查 WD1-Report.json，再手动上传这个 JSON 文件。'
    Write-Host '不需要上传整个文件夹、存档、游戏文件或账号文件。'
    return $destination
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $null = Invoke-WdCollection -GamePath $GamePath -UbisoftConnectPath $UbisoftConnectPath `
            -SaveGamePath $SaveGamePath -OutputDirectory $OutputDirectory -NonInteractive:$NonInteractive
    } catch {
        Write-Host ''
        Write-Host ('检测未完成：' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '不要关闭安全软件或修改系统设置。请参考 README 的手动收集方法。'
        Write-Host '如需反馈，只需告知错误类型；截图前注意遮住本机路径中的用户名。'
        exit 1
    }
}
