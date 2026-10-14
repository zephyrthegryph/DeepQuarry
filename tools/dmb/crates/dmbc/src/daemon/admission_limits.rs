//! One startup admission value; it never changes compiler semantics or pool ownership.
use std::{ffi::OsStr, io};

pub(super) fn max_workers() -> io::Result<usize> {
    parse(std::env::var_os("DMB_DAEMON_MAX_WORKERS").as_deref())
}

fn parse(value: Option<&OsStr>) -> io::Result<usize> {
    let Some(value) = value else { return Ok(8) };
    let parsed = value
        .to_str()
        .filter(|text| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
        .and_then(|text| text.parse::<usize>().ok())
        .filter(|value| (1..=8).contains(value));
    parsed.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "DMB_DAEMON_MAX_WORKERS must be an integer from 1 through 8",
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn default_and_each_supported_worker_limit_are_exact() {
        assert_eq!(parse(None).unwrap(), 8);
        for expected in 1..=8 {
            assert_eq!(
                parse(Some(OsStr::new(&expected.to_string()))).unwrap(),
                expected
            );
        }
    }
    #[test]
    fn invalid_worker_limit_is_a_startup_error() {
        for value in [
            "",
            "0",
            "9",
            "-1",
            "+2",
            "2.0",
            " 2",
            "2 ",
            "many",
            "184467440737095516160",
        ] {
            let error = parse(Some(OsStr::new(value))).unwrap_err();
            assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
            assert!(error.to_string().contains("DMB_DAEMON_MAX_WORKERS"));
        }
    }
    #[cfg(windows)]
    #[test]
    fn non_unicode_worker_limit_is_rejected() {
        use std::os::windows::ffi::OsStringExt;
        let value = std::ffi::OsString::from_wide(&[0xd800]);
        assert_eq!(
            parse(Some(&value)).unwrap_err().kind(),
            io::ErrorKind::InvalidInput
        );
    }
}
