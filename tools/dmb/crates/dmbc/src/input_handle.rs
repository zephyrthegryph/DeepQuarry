//! Native held-file identity and isolated writable output admission.
use super::{invalid, FileSystemInputs, SnapshotProvider, Stamp};
use std::io;
#[cfg(not(windows))]
pub(crate) fn stamp_handle(file: &std::fs::File) -> io::Result<Stamp> {
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "candidate is not a regular file",
        ));
    }
    let modified_ns = metadata
        .modified()?
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| invalid("input modification time predates epoch"))?
        .as_nanos();
    Ok(Stamp {
        size: metadata.len(),
        modified_ns,
        file_id: platform_file_id(file)?,
    })
}
#[cfg(unix)]
fn platform_file_id(file: &std::fs::File) -> io::Result<Option<u128>> {
    use std::os::unix::fs::MetadataExt;
    let metadata = file.metadata()?;
    Ok(Some(
        (u128::from(metadata.dev()) << 64) | u128::from(metadata.ino()),
    ))
}
#[cfg(windows)]
fn stamp_handle_details(file: &std::fs::File) -> io::Result<(Stamp, u64)> {
    use std::os::windows::io::AsRawHandle;
    #[repr(C)]
    struct Information {
        attributes: u32,
        creation: [u32; 2],
        access: [u32; 2],
        write: [u32; 2],
        volume: u32,
        size_high: u32,
        size_low: u32,
        links: u32,
        index_high: u32,
        index_low: u32,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetFileInformationByHandle(handle: *mut std::ffi::c_void, info: *mut Information)
            -> i32;
    }
    let mut information = std::mem::MaybeUninit::<Information>::uninit();
    // SAFETY: file owns a live handle; Win32 initializes the exact C-layout
    // structure on success. No initialized data is read on failure.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), information.as_mut_ptr()) } == 0 {
        return Err(io::Error::last_os_error());
    }
    let information = unsafe { information.assume_init() };
    if information.attributes & 0x10 != 0 {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "candidate is not a regular file",
        ));
    }
    let write_ticks = (u128::from(information.write[1]) << 32) | u128::from(information.write[0]);
    let modified_ns = write_ticks
        .checked_sub(116_444_736_000_000_000)
        .ok_or_else(|| invalid("input modification time predates epoch"))?
        * 100;
    Ok((
        Stamp {
            size: (u64::from(information.size_high) << 32) | u64::from(information.size_low),
            modified_ns,
            file_id: Some(
                (u128::from(information.volume) << 64)
                    | (u128::from(information.index_high) << 32)
                    | u128::from(information.index_low),
            ),
        },
        u64::from(information.links),
    ))
}
#[cfg(not(any(unix, windows)))]
fn platform_file_id(_: &std::fs::File) -> io::Result<Option<u128>> {
    Ok(None)
}

#[cfg(windows)]
pub(crate) fn stamp_handle(file: &std::fs::File) -> io::Result<Stamp> {
    stamp_handle_details(file).map(|(stamp, _)| stamp)
}
#[cfg(windows)]
fn isolated_handle(file: &std::fs::File) -> io::Result<Option<Stamp>> {
    let (stamp, links) = stamp_handle_details(file)?;
    Ok((links == 1).then_some(stamp))
}
#[cfg(unix)]
fn isolated_handle(file: &std::fs::File) -> io::Result<Option<Stamp>> {
    use std::os::unix::fs::MetadataExt;
    if file.metadata()?.nlink() != 1 {
        return Ok(None);
    }
    stamp_handle(file).map(Some)
}
#[cfg(not(any(unix, windows)))]
fn isolated_handle(_: &std::fs::File) -> io::Result<Option<Stamp>> {
    Ok(None)
}

/// Held-handle authentication for a writable output with no shared hardlinks.
/// Symlinks and uncertain identities require ordinary atomic replacement.
pub(crate) fn isolated_output_stamp(path: &std::path::Path) -> io::Result<Option<Stamp>> {
    let regular_writable = |metadata: &std::fs::Metadata| {
        metadata.file_type().is_file() && !metadata.permissions().readonly()
    };
    if !regular_writable(&std::fs::symlink_metadata(path)?) {
        return Ok(None);
    }
    let file = std::fs::File::open(path)?;
    if !regular_writable(&file.metadata()?) {
        return Ok(None);
    }
    let Some(stamp) = isolated_handle(&file)? else {
        return Ok(None);
    };
    if stamp.file_id.is_none()
        || !regular_writable(&std::fs::symlink_metadata(path)?)
        || FileSystemInputs.stamp(path)? != stamp
    {
        return Ok(None);
    }
    Ok(Some(stamp))
}
