//! Lossless paths for external tools which do not understand Windows verbatim paths.
use std::path::{Path, PathBuf};

/// DreamMaker accepts ordinary drive and UNC paths, but a canonical `\\?\`
/// project argument breaks its FILE_DIR resource lookup. Strip only equivalent
/// filesystem prefixes; preserve device paths and every non-Unicode component.
pub fn legacy_tool_path(path: &Path) -> PathBuf {
    #[cfg(windows)]
    {
        use std::ffi::OsString;
        use std::path::{Component, Prefix};
        let mut components = path.components();
        if let Some(Component::Prefix(prefix)) = components.next() {
            let mut ordinary = match prefix.kind() {
                Prefix::VerbatimDisk(drive) => OsString::from(format!("{}:", char::from(drive))),
                Prefix::VerbatimUNC(server, share) => {
                    let mut value = OsString::from(r"\\");
                    value.push(server);
                    value.push(r"\");
                    value.push(share);
                    value
                }
                _ => return path.to_path_buf(),
            };
            ordinary.push(components.as_path());
            return PathBuf::from(ordinary);
        }
    }
    path.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordinary_paths_preserve_spelling() {
        for path in ["relative/project.dme", "./with space/project.dme", ""] {
            assert_eq!(legacy_tool_path(Path::new(path)), PathBuf::from(path));
        }
    }

    #[cfg(windows)]
    #[test]
    fn drive_unc_and_device_prefixes_are_distinguished() {
        for (input, expected) in [
            (
                r"\\?\C:\with space\é\project.dme",
                r"C:\with space\é\project.dme",
            ),
            (
                r"\\?\UNC\server\share\dir\project.dme",
                r"\\server\share\dir\project.dme",
            ),
            (r"\\?\UNC\server\share\", r"\\server\share\"),
            (
                r"\\?\GLOBALROOT\Device\Volume\file",
                r"\\?\GLOBALROOT\Device\Volume\file",
            ),
            (r"\\.\PhysicalDrive0", r"\\.\PhysicalDrive0"),
        ] {
            assert_eq!(
                legacy_tool_path(Path::new(input)).as_os_str(),
                Path::new(expected).as_os_str()
            );
        }
    }

    #[cfg(windows)]
    #[test]
    fn non_unicode_path_components_survive() {
        use std::os::windows::ffi::{OsStrExt, OsStringExt};
        let mut original: Vec<_> = r"\\?\C:\".encode_utf16().collect();
        original.extend([0xd800, b'\\' as u16, b'x' as u16]);
        let path = PathBuf::from(std::ffi::OsString::from_wide(&original));
        let actual: Vec<_> = legacy_tool_path(&path).as_os_str().encode_wide().collect();
        assert_eq!(actual, original[4..]);
    }
}
