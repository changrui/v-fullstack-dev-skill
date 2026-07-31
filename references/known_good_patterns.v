// known_good_patterns.v — copy-paste-corrected V idioms for Go→V ports.
// Every pattern below compiles under V 0.5.x and replaces a go2v-mangled emit.
// These are meant to be COPIED and ADAPTED, not compiled as-is.

module example

import strings
import os
import sync

// 1) strings.Builder with pre-size (go2v emits Builder{}+.grow — WRONG)
fn build_demo(s string) string {
	mut b := strings.new_builder(s.len) // pre-size, no .grow()
	for r in s {
		b.write_rune(r)
	}
	return b.str()
}

// 2) first-only replace (go2v emits s.replace(a,b,1) — V has no 3rd arg)
fn replace_first(s string, old string, new string) string {
	idx := s.index(old) or { -1 }
	if idx >= 0 {
		return s[..idx] + new + s[idx + old.len..]
	}
	return s
}

// 3) array swap (go2v emits a, b = b, a — forbidden in V)
fn swap_demo(mut a []i64, mut b []i64) {
	mut t := a.clone()
	a = b.clone()
	b = t
}

// 4) error to string (go2v emits err.error_() — DNE)
fn err_to_str(err IError) string {
	if isnil(err) {
		return ''
	}
	return err.str()
}

// 5) per-path reference-counted mutex map (go2v emits sync.Mutex.lock_() —
//    wrong; also botches map-of-ref + closure capture)
struct FileLock {
mut:
	mu   sync.Mutex
	refs int
}

pub struct FileMutationQueue {
mut:
	mu     sync.Mutex
	queues map[string]&FileLock
}

pub fn new() &FileMutationQueue {
	return &FileMutationQueue{ queues: map[string]&FileLock{} }
}

// Inline the lock/unlock + IO; do NOT use a closure to return a value out —
// V closure capture [mut x] is copy semantics for scalars.
pub fn (mut fmq FileMutationQueue) read_file_safe(path string) !string {
	key := os.abs_path(path)
	fmq.mu.lock()
	mut l := &FileLock{}
	if key in fmq.queues {
		l = fmq.queues[key]
	} else {
		l = &FileLock{}
		fmq.queues[key] = l
	}
	l.refs++
	fmq.mu.unlock()

	l.mu.lock()
	content := os.read_file(path) or { l.mu.unlock(); return err }
	l.mu.unlock()

	fmq.mu.lock()
	l.refs--
	if l.refs <= 0 {
		fmq.queues.delete(key)
	}
	fmq.mu.unlock()
	return content
}

// 6) write bytes (go2v emits os.write_file(p, data) with []u8 — 2nd arg is string)
pub fn (mut fmq FileMutationQueue) write_file_safe(path string, data []u8) ! {
	os.mkdir_all(os.dir(path), os.MkdirParams{}) or {}
	os.write_file(path, data.bytestr()) or { return err }
}

// 7) no context.Context — drop the param; if cancellation is needed, model it
//    with a `chan bool` / `select` + a flag. Go `func f(ctx context.Context)`
//    becomes plain `fn f()`.
// 8) map[string]any → map[string]json2.Any (import x.json2). For typed data
//    prefer a concrete struct or sum type over `any`.
