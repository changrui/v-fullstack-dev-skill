#!/usr/bin/env bash
# classify_modules.sh — scan a Go repo and score each module's Go→V port difficulty.
# Run this BEFORE porting to decide the A/B/C strategy (see SKILL.md "TL;DR
# decision rule"). Output is a per-module table: LOC + signal counts + class.
#
# Usage:  bash classify_modules.sh [repo_root]
#   repo_root defaults to the current directory.
#
# Class legend:
#   A (go2v)    — pure logic, no context/sync/os-path/regex/bufio → run go2v, patch 1-4 spots
#   B (rewrite) — has any of those signals → native rewrite is faster than patching go2v output
#   C (dep)     — imports an unported internal module → block until that dep is ported
set -u

ROOT="${1:-.}"
cd "$ROOT" || exit 1

printf "%-34s %6s %5s %5s %5s %6s  %s\n" "module" "loc" "ctx" "any" "sync" "ospath" "class"
printf "%-34s %6s %5s %5s %5s %6s  %s\n" "------" "---" "---" "---" "----" "------" "-----"

for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    loc=$(find "$d" -name '*.go' -not -name '*_test.go' 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
    [ "$loc" = "" ] && loc=0
    ctx=$(grep -rE 'context\.(Context|Background|With)' "$d" --include='*.go' 2>/dev/null | wc -l)
    any=$(grep -rE '\bany\b' "$d" --include='*.go' 2>/dev/null | wc -l)
    sync=$(grep -rE 'sync\.(Mutex|WaitGroup)|go func' "$d" --include='*.go' 2>/dev/null | wc -l)
    ospath=$(grep -rE 'path/filepath|"os"|"bufio"|"regexp"' "$d" --include='*.go' 2>/dev/null | wc -l)
    # detect internal-module imports that would block an independent port
    deps=$(grep -rhoE "covoyage/covonaut/[a-zA-Z_]+" "$d" --include='*.go' 2>/dev/null \
           | grep -v "covoyage/covonaut/$name" | sort -u | wc -l)

    if [ "$deps" -gt 0 ]; then
        class="C (dep)"
    elif [ "$ctx" = "0" ] && [ "$any" = "0" ] && [ "$sync" = "0" ] && [ "$ospath" = "0" ]; then
        class="A (go2v)"
    else
        class="B (rewrite)"
    fi
    printf "%-34s %6s %5s %5s %5s %6s  %s\n" "$name" "$loc" "$ctx" "$any" "$sync" "$ospath" "$class"
done
