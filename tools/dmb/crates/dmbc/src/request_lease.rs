//! One bounded, cancellation-aware wait for compiler-owned OS lease handles.
use fs2::FileExt;
use std::{
    fs::File,
    io,
    time::{Duration, Instant},
};
const MAX_WAIT: Duration = Duration::from_secs(300);
pub(crate) fn acquire(file: &File) -> io::Result<()> {
    acquire_until(
        file,
        Instant::now() + MAX_WAIT,
        crate::daemon::control::checkpoint,
    )
}
pub(crate) fn acquire_before(file: &File, deadline: Instant) -> io::Result<()> {
    acquire_until(file, deadline, crate::daemon::control::checkpoint)
}
fn acquire_until(
    file: &File,
    deadline: Instant,
    mut checkpoint: impl FnMut() -> io::Result<()>,
) -> io::Result<()> {
    let deadline = deadline.min(Instant::now() + MAX_WAIT);
    loop {
        checkpoint()?;
        match file.try_lock_exclusive() {
            Ok(()) => return Ok(()),
            Err(error)
                if error.kind() == io::ErrorKind::WouldBlock
                    || error.raw_os_error() == fs2::lock_contended_error().raw_os_error() => {}
            Err(error) => return Err(error),
        }
        let remaining = deadline
            .checked_duration_since(Instant::now())
            .filter(|duration| !duration.is_zero())
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::TimedOut,
                    "compiler lease admission deadline expired",
                )
            })?;
        std::thread::sleep(Duration::from_millis(20).min(remaining));
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn contended_lease_checks_cancellation_and_deadline_without_removing_owner() {
        let path = std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks").join(format!(
            "lease-{}-{}.lock",
            std::process::id(),
            SystemTimeKey::next()
        ));
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let open = || {
            std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(&path)
                .unwrap()
        };
        let owner = open();
        owner.lock_exclusive().unwrap();
        let contender = open();
        let mut polls = 0;
        let error = acquire_until(&contender, Instant::now() + Duration::from_secs(1), || {
            polls += 1;
            if polls >= 2 {
                Err(io::Error::new(
                    io::ErrorKind::Interrupted,
                    "cancelled fixture",
                ))
            } else {
                Ok(())
            }
        })
        .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert!(path.exists());
        assert_eq!(
            acquire_until(&contender, Instant::now(), || Ok(()))
                .unwrap_err()
                .kind(),
            io::ErrorKind::TimedOut
        );
        drop(owner);
        acquire_until(&contender, Instant::now() + Duration::from_secs(1), || {
            Ok(())
        })
        .unwrap();
    }
    struct SystemTimeKey;
    impl SystemTimeKey {
        fn next() -> u128 {
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        }
    }
}
