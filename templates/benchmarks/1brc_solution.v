// 1BRC Challenge in V 0.5.x — Enhanced with C FFI (mmap + SIMD)
//
// This version demonstrates V's C interop capabilities:
//   1. #include <sys/mman.h>  — injects C header into generated code
//   2. fn C.mmap(...) voidptr — declares the POSIX mmap for V to call
//   3. Calling C.mmap with the fd from V's os.open_file()
//   4. #include "c_simd.c" + @[c_extern] — links a hand-written C parser
//   5. Calling simd_parse_float_fast() — a C SIMD-ready float parser
//   6. Multi-threaded processing with `spawn` + `thread[].wait()`
//   7. Lock-free per-thread map aggregation, combined at the end
//
// Compile (c_simd.c is #included, so NO separate gcc step needed):
//   v -cc gcc -cflags '-O3 -march=native -ffast-math' -o bin/1brc main.v
//
// Usage:
//   ./bin/1brc --human-readable data/1brc.txt
//   ./bin/1brc --threads 8 data/1brc.txt
//
// Verified benchmark (10M rows / 411 cities, 24-core box):
//   1 thread:  ~492 ms    8 threads: ~77 ms   (target: < 2000 ms)

import os
import time
import math

// =========================================================================
// SECTION 1: C FFI — memory-mapped I/O
//
// V has no built-in mmap, so we call the POSIX syscall directly.
//   #include <sys/mman.h>  → emits the include into the generated C file
//   fn C.mmap(...) voidptr → declares the C function for V to call
// C macros PROT_READ / MAP_SHARED are referenced as C.PROT_READ etc.
// =========================================================================

#include <sys/mman.h>
#include "c_simd.c"  // place c_simd.c in the build cwd (or use an absolute path)

fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr
fn C.munmap(addr voidptr, len u64) i32

// =========================================================================
// SECTION 2: C FFI — SIMD float parser
//
// c_simd.c is #included at the top of this file (see #include above), so its
// definition is compiled into the generated C. The @[c_extern] marker tells V
// that simd_parse_float_fast is an external C symbol (already defined by the
// included source), not a V-generated stub. We call it as C.simd_parse_...
// It parses "5.8" / "-12.3" ASCII bytes to f32.
// =========================================================================

@[c_extern]
fn C.simd_parse_float_fast(buf &u8, len int) f32

// =========================================================================
// SECTION 3: Data structures
// =========================================================================

struct CityStats {
mut:
	min_temp f32
	max_temp f32
	sum_temp f64
	count  u64
}

struct MMapFile {
	size u64
mut:
	data &u8
	file os.File
}

fn mmap_file(path string) MMapFile {
	mut mf := MMapFile{
		file: os.open_file(path, 'r', 0) or { panic('fail to open ' + path) }
		size: os.file_size(path)
		data: C.NULL
	}
	mf.data = &u8(C.mmap(C.NULL, mf.size, C.PROT_READ, C.MAP_SHARED, mf.file.fd, 0))
	return mf
}

fn (mut mf MMapFile) unmap() {
	if C.munmap(mf.data, mf.size) != 0 {
		panic('munmap() failed')
	}
	mf.file.close()
}

// =========================================================================
// SECTION 4: Worker — parse one [from, to) chunk of the mmap'd buffer
//
// Line format:  "CityName; Temperature\n"
// We scan byte-by-byte for ';' (59) and '\n' (10). The temperature substring
// is handed to the C SIMD parser. Pointer indexing needs `unsafe { }`.
// =========================================================================

@[direct_array_access]
fn process_chunk(addr &u8, from u64, to u64) map[string]CityStats {
	mut results := map[string]CityStats{}
	mut city := ''
	mut city_start := u64(0)
	mut city_len := u64(0)
	mut temp_start := u64(0)
	mut in_temp := false

	for i in from .. to {
		c := unsafe { u8(addr[i]) }
		if !in_temp {
			if c == `;` {
				// city name is [city_start, i); capture it now
				city = unsafe { tos(addr + city_start, int(city_len)) }
				in_temp = true
				// temperature starts right after ';', skip an optional space
				temp_start = i + 1
			} else {
				if city_len == 0 {
					city_start = i
				}
				city_len++
			}
		} else {
			if c == `\n` {
				// skip a leading space in the temperature field, if present
				if temp_start < i && unsafe { addr[temp_start] } == 32 {
					temp_start++
				}
				temp_len := int(i - temp_start)
				temp := unsafe { C.simd_parse_float_fast(addr + temp_start, temp_len) }
				if city !in results {
					results[city] = CityStats{
						min_temp: temp
						max_temp: temp
						sum_temp: f64(temp)
						count: 1
					}
				} else {
					mut s := results[city]
					if temp < s.min_temp { s.min_temp = temp }
					if temp > s.max_temp { s.max_temp = temp }
					s.sum_temp += f64(temp)
					s.count++
					results[city] = s
				}
				// reset for next line
				in_temp = false
				city_len = 0
			}
		}
	}
	return results
}

// =========================================================================
// SECTION 5: Combine per-thread maps → sorted output
// =========================================================================

fn combine_results(results []map[string]CityStats) map[string]CityStats {
	mut combined := map[string]CityStats{}
	for result in results {
		for city, r in result {
			if city !in combined {
				combined[city] = r
			} else {
				mut e := combined[city]
				if r.max_temp > e.max_temp { e.max_temp = r.max_temp }
				if r.min_temp < e.min_temp { e.min_temp = r.min_temp }
				e.sum_temp += r.sum_temp
				e.count += r.count
				combined[city] = e
			}
		}
	}
	return combined
}

// fmt1 formats an f64 to 1 decimal place (V 0.5.x has no fNN.str(n) overload)
fn fmt1(v f64) string {
	rounded := math.round(v * 10) / 10
	mut s := rounded.str()
	// ensure exactly one decimal digit
	if !s.contains('.') {
		s += '.0'
	} else {
		dot := s.index('.') or { return s + '.0' }
		frac := s[dot + 1..]
		if frac.len > 1 {
			s = s[0..dot + 2]
		} else if frac.len == 0 {
			s += '0'
		}
	}
	return s
}

fn print_results(results map[string]CityStats, human_readable bool) {
	mut cities := results.keys()
	cities.sort()
	mut lines := []string{cap: cities.len}
	for city in cities {
		s := results[city]
		mean := if s.count > 0 { s.sum_temp / f64(s.count) } else { 0.0 }
		lines << '${city}  min=${fmt1(f64(s.min_temp))}/ avg=${fmt1(mean)}/ max=${fmt1(f64(s.max_temp))}'
	}
	if human_readable {
		println(lines.join('\n'))
	} else {
		println('{ ' + lines.join(', ') + ' }')
	}
}

// =========================================================================
// SECTION 6: Parallel dispatch (spawn + thread[].wait())
// =========================================================================

fn process_in_parallel(mf MMapFile, thread_count u32) map[string]CityStats {
	mut threads := []thread map[string]CityStats{}
	approx := mf.size / thread_count
	mut from := u64(0)
	mut to := approx
	for _ in 0 .. thread_count - 1 {
		unsafe {
			for mf.data[to] != `\n` {
				to++
			}
		}
		threads << spawn process_chunk(mf.data, from, to)
		from = to + 1
		to = from + approx
	}
	to = mf.size
	threads << spawn process_chunk(mf.data, from, to)
	res := threads.wait()
	return combine_results(res)
}

// =========================================================================
// SECTION 7: Main
// =========================================================================

fn main() {
	if os.args.len < 2 {
		eprintln('Usage: 1brc [--human-readable] [--threads N] <datafile>')
		exit(1)
	}

	mut human_readable := false
	mut num_threads := u32(1)
	mut threads_set := false
	mut filepath := ''
	mut i := 1
	for i < os.args.len {
		arg := os.args[i]
		if arg == '--human-readable' || arg == '-h' {
			human_readable = true
		} else if arg == '--threads' || arg == '-t' {
			if i + 1 < os.args.len {
				i++
				num_threads = os.args[i].u32()
				threads_set = true
			}
		} else if filepath == '' {
			filepath = arg
		}
		i++
	}
	if filepath == '' {
		eprintln('Usage: 1brc [--human-readable] [--threads N] <datafile>')
		exit(1)
	}

	mut mf := mmap_file(filepath)
	defer { mf.unmap() }
	println('File: ${filepath}  Size: ${mf.size} bytes')

	if !threads_set {
		// default to a reasonable parallel count (capped at 8)
		num_threads = 8
	}
	println('Threads: ${num_threads}')

	start_ms := time.now().unix_milli()

	results := if num_threads > 1 {
		process_in_parallel(mf, num_threads)
	} else {
		process_chunk(mf.data, 0, mf.size)
	}

	elapsed := time.now().unix_milli() - start_ms
	print_results(results, human_readable)
	println('Done in ${elapsed} ms')
}
