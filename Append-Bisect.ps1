# WD1 Append Bisect v3.1: minimal-diff archive variants for crash bisection.
# Always restores the clean native .carbak first, then appends ONE selected car
# DB blob at the end of patch.dat and rewrites only the FAT index row.
# Original archive bytes are never relocated. ASCII only. PS 5.1 safe.
param(
  [Parameter(Mandatory=$true)][string]$DataDir,
  [string]$ToolDir = "",
  [Parameter(Mandatory=$true)][string]$BlobPath,
  [Parameter(Mandatory=$true)][string]$Tag
)
$script:Version = "WD1 Append Bisect v3.1"
$TARGET = [long]2165723542
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
function Test-FileLock([string]$f) {
  try {
    $lk = [System.IO.File]::Open($f, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $lk.Close()
    return $null
  } catch {
    $holders = @()
    foreach ($pn in @("WatchDogs", "uplay", "steam")) {
      $p = Get-Process -Name $pn -ErrorAction SilentlyContinue
      if ($p) { $holders += $pn }
    }
    return $holders
  }
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
Write-Host ("=== " + $script:Version + " : variant " + $Tag + " ===")

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
if ($usePatch1) { $pairDat = $p1Dat; $pairFat = $p1Fat } else { $pairDat = $patchDat; $pairFat = $patchFat }

$bakDat = $pairDat + ".carbak"
$bakFat = $pairFat + ".carbak"
if (-not ([System.IO.File]::Exists($bakDat) -and [System.IO.File]::Exists($bakFat))) {
  throw "no .carbak backup found. Run the v2.9 cleanbase tool once (it heals the base), then run this again."
}
$flB = [long]0
$rowsB = $null
Read-Fat $bakFat ([ref]$flB) ([ref]$rowsB)
$tRow = $null
foreach ($r in $rowsB) { if ($r.hash -eq $TARGET) { $tRow = $r; break } }
if ($tRow -eq $null) { throw "backup has no car DB entry - report this" }
Write-Host ("backup check: car DB = scheme " + $tRow.scheme + ", " + $tRow.comp + " B (native = " + $NATIVE_SIZE + " B)")
if (-not (($tRow.scheme -eq 0) -and ($tRow.comp -eq $NATIVE_SIZE))) {
  throw "the .carbak backup is NOT clean native. Run the v2.9 cleanbase tool once to heal, then run this again."
}

$blobPath2 = Clean-PathArg $BlobPath
if (-not [System.IO.File]::Exists($blobPath2)) { throw ("blob missing: " + $blobPath2) }
$blob = [System.IO.File]::ReadAllBytes($blobPath2)
$sha0 = [System.Security.Cryptography.SHA256]::Create()
$hb = ($sha0.ComputeHash($blob) | ForEach-Object { $_.ToString("x2") }) -join ""
Write-Host ("variant blob: " + $blob.Length + " B, sha256 " + $hb.Substring(0, 16))

foreach ($f in @(($pairDat + ".new"), ($pairFat + ".new"))) {
  if ([System.IO.File]::Exists($f)) { [System.IO.File]::Delete($f) }
}
foreach ($f in @($pairDat, $pairFat)) {
  $h = Test-FileLock $f
  if ($h -ne $null) { throw ("file locked - close the game (" + ($h -join ",") + "): " + $f) }
}
$datNew = $pairDat + ".new"
$fatNew = $pairFat + ".new"
$okCopy = Copy-WithRetry $bakDat $datNew
if (-not $okCopy) { throw "could not copy the base archive (disk space? it is 2.7 GB)" }
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

$flV = [long]0
$rowsV = $null
Read-Fat $fatNew ([ref]$flV) ([ref]$rowsV)
if ($rowsV.Count -ne $rowsB.Count) { throw "verify: entry count mismatch" }
$vRow = $null
foreach ($r in $rowsV) { if ($r.hash -eq $TARGET) { $vRow = $r; break } }
if ($vRow -eq $null) { throw "verify: target row missing" }
if (-not (($vRow.scheme -eq 0) -and ($vRow.comp -eq $blob.Length) -and ($vRow.srcOff -eq $writeOff))) {
  throw ("verify: target row wrong")
}
$ds = [System.IO.File]::OpenRead($datNew)
try {
  $ds.Position = $writeOff
  $tail = New-Object byte[] ([int]$blob.Length)
  $null = $ds.Read($tail, 0, [int]$blob.Length)
} finally { $ds.Close() }
$sha = [System.Security.Cryptography.SHA256]::Create()
$h1 = ($sha.ComputeHash($tail) | ForEach-Object { $_.ToString("x2") }) -join ""
if ($h1 -ne $hb) { throw "verify: appended bytes do not match the blob" }
Write-Host ("verify OK: appended tail sha256 " + $h1.Substring(0, 16))

$okD = Copy-WithRetry $datNew $pairDat
if (-not $okD) { throw "could not replace the archive (locked?). Originals intact." }
$okF = Copy-WithRetry $fatNew $pairFat
if (-not $okF) {
  $null = Copy-WithRetry $bakDat $pairDat
  throw "could not replace the fat; rolled back. Originals intact - safe to retry."
}
Remove-Item ($pairDat + ".new") -ErrorAction SilentlyContinue
Remove-Item ($pairFat + ".new") -ErrorAction SilentlyContinue

$diagDir = Join-Path $ToolDir "diag"
if (-not [System.IO.Directory]::Exists($diagDir)) { New-Item -ItemType Directory -Path $diagDir | Out-Null }
[System.IO.File]::WriteAllText((Join-Path $diagDir ("append_" + $Tag + "_applied.txt")), ("applied " + (Get-Date -Format o) + " blob " + $blob.Length + " B sha16 " + $hb.Substring(0, 16)))
Write-Host ""
Write-Host ("OK: variant " + $Tag + " applied (append-mode, originals untouched).")
Write-Host "Start the game (keep Windows 7 compatibility mode ON), enter the world, note CRASH or OK."
