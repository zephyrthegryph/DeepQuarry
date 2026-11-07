//! One contiguous virtual-address range for the Original expanded source.
//! Address reservation owns no committed payload. The caller funds each exact
//! additional committed page before calling commit and keeps that credit until
//! this backing is dropped.

use std::{io, ptr::NonNull};

pub(crate) struct ReservedSourceBuffer {
    base: NonNull<u8>,
    reserved: usize,
    page_size: usize,
    committed: usize,
    len: usize,
}

// SAFETY: the pointer owns one private reservation. Shared access can only
// read the initialized prefix. All writes and changes to page protection
// require an exclusive borrow; no external owner can release the mapping.
unsafe impl Send for ReservedSourceBuffer {}
unsafe impl Sync for ReservedSourceBuffer {}

impl ReservedSourceBuffer {
    pub(crate) fn new(limit: usize) -> io::Result<Self> {
        if limit > isize::MAX as usize {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "source address limit exceeds slice geometry"));
        }
        let page_size = platform::page_size()?;
        if page_size == 0 {
            return Err(io::Error::new(io::ErrorKind::Unsupported, "source address reservation has no page geometry"));
        }
        let reserved = limit - limit % page_size;
        if reserved == 0 {
            return Err(io::Error::new(io::ErrorKind::OutOfMemory, "source address limit has no full page"));
        }
        let base = platform::reserve(reserved)?;
        Ok(Self { base, reserved, page_size, committed: 0, len: 0 })
    }

    pub(crate) fn capacity_for(&self, required: usize) -> io::Result<usize> {
        if required > self.reserved {
            return Err(io::Error::new(io::ErrorKind::OutOfMemory, "expanded source exceeds its reserved address range"));
        }
        Ok(required.div_ceil(self.page_size) * self.page_size)
    }

    pub(crate) fn commit(&mut self, capacity: usize) -> io::Result<()> {
        if capacity < self.committed || capacity > self.reserved || capacity % self.page_size != 0 {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid expanded source commit geometry"));
        }
        if capacity == self.committed {
            return Ok(());
        }
        // Compute the next address without dereferencing an uncommitted
        // page. The validated geometry keeps it within the reservation.
        let tail = NonNull::new(self.base.as_ptr().wrapping_add(self.committed))
            .ok_or(io::ErrorKind::InvalidData)?;
        platform::commit(tail, capacity - self.committed)?;
        self.committed = capacity;
        Ok(())
    }

    pub(crate) fn capacity(&self) -> usize {
        self.committed
    }

    pub(crate) fn as_str(&self) -> &str {
        // SAFETY: push_str writes only complete UTF-8 input into committed
        // pages before increasing len. Zero length does not access any page.
        // The mapping outlives this borrow, and no writes can alias it.
        unsafe {
            let bytes = std::slice::from_raw_parts(self.base.as_ptr(), self.len);
            std::str::from_utf8_unchecked(bytes)
        }
    }

    pub(crate) fn push_str(&mut self, text: &str) -> io::Result<()> {
        let end = self.len.checked_add(text.len()).ok_or(io::ErrorKind::OutOfMemory)?;
        if end > self.committed {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "expanded source append exceeds committed pages"));
        }
        if !text.is_empty() {
            // SAFETY: the destination is the newly initialized part of the
            // committed prefix. Safe callers cannot borrow text from self
            // while holding this exclusive borrow. Source bytes are UTF-8.
            unsafe {
                std::ptr::copy_nonoverlapping(text.as_ptr(), self.base.as_ptr().add(self.len), text.len());
            }
        }
        self.len = end;
        Ok(())
    }
}

impl Drop for ReservedSourceBuffer {
    fn drop(&mut self) {
        platform::release(self.base, self.reserved);
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use std::{ffi::c_void, mem::MaybeUninit, ptr};
    use windows_sys::Win32::System::{
        Memory::{VirtualAlloc, VirtualFree, MEM_COMMIT, MEM_RELEASE, MEM_RESERVE, PAGE_NOACCESS, PAGE_READWRITE},
        SystemInformation::{GetSystemInfo, SYSTEM_INFO},
    };

    pub(super) fn page_size() -> io::Result<usize> {
        let mut info = MaybeUninit::<SYSTEM_INFO>::uninit();
        // SAFETY: GetSystemInfo initializes the supplied SYSTEM_INFO.
        unsafe { GetSystemInfo(info.as_mut_ptr()); }
        Ok(unsafe { info.assume_init() }.dwPageSize as usize)
    }

    pub(super) fn reserve(bytes: usize) -> io::Result<NonNull<u8>> {
        // SAFETY: let the OS choose the base. MEM_RESERVE alone neither makes
        // the range accessible nor commits its payload pages.
        let base = unsafe { VirtualAlloc(ptr::null(), bytes, MEM_RESERVE, PAGE_NOACCESS) };
        NonNull::new(base.cast()).ok_or_else(io::Error::last_os_error)
    }

    pub(super) fn commit(tail: NonNull<u8>, bytes: usize) -> io::Result<()> {
        // SAFETY: caller supplies only an aligned, positive subrange of its
        // live reservation. No MEM_RESERVE flag means it cannot choose a
        // separate reservation or move existing bytes.
        let address = tail.as_ptr().cast::<c_void>();
        let actual = unsafe { VirtualAlloc(address, bytes, MEM_COMMIT, PAGE_READWRITE) };
        if actual.is_null() { return Err(io::Error::last_os_error()); }
        if actual != address {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "OS moved a committed source page"));
        }
        Ok(())
    }

    pub(super) fn release(base: NonNull<u8>, _: usize) {
        // SAFETY: the original reservation base is still live and exclusively
        // owned. MEM_RELEASE requires zero length and releases the whole range.
        let released = unsafe { VirtualFree(base.as_ptr().cast(), 0, MEM_RELEASE) };
        debug_assert_ne!(released, 0, "release of the actual source reservation failed");
    }
}

#[cfg(unix)]
mod platform {
    use super::*;
    use std::ptr;

    pub(super) fn page_size() -> io::Result<usize> {
        // SAFETY: sysconf accepts this constant and has no pointer arguments.
        let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
        usize::try_from(size).ok().filter(|size| *size != 0)
            .ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "OS did not provide a source page size"))
    }

    pub(super) fn reserve(bytes: usize) -> io::Result<NonNull<u8>> {
        // SAFETY: anonymous private mapping, with OS-selected address and no
        // initial access. Positive, page-aligned bytes are validated upstream.
        let address = unsafe {
            libc::mmap(ptr::null_mut(), bytes, libc::PROT_NONE, libc::MAP_PRIVATE | libc::MAP_ANON, -1, 0)
        };
        if address == libc::MAP_FAILED { return Err(io::Error::last_os_error()); }
        let Some(base) = NonNull::new(address.cast()) else {
            // A null address cannot back Rust references even for an empty
            // slice. The mmap did succeed, so release it before refusing.
            unsafe { libc::munmap(address, bytes); }
            return Err(io::Error::new(io::ErrorKind::Unsupported, "OS selected a null source reservation"));
        };
        Ok(base)
    }

    pub(super) fn commit(tail: NonNull<u8>, bytes: usize) -> io::Result<()> {
        // SAFETY: caller supplies only an aligned, positive tail of its live
        // mapping. mprotect grants access without replacing the mapping.
        let status = unsafe { libc::mprotect(tail.as_ptr().cast(), bytes, libc::PROT_READ | libc::PROT_WRITE) };
        if status == 0 { Ok(()) } else { Err(io::Error::last_os_error()) }
    }

    pub(super) fn release(base: NonNull<u8>, bytes: usize) {
        // SAFETY: release the exact complete mapping while it is exclusively
        // owned, including the inaccessible tail.
        let status = unsafe { libc::munmap(base.as_ptr().cast(), bytes) };
        debug_assert_eq!(status, 0, "release of the actual source reservation failed");
    }
}

#[cfg(not(any(unix, windows)))]
mod platform {
    use super::*;

    fn unsupported() -> io::Error {
        io::Error::new(io::ErrorKind::Unsupported, "contiguous source address reservation is unavailable on this host")
    }

    pub(super) fn page_size() -> io::Result<usize> { Err(unsupported()) }
    pub(super) fn reserve(_: usize) -> io::Result<NonNull<u8>> { Err(unsupported()) }
    pub(super) fn commit(_: NonNull<u8>, _: usize) -> io::Result<()> { Err(unsupported()) }
    pub(super) fn release(_: NonNull<u8>, _: usize) { unreachable!("unavailable source reservation cannot be owned") }
}

#[cfg(all(test, any(unix, windows)))]
mod tests {
    use super::*;

    #[test]
    fn reserved_source_commits_exact_pages_without_moving_the_utf8_prefix() {
        let page = platform::page_size().unwrap();
        let mut source = ReservedSourceBuffer::new(page * 3 - 1).unwrap();
        let base = source.as_str().as_ptr();
        assert_eq!(source.capacity(), 0);
        assert!(source.push_str("uncommitted").is_err());
        assert_eq!(source.capacity_for(0).unwrap(), 0);
        assert_eq!(source.capacity_for(page - 1).unwrap(), page);
        assert_eq!(source.capacity_for(page + 1).unwrap(), page * 2);
        assert!(source.capacity_for(page * 2 + 1).is_err());
        source.commit(page).unwrap();
        source.push_str(&"a".repeat(page - 1)).unwrap();
        assert!(source.push_str("é").is_err());
        assert_eq!(source.as_str().len(), page - 1);
        source.commit(page * 2).unwrap();
        source.push_str("é").unwrap();
        assert!(source.commit(page).is_err());
        assert!(source.commit(page * 2 - 1).is_err());
        assert_eq!(source.capacity(), page * 2);
        assert_eq!(source.as_str().as_ptr(), base);
        assert!(source.as_str().ends_with("aé"));
        std::thread::scope(|scope| {
            scope.spawn(|| assert_eq!(source.as_str().len(), page + 1)).join().unwrap();
        });
    }
}
