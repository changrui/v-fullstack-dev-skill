# go2v Workflow (reference for v-go2v-port)

## Install (verified 2026-07-16, V 0.5.x, go1.22.2)

```bash
# go2v is a V program; it calls the Go tool `asty` to emit a Go AST JSON.
git clone https://github.com/vlang/go2v /tmp/go2v
cd /tmp/go2v
~/v/v .                      # builds ./go2v binary (~2.6MB)

# asty auto-installs on first run, but default GOPROXY times out on some nets:
export PATH=$PATH:/home/iqdo/go/bin
GOPROXY=direct go install github.com/asty-org/asty@latest
# verify:
ls -la /home/iqdo/go/bin/asty
```

## Usage

```bash
# Translate ONE .go FILE -> writes <samebasename>.v next to it.
/tmp/go2v/go2v /abs/path/to/file.go

# WRONG: passing a directory triggers test-compare mode that needs a
# <dir>/<name>.vv expected-output file (CI path). Avoid for ad-hoc ports.
/tmp/go2v/go2v /some/dir/     # don't do this
```

- go2v writes `.v` beside the `.go` (same directory). Move it into your V module tree
  (`vlib/<mod>/<file>.v`) afterward.
- `v -translated-go` mode exists but provides NO compat shims for the broken stdlib
  mappings — don't rely on it to "fix" the table below.

## Batch port recipe (covonaut 8-leaf batch, 2026-07)

```bash
cd /home/iqdo/covonaut
export PATH=$PATH:/home/iqdo/go/bin
cd /tmp/go2v
for f in \
  /home/iqdo/covonaut/fuzzy/fuzzy.go \
  /home/iqdo/covonaut/pkg/util/util.go \
  /home/iqdo/covonaut/prompt/prompt.go \
  /home/iqdo/covonaut/skill/frontmatter.go \
  /home/iqdo/covonaut/skill/skill.go \
  /home/iqdo/covonaut/filequeue/filequeue.go \
  /home/iqdo/covonaut/components/doc.go ; do
  ./go2v "$f"
done
# -> writes .v next to each .go; then move into vlib_demo/<mod>/
```

## Real results table (covonaut, what actually happened)

| Module | LOC | go2v gen | Final | Fixes needed | Method |
|--------|-----|----------|-------|--------------|--------|
| fuzzy | 168 | yes | PASS (-prod + run assert) | 4 stdlib (grow/trim_right_func/replace/swap) | go2v + patch |
| util (pkg/util) | 41 | yes | PASS | 1 (err.error_()->err.str()) | go2v + patch |
| filequeue | 100 | yes but sync/os/path all wrong | PASS (run assert) | ~full rewrite | go2v ref + native |
| components | 44 | yes but context/Any wrong | PASS | rewrite interfaces (drop context/any) | go2v ref + V-style |
| skill/frontmatter | 541 | yes but regex/bufio wrong | NOT DONE (290-line state machine) | needs native rewrite | deferred |
| prompt | 96 | — | BLOCKED (imports agentcore) | needs agentcore first | C-class |
| store | 108 | — | BLOCKED (imports agentcore) | needs agentcore first | C-class |
| workflow | 110 | — | BLOCKED (imports agentcore) | needs agentcore first | C-class |

Lesson: of 8 "leaves", only 5 were truly independent; 3 imported the unported
`agentcore` core. Always `grep` internal imports before claiming leaf status.

## Effort reality
- 5 portables took ~2-3h wall-clock incl. debugging (go2v saved skeleton typing).
- The 65k-LOC whole project is dominated by agentcore(7.8k, 330 context refs),
  tools(15k, 352 any), mcp(3.3k, 224 context), tui(18k terminal UI) — go2v does
  NOT reduce that semantic cost. Recommend V-native rewrite of the architecture
  core, go2v only for leaf utils.
