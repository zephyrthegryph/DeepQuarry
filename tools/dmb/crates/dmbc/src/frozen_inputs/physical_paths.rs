//! Capture-time Windows path identities. Handles forbid ancestor rename while
//! the ordinary provider observes bytes/absence/membership. Replay is offline.
use super::*;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(super) struct Node {
    path: PathBuf,
    identity: u128,
    directory: bool,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(super) struct Proof {
    nodes: Vec<Node>,
    missing_from: Option<PathBuf>,
}
pub(super) struct Guard {
    proof: Proof,
    _handles: Vec<fs::File>,
}
impl Guard {
    pub(super) fn proof(&self) -> Proof { self.proof.clone() }
}
#[cfg(not(windows))]
pub(super) fn capture(_: &Path) -> io::Result<Guard> {
    Err(io::Error::new(io::ErrorKind::Unsupported, "physical journal issuer requires Windows held path handles"))
}
#[cfg(windows)]
pub(super) fn capture(path: &Path) -> io::Result<Guard> {
    use std::os::windows::{fs::OpenOptionsExt, io::AsRawHandle};
    #[repr(C)]
    struct Information {
        attributes: u32, creation: [u32; 2], access: [u32; 2], write: [u32; 2],
        volume: u32, size_high: u32, size_low: u32, links: u32,
        index_high: u32, index_low: u32,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetFileInformationByHandle(handle: *mut std::ffi::c_void, info: *mut Information) -> i32;
    }
    let path = canonical_path(path);
    if !path.is_absolute() { return Err(invalid("physical journal path must be absolute")); }
    let mut ancestors: Vec<_> = path.ancestors().collect();
    ancestors.reverse();
    if ancestors.len() > 256 { return Err(invalid("physical journal path depth exceeds bound")); }
    let mut guard = Guard { proof: Proof { nodes: Vec::new(), missing_from: None }, _handles: Vec::new() };
    for ancestor in ancestors {
        // READ_ATTRIBUTES alone does not participate in Win32 sharing checks.
        // GENERIC_READ binds the no-write/no-delete sharing restriction.
        let file = match fs::OpenOptions::new().access_mode(0x80000000)
            // FILE_SHARE_READ only: exclude rename/delete and reparse writes.
            .share_mode(1).custom_flags(0x02000000 | 0x00200000).open(ancestor) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                guard.proof.missing_from = Some(ancestor.to_owned()); break;
            }
            Err(error) => return Err(error),
        };
        let mut information = std::mem::MaybeUninit::<Information>::uninit();
        // SAFETY: live owned handle and exact Win32 output structure.
        if unsafe { GetFileInformationByHandle(file.as_raw_handle(), information.as_mut_ptr()) } == 0 {
            return Err(io::Error::last_os_error());
        }
        let information = unsafe { information.assume_init() };
        if information.attributes & 0x400 != 0 {
            return Err(io::Error::new(io::ErrorKind::Unsupported, "physical journal path traverses a reparse point"));
        }
        let directory = information.attributes & 0x10 != 0;
        if ancestor != path && !directory { return Err(invalid("physical journal ancestor is not a directory")); }
        guard.proof.nodes.push(Node { path: ancestor.to_owned(), directory,
            identity: (u128::from(information.volume) << 64)
                | (u128::from(information.index_high) << 32) | u128::from(information.index_low) });
        guard._handles.push(file);
    }
    Ok(guard)
}

impl Proof {
    pub(super) fn ancestors(&self) -> impl Iterator<Item = &Path> {
        self.nodes.iter().map(|node| node.path.as_path())
    }
    pub(super) fn agrees_with(&self, other: &Self) -> bool {
        self.nodes.iter().zip(&other.nodes).all(|(left, right)| left == right)
    }
    pub(super) fn contained_root_identity(&self, path: &Path, root: &Path) -> io::Result<u128> {
        let path = canonical_path(path);
        let root = canonical_path(root);
        if !path.is_absolute() || !root.is_absolute() || !path.starts_with(&root) {
            return Err(io::Error::new(io::ErrorKind::Unsupported, "physical journal path escapes root"));
        }
        let mut expected: Vec<_> = path.ancestors().collect(); expected.reverse();
        if self.nodes.len() > expected.len() || self.nodes.is_empty() {
            return Err(invalid("physical journal ancestor receipt is incomplete"));
        }
        for (index, node) in self.nodes.iter().enumerate() {
            if node.path != expected[index] || (index + 1 < expected.len() && !node.directory) {
                return Err(invalid("physical journal ancestor receipt differs from requested path"));
            }
        }
        match &self.missing_from {
            Some(missing) if expected.get(self.nodes.len()).copied() == Some(missing.as_path()) => (),
            None if self.nodes.len() == expected.len() => (),
            _ => return Err(invalid("physical journal terminal receipt is incomplete")),
        }
        self.nodes.iter().find(|node| node.path == root && node.directory)
            .map(|node| node.identity)
            .ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "physical journal root was not observed as an existing directory"))
    }
    pub(super) fn present(&self) -> bool { self.missing_from.is_none() }
    pub(super) fn terminal_directory(&self) -> bool { self.nodes.last().is_some_and(|node| node.directory) }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    #[test]
    fn physical_handles_block_ancestor_rename_until_observation_finishes() {
        let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let root = PathBuf::from("E:/dq-cache/dmb-protocol-checks")
            .join(format!("physical-handles-{}-{nonce}", std::process::id()));
        let directory = root.join("assets");
        fs::create_dir_all(&directory).unwrap();
        let guard = capture(&directory.join("missing.txt")).unwrap();
        assert!(fs::rename(&directory, root.join("moved")).is_err());
        assert!(guard.proof.contained_root_identity(&directory.join("missing.txt"), &root).is_ok());
        drop(guard);
        fs::rename(&directory, root.join("moved")).unwrap();
        fs::remove_dir_all(root).unwrap();
    }
}
