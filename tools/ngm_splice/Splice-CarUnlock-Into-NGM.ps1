# Splice-CarUnlock-Into-NGM.ps1  v2.4
# WD1 car-unlock splicer + localization data collector.
# Phase A (read-only) -> Phase B (replace) -> probe (non-fatal).
param(
  [Parameter(Mandatory=$true)][string]$DataDir,
  [string]$BlobPath = "",
  [string]$ToolDir = ""
)

$ErrorActionPreference = "Stop"

function Clean-PathArg([string]$p) {
  if ($null -eq $p) { return "" }
  $p = $p.Trim()
  $p = $p.Trim('"')
  while ($p.EndsWith("\")) { $p = $p.Substring(0, $p.Length - 1) }
  return $p
}
$DataDir = Clean-PathArg $DataDir
$ToolDir = Clean-PathArg $ToolDir
$BlobPath = Clean-PathArg $BlobPath
if ($ToolDir -eq "") {
  if ($PSScriptRoot) { $ToolDir = $PSScriptRoot }
  else { $ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
}
if ($BlobPath -eq "") { $BlobPath = Join-Path $ToolDir "car_db_81165196.bin" }

# NOTE: Windows PowerShell 5.1 parses hex literals >= 0x80000000 as Int32.
# Always use decimal forms here.
$TARGET = [long]2165723542   # 0x81165196 (car DB entry name hash)
$MASK32 = [long]4294967295   # 0xFFFFFFFF
$script:SplicerVersion = "v2.9-cleanbase"
$script:BUF = New-Object byte[] 8388608
$script:ExportCount = 0
$script:ExportBytes = [long]0
$script:MaxExportFiles = 500
$script:MaxExportBytes = [long]629145600

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

function Copy-Slice([System.IO.Stream]$src, [long]$srcOff, [System.IO.Stream]$dst, [long]$len) {
  $src.Position = $srcOff
  while ($len -gt 0) {
    $take = $script:BUF.Length
    if ($take -gt $len) { $take = $len }
    $n = $src.Read($script:BUF, 0, [int]$take)
    if ($n -le 0) { throw "unexpected end of data" }
    $dst.Write($script:BUF, 0, $n)
    $len = $len - $n
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

function Load-HashList([string]$path) {
  $set = @{}
  if ([System.IO.File]::Exists($path)) {
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
      $t = $line.Trim()
      if ($t -eq "" -or $t.StartsWith("#")) { continue }
      $set[[uint32]([Convert]::ToUInt32($t, 16))] = $true
    }
  }
  return $set
}

function Export-DiffPayloads {
  param(
    [string]$datPath, [string]$fatPath, [string]$manifestPath,
    [string]$outDir, [string]$pairName,
    [hashtable]$CjkSet, [hashtable]$RequestSet,
    [System.IO.StreamWriter]$csv
  )
  $van = @{}
  if ([System.IO.File]::Exists($manifestPath)) {
    foreach ($line in [System.IO.File]::ReadAllLines($manifestPath)) {
      if ($line.StartsWith("#") -or $line.Trim() -eq "") { continue }
      $p = $line.Split(",")
      $van[[uint32]([Convert]::ToUInt32($p[0], 16))] = @([long]$p[1], [long]$p[2], [long]$p[3])
    }
  } else {
    Write-Host ("  (no vanilla manifest for " + $pairName + " - export skipped)")
    return
  }
  $fl = [long]0
  $rows = $null
  Read-Fat $fatPath ([ref]$fl) ([ref]$rows)
  $ds = [System.IO.File]::OpenRead($datPath)
  $diffs = 0
  try {
    foreach ($r in $rows) {
      $key = [uint32]($r.hash -band $MASK32)
      $reason = ""
      if (-not $van.ContainsKey($key)) { $reason = "EXTRA" }
      else {
        $v = $van[$key]
        if ($v[0] -ne $r.scheme -or $v[1] -ne $r.comp -or $v[2] -ne $r.unc) { $reason = "DIFF" }
      }
      if ($reason -eq "") { continue }
      $diffs++
      $magic = ""
      if ($r.comp -ge 4) {
        $mb = New-Object byte[] 4
        $ds.Position = $r.srcOff
        $null = $ds.Read($mb, 0, 4)
        $magic = [System.Text.Encoding]::ASCII.GetString($mb)
      }
      $csv.WriteLine($pairName + "," + $reason + "," + $key.ToString("x8") + "," + $r.scheme + "," + $r.comp + "," + $r.unc + "," + $magic)

      $isCjk = $CjkSet.ContainsKey($key)
      $requested = $RequestSet.ContainsKey($key)
      $isCar = ($key -eq [uint32]2165723542)
      $textMagic = ($magic -eq "nbCF" -or $magic -like "UEF*" -or $magic -like "SL*" -or $magic -eq "DDS " -or $magic -eq ("TBX" + [char]0))
      $want = $requested -or $isCjk -or ($textMagic -and $r.comp -le 25165824) -or ($r.comp -le 524288 -and -not $isCar)
      if (-not $want) { continue }
      if ($script:ExportCount -ge $script:MaxExportFiles) { $csv.WriteLine("SKIPCAP,files," + $key.ToString("x8")); continue }
      if ($script:ExportBytes + $r.comp -gt $script:MaxExportBytes) { $csv.WriteLine("SKIPCAP,bytes," + $key.ToString("x8")); continue }
      $name = $outDir + "\" + $pairName + "_" + $key.ToString("x8") + "_" + $r.comp + ".bin"
      $out = [System.IO.File]::Create($name)
      try { Copy-Slice $ds $r.srcOff $out $r.comp } finally { $out.Close() }
      $script:ExportCount++
      $script:ExportBytes = $script:ExportBytes + $r.comp
      if (($script:ExportCount % 25) -eq 0) {
        Write-Host ("  exported " + $script:ExportCount + " files, " + [Math]::Round($script:ExportBytes / 1MB) + " MB ...")
      }
    }
  } finally { $ds.Close() }
  Write-Host ("  " + $pairName + ": " + $diffs + " changed entries vs vanilla")
}

function Process-Pair([string]$datPath, [string]$fatPath, [byte[]]$blob, [string]$toolDir, [switch]$Force) {
  $fl = [long]0
  $rows = $null
  Read-Fat $fatPath ([ref]$fl) ([ref]$rows)
  Write-Host ("  " + (Split-Path -Leaf $fatPath) + ": " + $rows.Count + " entries, flags 0x" + $fl.ToString("X8"))

  foreach ($stale in @(($datPath + ".new"), ($fatPath + ".new"))) {
    if ([System.IO.File]::Exists($stale)) {
      [System.IO.File]::Delete($stale)
      Write-Host ("  removed stale temp: " + (Split-Path -Leaf $stale))
    }
  }

  # ================= PHASE A: read-only =================
  $datStream = [System.IO.File]::OpenRead($datPath)
  $skipSwap = $false
  try {
    $idx = -1
    for ($i = 0; $i -lt $rows.Count; $i++) {
      if ($rows[$i].hash -eq $TARGET) { $idx = $i; break }
    }
    if ($idx -lt 0) {
      Write-Host "  target entry not present -> will insert (sorted)"
    } else {
      $e = $rows[$idx]
      $payloadPath = Join-Path $toolDir "ngm_81165196_payload.bin"
      $sl = New-Object byte[] ([int]$e.comp)
      $datStream.Position = $e.srcOff
      $null = $datStream.Read($sl, 0, [int]$e.comp)
      $same = ($e.scheme -eq 0 -and $e.comp -eq $blob.Length)
      if ($same) {
        for ($i = 0; $i -lt $blob.Length; $i++) {
          if ($sl[$i] -ne $blob[$i]) { $same = $false; break }
        }
      }
      if ($same -and -not $Force) {
        Write-Host "  target entry ALREADY equals the merged blob -> splice skipped (nothing to replace)."
        $skipSwap = $true
        if ([System.IO.File]::Exists($payloadPath)) {
          $cur = [System.IO.File]::ReadAllBytes($payloadPath)
          $sameP = ($cur.Length -eq $blob.Length)
          if ($sameP) {
            for ($i = 0; $i -lt $blob.Length; $i++) {
              if ($cur[$i] -ne $blob[$i]) { $sameP = $false; break }
            }
          }
          if ($sameP) {
            Write-Host "  (kept your existing ngm_81165196_payload.bin - it is the original NGM data)"
          } else {
            [System.IO.File]::WriteAllBytes($payloadPath, $sl)
          }
        }
      } else {
        [System.IO.File]::WriteAllBytes($payloadPath, $sl)
        Write-Host ("  NOTE: target entry EXISTS (scheme " + $e.scheme + ", " + $e.comp + " B). Saved -> " + $payloadPath)
      }
    }

    if (-not $skipSwap) {
      $newRows = New-Object System.Collections.Generic.List[object]
      $replaced = $false
      foreach ($r in $rows) {
        if ($r.hash -eq $TARGET) {
          $newRows.Add(@{ "hash" = $r.hash; "unc" = [long]$blob.Length; "scheme" = [long]0; "comp" = [long]$blob.Length; "srcOff" = [long]0; "isTarget" = $true })
          $replaced = $true
        } else {
          $newRows.Add(@{ "hash" = $r.hash; "unc" = $r.unc; "scheme" = $r.scheme; "comp" = $r.comp; "srcOff" = $r.srcOff; "isTarget" = $false })
        }
      }
      if (-not $replaced) {
        $ins = $newRows.Count
        for ($i = 0; $i -lt $newRows.Count; $i++) {
          if ($newRows[$i].hash -gt $TARGET) { $ins = $i; break }
        }
        $newRows.Insert($ins, @{ "hash" = $TARGET; "unc" = [long]$blob.Length; "scheme" = [long]0; "comp" = [long]$blob.Length; "srcOff" = [long]0; "isTarget" = $true })
        Write-Host ("  target absent -> inserted at position " + $ins + " (sorted)")
      }
      $cur = [long]0
      foreach ($r in $newRows) { $r["newOff"] = $cur; $cur = $cur + $r["comp"] }
      $newSize = $cur

      $tmpDat = $datPath + ".new"
      $out = [System.IO.File]::Create($tmpDat)
      try {
        foreach ($r in $newRows) {
          if ($r["isTarget"]) { $out.Write($blob, 0, $blob.Length) }
          else { Copy-Slice $datStream $r["srcOff"] $out $r["comp"] }
        }
      } finally { $out.Close() }

      $tmpFat = $fatPath + ".new"
      $ms = New-Object System.IO.MemoryStream
      $bw = New-Object System.IO.BinaryWriter($ms)
      $bw.Write([byte[]]@(0x33,0x54,0x41,0x46))
      $bw.Write([uint32]8)
      $bw.Write([uint32]$fl)
      $bw.Write([uint32]$newRows.Count)
      foreach ($r in $newRows) {
        $bw.Write([uint32]($r["hash"] -band $MASK32))
        $bw.Write([uint32](((($r["unc"] -band 0x1FFFFFFF) -shl 3) -bor ($r["scheme"] -band 7))))
        $bw.Write([uint32](((($r["newOff"] -band 7) -shl 29) -bor ($r["comp"] -band 0x1FFFFFFF))))
        $bw.Write([uint32][Math]::Floor($r["newOff"] / 8))
      }
      $bw.Write([uint32]0)
      $bw.Flush()
      [System.IO.File]::WriteAllBytes($tmpFat, $ms.ToArray())
      $bw.Close()

      $fl2 = [long]0
      $rows2 = $null
      Read-Fat $tmpFat ([ref]$fl2) ([ref]$rows2)
      if ($rows2.Count -ne $newRows.Count) { throw "verify: entry count mismatch" }
      for ($i = 0; $i -lt $rows2.Count; $i++) {
        if ($rows2[$i].hash -ne $newRows[$i].hash) { throw ("verify: order mismatch at " + $i) }
        if ($rows2[$i].comp -ne $newRows[$i].comp) { throw ("verify: comp mismatch at " + $i) }
      }
      $nd = [System.IO.File]::OpenRead($tmpDat)
      try {
        foreach ($r in $rows2) {
          if ($r.srcOff + $r.comp -gt $newSize) { throw "verify: entry exceeds dat size" }
        }
        $t = $null
        foreach ($r in $rows2) { if ($r.hash -eq $TARGET) { $t = $r; break } }
        if ($null -eq $t) { throw "verify: target missing" }
        $back = New-Object byte[] $blob.Length
        $nd.Position = $t.srcOff
        $null = $nd.Read($back, 0, $blob.Length)
        for ($i = 0; $i -lt $blob.Length; $i++) {
          if ($back[$i] -ne $blob[$i]) { throw ("verify: target payload mismatch at byte " + $i) }
        }
      } finally { $nd.Close() }
      Write-Host "  phase A done: .new files built and verified."
    }
  } finally {
    $datStream.Close()
  }

  if ($skipSwap) {
    Write-Host "  splice: skipped (already applied earlier)."
    return
  }

  # ================= PHASE B: replace (no handles held) =================
  foreach ($f in @($datPath, $fatPath)) {
    $holders = Test-FileLock $f 5 1500
    if ($null -ne $holders) {
      Write-Host ""
      Write-Host ("LOCKED: " + $f)
      if ($holders.Count -gt 0) {
        Write-Host ("  these processes are still running: " + ($holders -join ", "))
      } else {
        Write-Host "  no game/steam process found; likely antivirus scanning."
      }
      Write-Host "  -> Close the game (check Task Manager for WatchDogs.exe) and run again. Originals untouched."
      throw ("file is locked: " + $f)
    }
  }

  foreach ($f in @($datPath, $fatPath)) {
    $bak = $f + ".carbak"
    if (-not [System.IO.File]::Exists($bak)) { Copy-Item $f $bak }
  }

  $datOk = Copy-WithRetry ($datPath + ".new") $datPath
  if (-not $datOk) {
    Write-Host "  patch.dat was NOT changed. Originals are intact."
    throw "could not replace patch.dat after 4 attempts"
  }
  $fatOk = Copy-WithRetry ($fatPath + ".new") $fatPath
  if (-not $fatOk) {
    Write-Host "  patch.fat replace failed - rolling back patch.dat from .carbak ..."
    $ok = Copy-WithRetry ($datPath + ".carbak") $datPath
    if ($ok) { Write-Host "  patch.dat restored. Nothing was changed - safe to re-run." }
    else { Write-Host "  !!! automatic restore failed. Manually copy patch.dat.carbak over patch.dat !!!" }
    throw "could not replace patch.fat; rolled back."
  }

  Remove-Item ($datPath + ".new") -ErrorAction SilentlyContinue
  Remove-Item ($fatPath + ".new") -ErrorAction SilentlyContinue
  Write-Host ("  OK: " + (Split-Path -Leaf $datPath) + " replaced (backups: *.carbak)")
}

function Write-ManifestDiff([string]$pairName, [string]$fatPath, [string]$manifestPath, [System.IO.StreamWriter]$rep) {
  $fl = [long]0
  $rows = $null
  Read-Fat $fatPath ([ref]$fl) ([ref]$rows)
  $van = @{}
  if ([System.IO.File]::Exists($manifestPath)) {
    foreach ($line in [System.IO.File]::ReadAllLines($manifestPath)) {
      if ($line.StartsWith("#") -or $line.Trim() -eq "") { continue }
      $p = $line.Split(",")
      $van[[uint32]([Convert]::ToUInt32($p[0], 16))] = @([long]$p[1], [long]$p[2], [long]$p[3])
    }
  }
  $diffs = 0
  foreach ($r in $rows) {
    $key = [uint32]($r.hash -band $MASK32)
    if (-not $van.ContainsKey($key)) {
      $rep.WriteLine($pairName + " EXTRA " + $key.ToString("x8") + " scheme=" + $r.scheme + " comp=" + $r.comp + " unc=" + $r.unc)
      $diffs++
    } else {
      $v = $van[$key]
      if ($v[0] -ne $r.scheme -or $v[1] -ne $r.comp -or $v[2] -ne $r.unc) {
        $rep.WriteLine($pairName + " DIFF  " + $key.ToString("x8") + " scheme=" + $r.scheme + "/" + $v[0] + " comp=" + $r.comp + "/" + $v[1] + " unc=" + $r.unc + "/" + $v[2])
        $diffs++
      }
    }
  }
  Write-Host ("  manifest diff vs vanilla (" + $pairName + "): " + $diffs + " entries")
}

# ---- main: v2.9 clean-base bisect A -> B -> C -> D ----
# Round-3 discovery: the user's .carbak "NGM original" was polluted - its car DB
# entry was 1,101,571 B = the OLD v2.0-v2.6 merged blob (sha16 29ee5fbdd02083ce).
# Every v2.8 test therefore started from a merged base and crashed regardless of
# variant. v2.9 VERIFIES the base; if it is not the NGM native DB (1,075,943 B)
# it heals the archive by splicing the native DB in, then takes a fresh backup.
Write-Host ("=== WD1 Car-Unlock Splicer " + $script:SplicerVersion + " ===")

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

$diagDir = Join-Path $ToolDir "diag"
if (-not [System.IO.Directory]::Exists($diagDir)) { New-Item -ItemType Directory -Path $diagDir | Out-Null }

$counterPath = Join-Path $diagDir "v29_counter.txt"
$testIndex = 0
if ([System.IO.File]::Exists($counterPath)) { $testIndex = [int]([System.IO.File]::ReadAllText($counterPath).Trim()) }
if ($testIndex -gt 3) {
  Write-Host "All 4 v2.9 tests have been applied already."
  Write-Host "Upload the diag folder to GitHub main and report the 4 results (A/B/C/D = ok/crash)."
  return
}
$tests = @("A","B","C","D")
$test = $tests[$testIndex]
Write-Host ("=== BISECT TEST " + $test + " (step " + ($testIndex + 1) + " of 4) ===")

# --- step 1: the restore base (.carbak) MUST be the true NGM original ---
$bakDat = $pairDat + ".carbak"
$bakFat = $pairFat + ".carbak"
$baseOk = $false
if (([System.IO.File]::Exists($bakDat)) -and ([System.IO.File]::Exists($bakFat))) {
  $flB = [long]0
  $rowsB = $null
  Read-Fat $bakFat ([ref]$flB) ([ref]$rowsB)
  foreach ($r in $rowsB) {
    if ($r.hash -eq $TARGET) {
      Write-Host ("backup check: car DB in .carbak = " + $r.comp + " B (scheme " + $r.scheme + "); NGM native = 1075943 B")
      if (($r.scheme -eq 0) -and ($r.comp -eq 1075943)) { $baseOk = $true }
      break
    }
  }
}

$healed = $false
if (-not $baseOk) {
  if ($testIndex -ne 0) {
    throw "clean base lost after test A. Delete diag\v29_counter.txt and run again from test A."
  }
  Write-Host "!!! your .carbak backup is NOT the NGM original: it still contains an old merged car DB."
  Write-Host "!!! that is why every earlier test crashed - the base was never clean. Healing now ..."
  foreach ($f in @($bakDat, $bakFat)) {
    if ([System.IO.File]::Exists($f)) { Move-Item -Force $f ($f + ".poisoned26") }
  }
  $blob = [System.IO.File]::ReadAllBytes((Join-Path $ToolDir "blob_A_native.bin"))
  Write-Host ("heal: splicing NGM-native car DB (" + $blob.Length + " B) into the archive ...")
  Process-Pair $pairDat $pairFat $blob $ToolDir -Force
  $ok1 = Copy-WithRetry $pairDat $bakDat
  $ok2 = Copy-WithRetry $pairFat $bakFat
  if (-not ($ok1 -and $ok2)) { throw "could not write the fresh .carbak (locked? close the game)" }
  $healed = $true
  Write-Host "HEAL DONE: fresh clean .carbak written (old poisoned backups kept as *.carbak.poisoned26)."
}

if (-not $healed) {
  Write-Host "restoring clean NGM base from .carbak ..."
  $okD = Copy-WithRetry $bakDat $pairDat
  $okF = Copy-WithRetry $bakFat $pairFat
  if (-not ($okD -and $okF)) { throw "could not restore from .carbak (locked? close the game)" }
}

# --- step 2: apply the current test variant ---
$blob = $null
$variantPath = $null
if ($test -eq "A") {
  $variantPath = Join-Path $ToolDir "blob_A_native.bin"
  Write-Host "TEST A = NGM-native car DB written by my container writer (clean-base rebuild)."
} elseif ($test -eq "B") {
  $variantPath = Join-Path $ToolDir "blob_B_speed08.bin"
  Write-Host "TEST B = NGM + Speed_08 only."
} elseif ($test -eq "C") {
  $variantPath = Join-Path $ToolDir "blob_C_hidden44.bin"
  Write-Host "TEST C = NGM + 44 hidden-slot records (no Speed_08)."
} else {
  $variantPath = Join-Path $ToolDir "blob_D_full.bin"
  Write-Host "TEST D = NGM + 44 + Speed_08 (same content as v2.7)."
}
if (-not [System.IO.File]::Exists($variantPath)) { throw ("blob variant missing: " + $variantPath) }
$blob = [System.IO.File]::ReadAllBytes($variantPath)
Write-Host ("variant blob: " + $blob.Length + " B")

Write-Host "splicing variant into the archive ..."
Process-Pair $pairDat $pairFat $blob $ToolDir -Force

if ($test -eq "A") {
  $hNewD = Get-FileHash -Algorithm SHA256 $pairDat
  $hBakD = Get-FileHash -Algorithm SHA256 $bakDat
  $hNewF = Get-FileHash -Algorithm SHA256 $pairFat
  $hBakF = Get-FileHash -Algorithm SHA256 $bakFat
  $sameD = ($hNewD.Hash -eq $hBakD.Hash)
  $sameF = ($hNewF.Hash -eq $hBakF.Hash)
  Write-Host ("TEST A self-check: patch pair dat " + $(if ($sameD) { "IDENTICAL" } else { "DIFFERENT" }) + ", fat " + $(if ($sameF) { "IDENTICAL" } else { "DIFFERENT" }))
  if ($sameD -and $sameF) {
    Write-Host "container writer is byte-perfect on this archive; the A boot result measures CONTENT only."
  } else {
    Write-Host "!!! writer output differs from the clean base - report this to the agent."
  }
}

# diag artifacts for the GitHub push
Copy-Item $bakFat (Join-Path $diagDir "original_patch.fat") -Force
[System.IO.File]::WriteAllBytes((Join-Path $diagDir "applied_blob.bin"), $blob)
[System.IO.File]::WriteAllText((Join-Path $diagDir ("v29_test_" + $test + "_applied.txt")), ("applied " + (Get-Date -Format o)))
[System.IO.File]::WriteAllText($counterPath, [string]($testIndex + 1))

Write-Host ""
Write-Host ("=== TEST " + $test + " APPLIED. NOW: ===")
Write-Host "1. Start the game, load/create a save, enter the world."
Write-Host "2. Note the result: CRASH or OK (if the first boot crashes, try once more - NGM itself can be flaky)."
Write-Host "3. Run this tool again for the next test (A->B->C->D)."
if ($testIndex -eq 3) {
  Write-Host "That was the LAST test. Upload the whole diag folder to GitHub main and"
  Write-Host "report which tests crashed (e.g. A=ok B=ok C=crash D=crash)."
}
return

# ---- diagnostic: export CURRENT in-archive car DB ----
try {
  $diagDir = Join-Path $ToolDir "diag"
  if (-not [System.IO.Directory]::Exists($diagDir)) { New-Item -ItemType Directory -Path $diagDir | Out-Null }
  $diagDat = if ($usePatch1) { $p1Dat } else { $patchDat }
  $diagFat = if ($usePatch1) { $p1Fat } else { $patchFat }
  $fl = [long]0
  $rows = $null
  Read-Fat $diagFat ([ref]$fl) ([ref]$rows)
  $ds = [System.IO.File]::OpenRead($diagDat)
  try {
    foreach ($r in $rows) {
      if ($r.hash -eq $TARGET) {
        $cur = New-Object byte[] ([int]$r.comp)
        $ds.Position = $r.srcOff
        $null = $ds.Read($cur, 0, [int]$r.comp)
        [System.IO.File]::WriteAllBytes((Join-Path $diagDir "current_81165196_payload.bin"), $cur)
        $blobBytes = [System.IO.File]::ReadAllBytes($BlobPath)
        $same = ($r.comp -eq $blobBytes.Length)
        if ($same) {
          for ($i = 0; $i -lt $blobBytes.Length; $i++) {
            if ($cur[$i] -ne $blobBytes[$i]) { $same = $false; break }
          }
        }
        Write-Host ("DIAG: current car DB in archive = " + $r.comp + " B, identical-to-blob=" + $same)
        # hash both for reporting
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $h1 = ($sha.ComputeHash($cur) | ForEach-Object { $_.ToString("x2") }) -join ""
        $h2 = ($sha.ComputeHash($blobBytes) | ForEach-Object { $_.ToString("x2") }) -join ""
        Write-Host ("DIAG: sha256 current=" + $h1.Substring(0,16) + " blob=" + $h2.Substring(0,16))
        break
      }
    }
  } finally { $ds.Close() }
} catch {
  Write-Host ("diag export failed (non-fatal): " + $_.Exception.Message)
}

# ---- localization probe (NON-FATAL) ----
try {
  $expDir = Join-Path $ToolDir "exports"
  if (-not [System.IO.Directory]::Exists($expDir)) { New-Item -ItemType Directory -Path $expDir | Out-Null }
  $cjkP = Load-HashList (Join-Path $ToolDir "cjk_hashes_patch.txt")
  $cjk1 = Load-HashList (Join-Path $ToolDir "cjk_hashes_patch1.txt")
  $req = Load-HashList (Join-Path $ToolDir "export_these_hashes.txt")
  Write-Host ("localization probe: cjk patch=" + $cjkP.Count + " patch1=" + $cjk1.Count + " requested=" + $req.Count)
  $csvPath = Join-Path $expDir "index.csv"
  $csv = New-Object System.IO.StreamWriter($csvPath, $false)
  try {
    $csv.WriteLine("pair,reason,hash,scheme,comp,unc,magic")
    Export-DiffPayloads $patchDat $patchFat (Join-Path $ToolDir "vanilla_manifest_patch.txt") $expDir "patch" $cjkP $req $csv
    if ($hasPatch1) {
      Export-DiffPayloads $p1Dat $p1Fat (Join-Path $ToolDir "vanilla_manifest_patch1.txt") $expDir "patch1" $cjk1 $req $csv
    }
  } finally { $csv.Close() }
  Write-Host ("exports -> " + $expDir + "  (" + $script:ExportCount + " files, " + [Math]::Round($script:ExportBytes / 1MB) + " MB)")

  $repPath = Join-Path $ToolDir "ngm_diff_manifest.txt"
  $rep = New-Object System.IO.StreamWriter($repPath, $false)
  try {
    Write-ManifestDiff "patch" $patchFat (Join-Path $ToolDir "vanilla_manifest_patch.txt") $rep
    if ($hasPatch1) {
      Write-ManifestDiff "patch1" $p1Fat (Join-Path $ToolDir "vanilla_manifest_patch1.txt") $rep
    }
    $rep.WriteLine("# generated by Splice-CarUnlock-Into-NGM " + $script:SplicerVersion)
  } finally { $rep.Close() }
  Write-Host ("audit report -> " + $repPath)
} catch {
  Write-Host ("localization probe FAILED (non-fatal, splice is already applied): " + $_.Exception.Message)
}

Write-Host ""
Write-Host "=== ALL DONE ==="
Write-Host "1. Start the game and check the Car On Demand list (74 cars + police/madness)."
Write-Host "2. Upload to GitHub main branch (for the Chinese-restore pack):"
Write-Host "   - the exports\ folder (all files inside)"
Write-Host "   - ngm_diff_manifest.txt"
