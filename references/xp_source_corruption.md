# Source-file corruption diagnostics (V 0.5.x)

Reusable recipe for when `v vet`/`v` throws a baffling error at a line that looks
syntactically fine. The real cause is usually a corrupted `.v` file, not a logic bug.

## Symptoms
- `error: this number has unsuitable digit 'c'` pointing at a literal `new_string`
  or `old_string` token embedded in the file.
- `error: expecting '('` / `unexpected name X` at a function that looks correct —
  a cascade from a missing/extra brace earlier, where the parser lost scope tracking.
- The same error moves around as you "fix" unrelated lines (sign of a scoping break
  upstream, not the flagged line).

## Diagnostic commands (plain shell, from project root)
```bash
# 1) Leftover patch/edit markers inside the .v file (any hit = corruption)
grep -n -e 'new_string' -e 'old_string' -e '^@@' agent/webstore.v

# 2) Brace balance — open must equal close
awk '{o+=gsub(/{/,"{");c+=gsub(/}/,"}")} END{print "open="o" close="c}' agent/webstore.v

# 3) Localize the brace break: print depth per line, find where it first
#    goes unexpectedly negative or fails to return to 0 at EOF
awk '{d+=gsub(/{/,"{")-gsub(/}/,"}"); print NR": depth="d}' agent/webstore.v

# 4) Hidden / non-ASCII bytes in a suspect region (clean V is pure ASCII)
sed -n '70,90p' agent/webstore.v | cat -A
sed -n '73,84p' agent/webstore.v | hexdump -C
```

## Fix pattern
- Delete the stray `new_string`/`old_string`/`@@ ... @@` line (it is not code).
- Re-add the missing `}` (or remove the extra one) at the depth transition found in step 3.
- Re-run `v vet .` (NOT just `v .`) — vet reports the first/nearest error, which is
  closest to the true cause; a full `v .` cascades and may point at a later line,
  misleading the fix.

## Real example (vaiv webstore.v, 2026-07-12)
A malformed edit left `new_string` on line 82 AND dropped the `}` closing `role_str`.
Result: `v vet` reported `error: this number has unsuitable digit 'c'` at the marker,
then after removing it, `error: expecting '('` at `parse_role` (because the missing `}`
made the parser think `parse_role` was still inside `role_str`'s block). Both found
via the grep + brace-scan above; fixed by re-adding the `}` and removing the marker.
