//! Optional caller-selected isolation inside the existing current-user endpoint.
//! Unset is the original endpoint name. Invalid values never fall back to it.
use std::{ffi::OsStr, io};

pub(super) fn current_name(base: &str) -> io::Result<String> {
    name(base, std::env::var_os("DMB_DAEMON_NAMESPACE").as_deref())
}
fn name(base: &str, namespace: Option<&OsStr>) -> io::Result<String> {
    let Some(namespace) = namespace else {
        return Ok(base.to_owned());
    };
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "DMB_DAEMON_NAMESPACE must contain 1..64 lowercase ASCII letters, digits or hyphens",
        )
    };
    let text = namespace.to_str().ok_or_else(invalid)?;
    if text.is_empty()
        || text.len() > 64
        || !text
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(invalid());
    }
    Ok(format!("{base}-{text}"))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn default_and_isolated_names_are_exact_on_both_transports() {
        for base in [r"\\.\pipe\dmbd-S-1-5-21", "dmbd-1000"] {
            assert_eq!(name(base, None).unwrap(), base);
            assert_eq!(
                name(base, Some(OsStr::new("upgrade-a1"))).unwrap(),
                format!("{base}-upgrade-a1")
            );
            assert_eq!(
                name(base, Some(OsStr::new("a"))).unwrap(),
                format!("{base}-a")
            );
            let longest = "z".repeat(64);
            assert_eq!(
                name(base, Some(OsStr::new(&longest))).unwrap(),
                format!("{base}-{longest}")
            );
        }
    }
    #[test]
    fn malformed_namespace_cannot_select_default_or_escape_user_directory() {
        for value in [
            "",
            "Upper",
            "space here",
            "a/b",
            r"a\b",
            "..",
            "a:b",
            "é",
            "a\n",
        ] {
            assert_eq!(
                name("dmbd-user", Some(OsStr::new(value)))
                    .unwrap_err()
                    .kind(),
                io::ErrorKind::InvalidInput
            );
        }
        assert!(name("dmbd-user", Some(OsStr::new(&"a".repeat(65)))).is_err());
    }
    #[cfg(windows)]
    #[test]
    fn non_unicode_namespace_is_rejected() {
        use std::os::windows::ffi::OsStringExt;
        let value = std::ffi::OsString::from_wide(&[0xd800]);
        assert_eq!(
            name("dmbd-user", Some(&value)).unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
    }
    #[cfg(unix)]
    #[test]
    fn non_unicode_namespace_is_rejected() {
        use std::os::unix::ffi::OsStringExt;
        let value = std::ffi::OsString::from_vec(vec![0xff]);
        assert_eq!(
            name("dmbd-user", Some(&value)).unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
    }
}
