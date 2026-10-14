//! One shared publication lease protects overlapping destinations across stores.
//!
//! Conservatively serializes conventional pair installation, including aliases
//! and absent destination parents. Encoding and immutable staging precede this
//! lease. No registry, destination parent creation, or path hash authority.
use super::*;
use std::time::{Duration, Instant};
pub(super) fn acquire() -> io::Result<File> {
    acquire_at(&control_root()?)
}
fn control_root() -> io::Result<PathBuf> {
    #[cfg(windows)]
    {
        Ok(PathBuf::from("E:/dq-cache/dmbd/publication-leases"))
    }
    #[cfg(not(windows))]
    {
        std::env::var_os("HOME")
            .map(|home| PathBuf::from(home).join(".cache/dmbd/publication-leases"))
            .ok_or_else(|| invalid("publication lease control root unavailable"))
    }
}
fn open(root: &Path) -> io::Result<File> {
    fs::create_dir_all(root)?;
    OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(root.join("publication.lock"))
}
fn acquire_at(root: &Path) -> io::Result<File> {
    let deadline = Instant::now() + Duration::from_secs(300);
    let file = open(root)?;
    crate::request_lease::acquire_before(&file, deadline)?;
    Ok(file)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn independent_stores_contend_on_shared_publication_lease() {
        let first = super::super::tests::store();
        let second = super::super::tests::store();
        assert_ne!(first.root, second.root);
        let control = first.root.join("shared-lease-control");
        let owner = acquire_at(&control).unwrap();
        let contender = open(&control).unwrap();
        assert!(fs2::FileExt::try_lock_exclusive(&contender).is_err());
        assert!(!first.root.join("absent-output").exists());
        assert!(!second.root.join("absent-output").exists());
        drop(owner);
        crate::request_lease::acquire(&contender).unwrap();
    }
}
