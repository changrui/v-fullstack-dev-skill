# classify_modules.ps1 — Windows equivalent of classify_modules.sh
# Scan a Go repo and score each module's Go->V port difficulty.
# Run this BEFORE porting to decide the A/B/C strategy.
#
# Usage:  powershell -File classify_modules.ps1 [repo_root]
#   repo_root defaults to the current directory.
#
# Class legend:
#   A (go2v)    — pure logic, no context/sync/os-path/regex/bufio
#   B (rewrite) — has any of those signals -> native rewrite is faster
#   C (dep)     — imports an unported internal module -> block until that dep is ported

param([string]$Root = ".")

$Root = (Resolve-Path $Root).Path
$fmt = "{0,-34} {1,6} {2,5} {3,5} {4,5} {5,6}  {6}"
Write-Host ($fmt -f "module", "loc", "ctx", "any", "sync", "ospath", "class")
Write-Host ($fmt -f "------", "---", "---", "---", "----", "------", "-----")

Get-ChildItem -Path $Root -Directory | ForEach-Object {
    $name = $_.Name
    $dir = $_.FullName

    $goFiles = Get-ChildItem -Path $dir -Filter '*.go' -Recurse `
        | Where-Object { $_.Name -notlike '*_test.go' }
    $loc = 0
    $goFiles | ForEach-Object { $loc += (Get-Content $_.FullName | Measure-Object -Line).Lines }

    $allCode = ""
    $goFiles | ForEach-Object { $allCode += (Get-Content $_.FullName -Raw) + "`n" }

    $ctx    = [regex]::Matches($allCode, 'context\.(Context|Background|With)').Count
    $any    = [regex]::Matches($allCode, '\bany\b').Count
    $sync   = [regex]::Matches($allCode, 'sync\.(Mutex|WaitGroup)|go func').Count
    $ospath = [regex]::Matches($allCode, 'path/filepath|"os"|"bufio"|"regexp"').Count

    $deps = 0
    $matches = [regex]::Matches($allCode, 'covoyage/covonaut/([a-zA-Z_]+)')
    $depNames = @{}
    $matches | ForEach-Object {
        if ($_.Groups[1].Value -ne $name) { $depNames[$_.Groups[1].Value] = $true }
    }
    $deps = $depNames.Count

    if ($deps -gt 0) {
        $class = "C (dep)"
    } elseif ($ctx -eq 0 -and $any -eq 0 -and $sync -eq 0 -and $ospath -eq 0) {
        $class = "A (go2v)"
    } else {
        $class = "B (rewrite)"
    }

    Write-Host ($fmt -f $name, $loc, $ctx, $any, $sync, $ospath, $class)
}
