
# WD1 Archive Compare - byte-level compare of game archive vs reference (NGM original)
# ASCII only. Windows PowerShell 5.1 safe (long arithmetic everywhere).
param(
  [Parameter(Mandatory=$true)][string]$GameDir,
  [string]$RefDir = ""
)
$script:Version = "WD1 Archive Compare v1"
$TARGET = [long]2165723542   # car DB entry hash 81165196

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
function Get-EntrySha([System.IO.Stream]$ds, $e) {
  try { $buf = New-Object byte[] ([int]$e.comp) } catch { return "TOOBIG" }
  $ds.Position = $e.srcOff
  $n = $ds.Read($buf, 0, [int]$e.comp)
  if ($n -ne $e.comp) { return "READFAIL" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $h = $sha.ComputeHash($buf)
  $sha.Dispose()
  return (($h | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 16)
}
function Compare-Pair([string]$tag, [string]$gD, [string]$gF, [string]$rD, [string]$rF, [System.IO.StreamWriter]$rep) {
  $flG = [long]0; $rowsG = $null
  $flR = [long]0; $rowsR = $null
  Read-Fat $gF ([ref]$flG) ([ref]$rowsG)
  Read-Fat $rF ([ref]$flR) ([ref]$rowsR)
  Write-Host ("[" + $tag + "] game entries: " + $rowsG.Count + ", ref(NGM) entries: " + $rowsR.Count)
  $rep.WriteLine("")
  $rep.WriteLine("== pair " + $tag + " ==")
  $rep.WriteLine("game entries: " + $rowsG.Count + " (flags 0x" + $flG.ToString("X8") + ")  ref entries: " + $rowsR.Count + " (flags 0x" + $flR.ToString("X8") + ")")
  $mg = @{}
  foreach ($r in $rowsG) { $mg[[long]$r.hash] = $r }
  $mr = @{}
  foreach ($r in $rowsR) { $mr[[long]$r.hash] = $r }
  $onlyG = New-Object System.Collections.Generic.List[long]
  $onlyR = New-Object System.Collections.Generic.List[long]
  foreach ($k in $mg.Keys) { if (-not $mr.ContainsKey($k)) { $onlyG.Add($k) } }
  foreach ($k in $mr.Keys) { if (-not $mg.ContainsKey($k)) { $onlyR.Add($k) } }
  $rep.WriteLine("only in game: " + $onlyG.Count + "   only in ref: " + $onlyR.Count)
  foreach ($k in $onlyG) { if ($k -ne $TARGET) { $rep.WriteLine("  only-game " + ("{0:x8}" -f $k)) } }
  foreach ($k in $onlyR) { if ($k -ne $TARGET) { $rep.WriteLine("  only-ref  " + ("{0:x8}" -f $k)) } }
  $paramDiff = New-Object System.Collections.Generic.List[string]
  foreach ($k in $mg.Keys) {
    if (-not $mr.ContainsKey($k)) { continue }
    $g = $mg[$k]; $r = $mr[$k]
    if (($g.scheme -ne $r.scheme) -or ($g.comp -ne $r.comp) -or ($g.unc -ne $r.unc)) {
      $paramDiff.Add(("  {0:x8} game(scheme {1},comp {2},unc {3}) ref(scheme {4},comp {5},unc {6})" -f $k, $g.scheme, $g.comp, $g.unc, $r.scheme, $r.comp, $r.unc))
    }
  }
  $rep.WriteLine("fat param diffs (scheme/comp/unc): " + $paramDiff.Count)
  foreach ($l in $paramDiff) { if ($l -ne $null) { $rep.WriteLine($l) } }
  $same = 0; $diff = 0
  $diffList = New-Object System.Collections.Generic.List[string]
  $done = 0
  $dsG = [System.IO.File]::OpenRead($gD)
  $dsR = [System.IO.File]::OpenRead($rD)
  try {
    foreach ($r in $rowsG) {
      $k = $r.hash
      if (-not $mr.ContainsKey($k)) { continue }
      $rr = $mr[$k]
      $sG = Get-EntrySha $dsG $r
      $sR = Get-EntrySha $dsR $rr
      if (($sG -eq $sR) -and ($sG -ne "READFAIL") -and ($sG -ne "TOOBIG")) { $same = $same + 1 }
      else {
        $diff = $diff + 1
        if ($diffList.Count -lt 40) { $diffList.Add(("  {0:x8} game sha16 {1} ref sha16 {2}" -f $k, $sG, $sR)) }
      }
      if ($k -eq $TARGET) { $rep.WriteLine("car DB 81165196: game sha16 " + $sG + " ref sha16 " + $sR) }
      $done = $done + 1
      if (($done % 500) -eq 0) { Write-Host ("  compared " + $done + " entries ...") }
    }
  } finally { $dsG.Close(); $dsR.Close() }
  $rep.WriteLine("content: identical " + $same + " / differ " + $diff)
  foreach ($l in $diffList) { $rep.WriteLine($l) }
  if (($onlyG.Count -eq 0) -and ($onlyR.Count -eq 0) -and ($paramDiff.Count -eq 0) -and ($diff -eq 0)) {
    $rep.WriteLine("VERDICT " + $tag + ": GAME ARCHIVE == NGM ORIGINAL 100% (container writer cleared)")
    Write-Host ("[" + $tag + "] VERDICT: 100% IDENTICAL - container writer cleared.")
  } else {
    $rep.WriteLine("VERDICT " + $tag + ": DIFFERENCES FOUND (see above - container bug or version mismatch)")
    Write-Host ("[" + $tag + "] VERDICT: DIFFERENCES FOUND.")
  }
}
$GameDir = Clean-PathArg $GameDir
$RefDir = Clean-PathArg $RefDir
Write-Host ("=== " + $script:Version + " ===")
if ($RefDir -eq "") { throw "RefDir (folder with the ORIGINAL NGM patch.dat/patch.fat) is required" }
$gD = Join-Path $GameDir "patch.dat"; $gF = Join-Path $GameDir "patch.fat"
$rD = Join-Path $RefDir "patch.dat";  $rF = Join-Path $RefDir "patch.fat"
foreach ($f in @($gD, $gF, $rD, $rF)) {
  if (-not [System.IO.File]::Exists($f)) { throw ("missing file: " + $f) }
}
$repPath = Join-Path $PSScriptRoot "compare_report.txt"
$rep = New-Object System.IO.StreamWriter($repPath, $false)
try {
  $rep.WriteLine("# generated by " + $script:Version + " " + (Get-Date -Format o))
  $rep.WriteLine("game dir: " + $GameDir)
  $rep.WriteLine("ref  dir: " + $RefDir)
  Compare-Pair "patch" $gD $gF $rD $rF $rep
  $g1D = Join-Path $GameDir "patch1.dat"; $g1F = Join-Path $GameDir "patch1.fat"
  $r1D = Join-Path $RefDir "patch1.dat";  $r1F = Join-Path $RefDir "patch1.fat"
  $hasG1 = ([System.IO.File]::Exists($g1D) -and [System.IO.File]::Exists($g1F))
  $hasR1 = ([System.IO.File]::Exists($r1D) -and [System.IO.File]::Exists($r1F))
  if ($hasG1 -and $hasR1) { Compare-Pair "patch1" $g1D $g1F $r1D $r1F $rep }
  else { $rep.WriteLine("== pair patch1 == skipped (game:" + $hasG1 + " ref:" + $hasR1 + ")") }
} finally { $rep.Close() }
Write-Host ""
Write-Host ("report written: " + $repPath)
Write-Host "Upload compare_report.txt to GitHub main. That is all the agent needs."
