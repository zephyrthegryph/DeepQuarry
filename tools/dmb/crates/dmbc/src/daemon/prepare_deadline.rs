//! Explicit cooperative request deadlines for bounded private/tooling sessions.
//! Normal compilation and preparation without the opt-in retain their existing
//! behavior. This is cancellation at checkpoints, never a process-kill timer.
use crate::request::BuildCommand;
use std::{
    ffi::OsStr,
    io,
    time::{Duration, Instant},
};

pub(crate) fn capture(command: BuildCommand, explicit: Option<u16>, started: Instant) -> io::Result<Option<Instant>> {
    capture_with_legacy(command, explicit,
        std::env::var_os("DMB_PREPARE_TIMEOUT_SECONDS").as_deref(), started)
}
fn capture_with_legacy(command: BuildCommand, explicit: Option<u16>, legacy: Option<&OsStr>, started: Instant) -> io::Result<Option<Instant>> {
    crate::request::validate_timeout_seconds(explicit)?;
    if let Some(seconds) = explicit {
        return started.checked_add(Duration::from_secs(u64::from(seconds))).map(Some)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "request deadline overflow"));
    }
    if command != BuildCommand::PrepareQuery {
        return Ok(None);
    }
    parse(legacy, started)
}
fn parse(value: Option<&OsStr>, started: Instant) -> io::Result<Option<Instant>> {
    let Some(value) = value else { return Ok(None) };
    let invalid = || {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "DMB_PREPARE_TIMEOUT_SECONDS must be an integer in 1..300",
        )
    };
    let text = value
        .to_str()
        .filter(|text| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
        .ok_or_else(invalid)?;
    let seconds: u64 = text.parse().map_err(|_| invalid())?;
    if !(1..=300).contains(&seconds) {
        return Err(invalid());
    }
    started
        .checked_add(Duration::from_secs(seconds))
        .map(Some)
        .ok_or_else(invalid)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preparation_deadline_is_explicit_and_absolute() {
        let started = Instant::now();
        assert_eq!(parse(None, started).unwrap(), None);
        assert_eq!(
            parse(Some(OsStr::new("1")), started).unwrap(),
            Some(started + Duration::from_secs(1))
        );
        assert_eq!(
            parse(Some(OsStr::new("300")), started).unwrap(),
            Some(started + Duration::from_secs(300))
        );
        // A caller may reuse this same Instant for admission and execution;
        // retries cannot restart the opted-in request's budget.
        let issued = parse(Some(OsStr::new("30")), started).unwrap().unwrap();
        assert_eq!(
            issued.duration_since(started + Duration::from_secs(29)),
            Duration::from_secs(1)
        );
    }
    #[test]
    fn preparation_deadline_rejects_invalid_zero_and_out_of_range_values() {
        for value in [
            "",
            "0",
            "301",
            "-1",
            "+1",
            "1.5",
            " 1",
            "1 ",
            "never",
            "18446744073709551616",
        ] {
            assert_eq!(
                parse(Some(OsStr::new(value)), Instant::now())
                    .unwrap_err()
                    .kind(),
                io::ErrorKind::InvalidInput,
                "{value}"
            );
        }
    }
    #[test]
    fn ordinary_build_commands_never_consume_the_prepare_opt_in() {
        for command in [
            BuildCommand::Compile,
            BuildCommand::Analyze,
            BuildCommand::AnalyzeBodies,
            BuildCommand::AnalyzeResolved,
        ] {
            assert_eq!(capture_with_legacy(command, None, Some(OsStr::new("invalid")), Instant::now()).unwrap(), None);
        }
    }
    #[test]
    fn explicit_deadlines_cover_every_command_and_override_only_legacy_prepare_budget() {
        let started = Instant::now();
        for command in [BuildCommand::Compile, BuildCommand::Analyze, BuildCommand::AnalyzeBodies,
            BuildCommand::AnalyzeResolved, BuildCommand::PrepareQuery] {
            assert_eq!(capture_with_legacy(command, Some(5), Some(OsStr::new("invalid")), started).unwrap(),
                Some(started + Duration::from_secs(5)));
            for seconds in [0,301,u16::MAX] {
                assert!(capture_with_legacy(command, Some(seconds), None, started).is_err());
            }
            assert_eq!(capture_with_legacy(command, None, None, started).unwrap(), None);
        }
        assert_eq!(capture_with_legacy(BuildCommand::PrepareQuery, None, Some(OsStr::new("7")), started).unwrap(),
            Some(started + Duration::from_secs(7)));
    }
    #[test]
    fn opted_in_deadline_cancels_coordinator_and_inherited_worker_without_sleep() {
        let started = Instant::now() - Duration::from_secs(2);
        let deadline = parse(Some(OsStr::new("1")), started).unwrap().unwrap();
        let binding = super::super::control::bind_with_deadline(
            super::super::control::Cancellation::default(),
            deadline,
        );
        assert_eq!(super::super::control::current_deadline(), Some(deadline));
        let worker = super::super::control::WorkerContext::capture().unwrap();
        let error = std::thread::spawn(move || {
            let _binding = worker.enter();
            assert_eq!(super::super::control::current_deadline(), Some(deadline));
            super::super::control::checkpoint().unwrap_err().kind()
        })
        .join()
        .unwrap();
        assert_eq!(error, io::ErrorKind::Interrupted);
        assert_eq!(
            super::super::control::checkpoint().unwrap_err().kind(),
            io::ErrorKind::Interrupted
        );
        drop(binding);
        assert_eq!(super::super::control::current_deadline(), None);
    }
}
