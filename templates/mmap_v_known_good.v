// KNOWN-GOOD V 0.5.2 mmap helper (copy + adapt). The pointer→[]u8 cast idiom
// ([])u8(addr)`, `&u8(addr)`, `([]u8(&u8(addr)))[0..n]`) ALL FAIL at C level
// with "conversion to non-scalar type requested"; `&u8` does not support
// slicing either. The only working approach is allocate-then-memcpy.
module yourmod

import os

#include <sys/mman.h>

#include <unistd.h>

#include <fcntl.h>

#include <string.h>

fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr

fn C.munmap(addr voidptr, len u64) i32

fn C.madvise(addr voidptr, len u64, advice i32) i32

fn C.open(path &char, flags i32, mode i32) i32

fn C.close(fd i32) i32

fn C.memcpy(dst voidptr, src voidptr, n u64) voidptr

const prot_read = 1 // PROT_READ


const map_private = 0x02 // MAP_PRIVATE


const madv_willneed = 3 // MADV_WILLNEED


const o_rdonly = 0 // O_RDONLY


// mmap_file: 返回 (data []u8, addr voidptr, size int, fd int)，使用 mmap 打开文件并返回内容切片与底层映射信息
pub fn mmap_file(path string) !([]u8, voidptr, int, int) {
	fd := C.open(&char(path.str), o_rdonly, 0)
	if fd < 0 {
		return error('mmap: cannot open ${path}')
	}
	fi := os.stat(path)!
	size := int(fi.size)
	addr := C.mmap(voidptr(0), u64(size), prot_read, map_private, fd, i64(0))
	if addr == voidptr(0) || addr == voidptr(-1) {
		C.close(fd)
		return error('mmap failed for ${path}')
	}
	C.madvise(addr, u64(size), madv_willneed)
	mut data := []u8{len: size}
	C.memcpy(data.data, addr, u64(size))
	return data, addr, size, fd
}

// munmap_file: 释放 mmap 映射并关闭文件描述符
pub fn munmap_file(addr voidptr, size int, fd int) {
	if addr != voidptr(0) {
		C.munmap(addr, u64(size))
	}
	if fd >= 0 {
		C.close(fd)
	}
}
