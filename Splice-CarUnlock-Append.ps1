# WD1 Car Splice v3.0-append: one-shot merged car DB, append-mode.
# Original 2.7GB archive bytes are NEVER relocated: we append the new DB at the
# end of patch.dat and rewrite only the FAT index. Minimal possible diff.
# ASCII only. Windows PowerShell 5.1 safe (long arithmetic everywhere).
param(
  [Parameter(Mandatory=$true)][string]$DataDir,
  [string]$ToolDir = ""
)
$script:Version = "WD1 Car Splice v3.0-append"
$TARGET = [long]2165723542   # car DB entry hash 81165196
$NATIVE_SIZE = [long]1075943
$MASK32 = [long]4294967295

function Clean-PathArg([string]$p) {
  $p = $p.Trim()
  if ($p.StartsWith('"') -and $p.EndsWith('"') -and $p.Length -ge 2) { $p = $p.Substring(1, $p.Length - 2) }
  return $p.TrimEnd('\')
}
function U32([byte[]]$b, [long]$off) {
  return [long]([BitConverter]::ToUInt32($b, [int]$off))
}
function Read-Fat([string]$fatPath, [ref]$flags, [ref]$rows) {
  $fat = [System.IO.File]::ReadAllBytes($fatPath)
  if ($fat[0] -ne 0x33 -or $fat[1] -ne 0x54 -or $fat[2] -ne 0x41 -or $fat[3] -ne 0x46) {
    throw ("not a FAT3 archive: " + $fatPath)
  }
  $ver = U32 $fat 4
  if ($ver -ne 8) { throw ("unsupported FAT version " + $ver + " in " + $fatPath) }
  $flags.Value = (U32 $fat 8)
  $count = (U32 $fat 12)
  $rows.Value = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $count; $i++) {
    $o = 16 + $i * 16
    $h = U32 $fat $o
    $b = U32 $fat ($o + 4)
    $c = U32 $fat ($o + 8)
    $d = U32 $fat ($o + 12)
    $rows.Value.Add(@{
      "hash"   = $h
      "unc"    = (($b -shr 3) -band 0x1FFFFFFF)
      "scheme" = ($b -band 7)
      "comp"   = ($c -band 0x1FFFFFFF)
      "srcOff" = (($d -shl 3) -bor (($c -shr 29) -band 7))
    })
  }
}
function Test-FileLock([string]$f, [int]$retries, [int]$sleepMs) {
  for ($i = 0; $i -lt $retries; $i++) {
    try {
      $lk = [System.IO.File]::Open($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
      $lk.Close()
      return $null
    } catch {
      Start-Sleep -Milliseconds $sleepMs
    }
  }
  $holders = @()
  foreach ($pn in @("WatchDogs", "uplay", "steam")) {
    $p = Get-Process -Name $pn -ErrorAction SilentlyContinue
    if ($p) { $holders += $pn }
  }
  return $holders
}
function Copy-WithRetry([string]$src, [string]$dst) {
  for ($i = 1; $i -le 4; $i++) {
    try {
      [System.IO.File]::Copy($src, $dst, $true)
      return $true
    } catch {
      Write-Host ("  replace attempt " + $i + "/4 failed: " + $_.Exception.Message)
      Start-Sleep -Seconds 2
    }
  }
  return $false
}

$DataDir = Clean-PathArg $DataDir
$ToolDir = Clean-PathArg $ToolDir
if ($ToolDir -eq "") {
  if ($PSScriptRoot) { $ToolDir = $PSScriptRoot }
  else { $ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
}
Write-Host ("=== " + $script:Version + " ===")

$patchDat = Join-Path $DataDir "patch.dat"
$patchFat = Join-Path $DataDir "patch.fat"
$p1Dat = Join-Path $DataDir "patch1.dat"
$p1Fat = Join-Path $DataDir "patch1.fat"
if (-not ([System.IO.File]::Exists($patchDat) -and [System.IO.File]::Exists($patchFat))) {
  throw ("patch.dat/patch.fat not found in " + $DataDir)
}
$hasPatch1 = ([System.IO.File]::Exists($p1Dat) -and [System.IO.File]::Exists($p1Fat))
$usePatch1 = $false
if ($hasPatch1) {
  $flD = [long]0
  $rowsD = $null
  Read-Fat $p1Fat ([ref]$flD) ([ref]$rowsD)
  foreach ($r in $rowsD) { if ($r.hash -eq $TARGET) { $usePatch1 = $true; break } }
}
if ($usePatch1) { $pairDat = $p1Dat; $pairFat = $p1Fat; Write-Host "car DB lives in patch1 pair" }
else { $pairDat = $patchDat; $pairFat = $patchFat; Write-Host "car DB lives in patch pair" }

# ---- step 1: ensure a CLEAN native base backup exists ----
$bakDat = $pairDat + ".carbak"
$bakFat = $pairFat + ".carbak"
if (-not ([System.IO.File]::Exists($bakDat) -and [System.IO.File]::Exists($bakFat))) {
  $flC = [long]0
  $rowsC = $null
  Read-Fat $pairFat ([ref]$flC) ([ref]$rowsC)
  $curOk = $false
  foreach ($r in $rowsC) {
    if ($r.hash -eq $TARGET) {
      Write-Host ("current archive car DB: scheme " + $r.scheme + ", " + $r.comp + " B (native = " + $NATIVE_SIZE + " B)")
      if (($r.scheme -eq 0) -and ($r.comp -eq $NATIVE_SIZE)) { $curOk = $true }
      break
    }
  }
  if ($curOk) {
    $ok1 = Copy-WithRetry $pairDat $bakDat
    $ok2 = Copy-WithRetry $pairFat $bakFat
    if (-not ($ok1 -and $ok2)) { throw "could not create the clean backup (locked? close the game)" }
    Write-Host "created clean backup (.carbak) from the current native archive"
  } else {
    throw "no clean backup and current archive is not native-DB. Run the v2.9 cleanbase tool once to heal, or reinstall NGM, then run this again."
  }
}

$flB = [long]0
$rowsB = $null
Read-Fat $bakFat ([ref]$flB) ([ref]$rowsB)
$tRow = $null
foreach ($r in $rowsB) { if ($r.hash -eq $TARGET) { $tRow = $r; break } }
if ($tRow -eq $null) { throw "backup has no car DB entry - unexpected; report this" }
Write-Host ("backup check: car DB = scheme " + $tRow.scheme + ", " + $tRow.comp + " B (native = " + $NATIVE_SIZE + " B)")
if (-not (($tRow.scheme -eq 0) -and ($tRow.comp -eq $NATIVE_SIZE))) {
  throw "the .carbak backup is NOT the clean native base (it still holds an old merged DB). Run the v2.9 cleanbase tool once to heal, then run this again."
}

# ---- step 2: load the merged blob ----
$blobPath = Join-Path $ToolDir "car_db_81165196_full.bin"
if (-not [System.IO.File]::Exists($blobPath)) { throw ("merged DB blob missing: " + $blobPath) }
$blob = [System.IO.File]::ReadAllBytes($blobPath)
Write-Host ("merged car DB blob: " + $blob.Length + " B (74 cars + police/madness + Speed_08)")

# ---- step 3: build dat.new = backup dat + pad + blob (append only) ----
foreach ($f in @(($pairDat + ".new"), ($pairFat + ".new"))) {
  if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) }
}
$holders = @()
foreach ($f in @($pairDat, $pairFat)) {
  $h = Test-FileLock $f 2 1500
  if ($h -ne $null) { throw ("file is locked (close the game: " + ($h -join ",") + "): " + $f) }
}
$datNew = $pairDat + ".new"
$fatNew = $pairFat + ".new"
$okCopy = Copy-WithRetry $bakDat $datNew
if (-not $okCopy) { throw "could not copy the base archive (disk space? the archive is 2.7 GB)" }
$datLen = (Get-Item $datNew).Length
$pad = [int]((8 - ($datLen % 8)) % 8)
$writeOff = [long]($datLen + $pad)
$fs = [System.IO.File]::Open($datNew, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
try {
  if ($pad -gt 0) {
    $padBuf = New-Object byte[] ($pad)
    $fs.Write($padBuf, 0, $pad)
  }
  $fs.Write($blob, 0, $blob.Length)
} finally { $fs.Close() }
Write-Host ("appended " + $blob.Length + " B at offset " + $writeOff + " (pad " + $pad + "); original bytes untouched")

# ---- step 4: build fat.new = same rows, target row points at the appended copy ----
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([byte[]]@(0x33, 0x54, 0x41, 0x46))
$bw.Write([uint32]8)
$bw.Write([uint32]$flB)
$bw.Write([uint32]($rowsB.Count))
foreach ($r in $rowsB) {
  if ($r.hash -eq $TARGET) {
    $unc2 = [long]$blob.Length
    $sch2 = [long]0
    $cmp2 = [long]$blob.Length
    $off2 = [long]$writeOff
  } else {
    $unc2 = [long]$r.unc
    $sch2 = [long]$r.scheme
    $cmp2 = [long]$r.comp
    $off2 = [long]$r.srcOff
  }
  $bw.Write([uint32]($r.hash -band $MASK32))
  $bw.Write([uint32](((($unc2 -band 0x1FFFFFFF) -shl 3) -bor ($sch2 -band 7))))
  $bw.Write([uint32](((($off2 -band 7) -shl 29) -bor ($cmp2 -band 0x1FFFFFFF))))
  $bw.Write([uint32][Math]::Floor($off2 / 8))
}
$bw.Write([uint32]0)
$bw.Flush()
[System.IO.File]::WriteAllBytes($fatNew, $ms.ToArray())
$bw.Close()

# ---- step 5: verify before swapping ----
$flV = [long]0
$rowsV = $null
Read-Fat $fatNew ([ref]$flV) ([ref]$rowsV)
if ($rowsV.Count -ne $rowsB.Count) { throw "verify: entry count mismatch" }
$vRow = $null
foreach ($r in $rowsV) { if ($r.hash -eq $TARGET) { $vRow = $r; break } }
if ($vRow -eq $null) { throw "verify: target row missing" }
if (-not (($vRow.scheme -eq 0) -and ($vRow.comp -eq $blob.Length) -and ($vRow.srcOff -eq $writeOff))) {
  throw ("verify: target row wrong (scheme " + $vRow.scheme + ", comp " + $vRow.comp + ", off " + $vRow.srcOff + ")")
}
$ds = [System.IO.File]::OpenRead($datNew)
try {
  $ds.Position = $writeOff
  $tail = New-Object byte[] ([int]$blob.Length)
  $null = $ds.Read($tail, 0, [int]$blob.Length)
} finally { $ds.Close() }
$sha = [System.Security.Cryptography.SHA256]::Create()
$h1 = ($sha.ComputeHash($tail) | ForEach-Object { $_.ToString("x2") }) -join ""
$h2 = ($sha.ComputeHash($blob) | ForEach-Object { $_.ToString("x2") }) -join ""
if ($h1 -ne $h2) { throw "verify: appended bytes do not match the blob" }
Write-Host ("verify OK: appended tail sha256 " + $h1.Substring(0, 16))

# ---- step 6: swap in ----
$okD = Copy-WithRetry $datNew $pairDat
if (-not $okD) { throw "could not replace the archive (locked? close the game). Originals intact." }
$okF = Copy-WithRetry $fatNew $pairFat
if (-not $okF) {
  $null = Copy-WithRetry $bakDat $pairDat
  throw "could not replace the fat; rolled back. Originals intact - safe to retry."
}
Remove-Item ($pairDat + ".new") -ErrorAction SilentlyContinue
Remove-Item ($pairFat + ".new") -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("OK: merged car DB spliced (append-mode). dat grew from " + $datLen + " to " + ((Get-Item $pairDat).Length) + " B")
Write-Host "All original archive bytes are untouched - only the FAT index changed + 1.1 MB appended."
Write-Host "NOW: keep Windows 7 compatibility mode ON for WatchDogs.exe, start the game,"
Write-Host "open Car On Demand and check: 74 cars + police + madness present?"
Write-Host "(if the first boot crashes, try once more - NGM baseline can be flaky)"
