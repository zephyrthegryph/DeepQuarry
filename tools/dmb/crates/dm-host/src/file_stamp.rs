use serde::{Deserialize, Serialize};
use std::{fs, path::Path, time::SystemTime};
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct FileStamp {
    len: u64,
    modified: SystemTime,
    identity: Vec<u64>,
}

impl FileStamp {
    #[cfg(windows)]
    pub(crate) fn volume_id(&self) -> Option<u64> {
        self.identity.first().copied()
    }
    #[cfg(windows)]
    pub(crate) fn same_object(&self, other: &Self) -> bool {
        self.identity
            .get(..3)
            .is_some_and(|identity| Some(identity) == other.identity.get(..3))
    }
    #[cfg(windows)]
    pub(crate) fn file_id(&self) -> Option<[u64; 2]> {
        Some([*self.identity.get(1)?, *self.identity.get(2)?])
    }
}
pub fn capture(path: &Path) -> Option<FileStamp> {
    // One open handle ties metadata and identity to the same file even if an
    // editor atomically replaces the path while we inspect it.
    #[cfg(windows)]
    let file = {
        use std::os::windows::fs::OpenOptionsExt;
        // Exclude an earlier reader/writer retaining accumulated USN reasons.
        fs::OpenOptions::new()
            .read(true)
            .share_mode(0)
            .open(path)
            .ok()?
    };
    #[cfg(not(windows))]
    let file = fs::File::open(path).ok()?;
    capture_handle(&file, true)
}

/// Hold the verified file against ordinary Windows writers/replacements while
/// publishing another immutable link. Unsupported sharing semantics fall back.
pub fn open_verified(path: &Path, expected: &FileStamp) -> Option<fs::File> {
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        let file = fs::OpenOptions::new()
            .read(true)
            .share_mode(0)
            .open(path)
            .ok()?;
        (capture_handle(&file, true).as_ref() == Some(expected)).then_some(file)
    }
    #[cfg(not(windows))]
    {
        let _ = (path, expected);
        None
    }
}

pub fn capture_file(file: &fs::File) -> Option<FileStamp> {
    capture_handle(file, true)
}

fn capture_handle(file: &fs::File, require_file: bool) -> Option<FileStamp> {
    let metadata = file.metadata().ok()?;
    if require_file && !metadata.is_file() {
        return None;
    }
    #[cfg(unix)]
    let identity = {
        use std::os::unix::fs::MetadataExt;
        vec![
            metadata.dev(),
            metadata.ino(),
            metadata.ctime() as u64,
            metadata.ctime_nsec() as u64,
        ]
    };
    #[cfg(windows)]
    let mut identity = windows_identity(&file)?;
    #[cfg(windows)]
    if require_file {
        identity.push(windows_file_usn(file)?);
    }
    #[cfg(not(any(unix, windows)))]
    let identity: Vec<u64> = return None;
    Some(FileStamp {
        len: metadata.len(),
        modified: metadata.modified().ok()?,
        identity,
    })
}

#[cfg(windows)]
fn windows_file_usn(file: &fs::File) -> Option<u64> {
    use std::os::windows::io::AsRawHandle;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn DeviceIoControl(
            handle: *mut std::ffi::c_void,
            code: u32,
            input: *const std::ffi::c_void,
            input_len: u32,
            output: *mut std::ffi::c_void,
            output_len: u32,
            returned: *mut u32,
            overlapped: *mut std::ffi::c_void,
        ) -> i32;
    }
    let input = [2u16, 3u16];
    let mut output = [0u8; 1024];
    let mut returned = 0u32;
    let ok = unsafe {
        DeviceIoControl(
            file.as_raw_handle(),
            0x900eb,
            input.as_ptr().cast(),
            4,
            output.as_mut_ptr().cast(),
            output.len() as u32,
            &mut returned,
            std::ptr::null_mut(),
        )
    };
    if ok == 0 || returned as usize > output.len() || returned < 8 {
        return None;
    }
    let bytes = &output[..returned as usize];
    let major = u16::from_le_bytes(bytes.get(4..6)?.try_into().ok()?);
    let offset = match major {
        2 => 24,
        3 => 40,
        _ => return None,
    };
    let usn = u64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
    (usn != 0).then_some(usn)
}

#[cfg(windows)]
pub(crate) fn exclusive_barrier(path: &Path, expected: &FileStamp) -> bool {
    use std::os::windows::fs::OpenOptionsExt;
    let Ok(file) = fs::OpenOptions::new().read(true).share_mode(0).open(path) else {
        return false;
    };
    // No reader/writer can predate this open. Closing the handle resets any
    // accumulated USN reason flags before a future writer starts its session.
    capture_handle(&file, true).as_ref() == Some(expected)
}

#[cfg(windows)]
pub(crate) fn directory(path: &Path) -> Option<FileStamp> {
    use std::os::windows::fs::OpenOptionsExt;
    let file = fs::OpenOptions::new()
        .read(true)
        .custom_flags(0x02000000 | 0x00200000)
        .open(path)
        .ok()?;
    capture_handle(&file, false)
}

#[cfg(windows)]
pub(crate) fn directory_following(path: &Path) -> Option<FileStamp> {
    use std::os::windows::fs::OpenOptionsExt;
    let file = fs::OpenOptions::new()
        .read(true)
        .custom_flags(0x02000000)
        .open(path)
        .ok()?;
    capture_handle(&file, false)
}

#[cfg(windows)]
fn windows_identity(file: &fs::File) -> Option<Vec<u64>> {
    use std::os::windows::io::AsRawHandle;
    #[repr(C)]
    struct Basic {
        creation: i64,
        access: i64,
        write: i64,
        change: i64,
        attributes: u32,
    }
    #[repr(C)]
    struct Id {
        volume: u64,
        id: [u64; 2],
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetFileInformationByHandleEx(
            handle: *mut std::ffi::c_void,
            class: i32,
            info: *mut std::ffi::c_void,
            size: u32,
        ) -> i32;
    }
    let mut basic = std::mem::MaybeUninit::<Basic>::uninit();
    let mut id = std::mem::MaybeUninit::<Id>::uninit();
    // Both structures are initialized only after successful kernel calls.
    unsafe {
        if GetFileInformationByHandleEx(
            file.as_raw_handle(),
            0,
            basic.as_mut_ptr().cast(),
            std::mem::size_of::<Basic>() as u32,
        ) == 0
            || GetFileInformationByHandleEx(
                file.as_raw_handle(),
                18,
                id.as_mut_ptr().cast(),
                std::mem::size_of::<Id>() as u32,
            ) == 0
        {
            return None;
        }
        let basic = basic.assume_init();
        let id = id.assume_init();
        if basic.change == 0 {
            return None;
        }
        Some(vec![
            id.volume,
            id.id[0],
            id.id[1],
            basic.creation as u64,
            basic.change as u64,
        ])
    }
}
