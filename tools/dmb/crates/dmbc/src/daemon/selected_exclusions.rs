//! Explicit, read-only Analyze exclusions report over the resident service.
use super::{protocol, selected_report_wire as wire, transport};
use crate::{request::BuildRequest, runner_host::BuildHost, selected_report_spool::Verified};
use dq_analyze::selected_exclusions_wire::JudgmentV2;
use serde::{Deserialize, Serialize};
use std::{error::Error, fs::File, io::{self, Read, Write}, path::Path};

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Request {
    pub(super) build: BuildRequest,
    pub(super) exclusions: Vec<String>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct RequestV2 {
    build: BuildRequest,
    exclusions: Vec<String>,
    #[serde(default, skip_serializing_if = "JudgmentV2::is_raw")]
    judgment: JudgmentV2,
}
impl RequestV2 {
    pub(super) fn into_mode(self) -> (Request, Mode) {
        (Request { build: self.build, exclusions: self.exclusions }, Mode::GenericV2(self.judgment))
    }
}

pub(super) use crate::runner_host::SelectedReportMode as Mode;

impl Request {
    pub(super) fn qualify(&self, mode: Mode) -> io::Result<wire::Roster> {
        if self.build.timeout_seconds.is_none() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "resident exclusions requires an explicit request deadline"));
        }
        let roster = BuildHost::qualify_original_exclusions(&self.exclusions, mode)?;
        if mode == Mode::Combined && !roster.is_combined() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "combined selected report requires its qualified semantic roster"));
        }
        Ok(roster)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dq_analyze::{
        captured_allow_annotations::{full_unused, Operation},
        captured_generator_budget::Budget,
    };

    #[test]
    fn request_qualification_preserves_combined_only_untyped_mode() {
        let crate::request::Command::Build(build) = crate::cli::parse(&[
            "prepare-query".into(), "deepquarry.dme".into(),
        ]).unwrap() else { panic!("expected prepare-query build request") };
        let mut build = *build;
        build.timeout_seconds = Some(60);
        let budget = Budget::new(1 << 20).unwrap();
        let mut operation = Operation { budget: &budget, poll: &|| Ok(()) };
        let selection = full_unused::registered_full_selection(&[], &mut operation).unwrap();
        let exclusions_for = |roster: wire::Roster| selection.names().iter()
            .filter(|name| !roster.names().contains(&name.as_str()))
            .map(|name| format!("-{name}")).collect::<Vec<_>>();
        let mut request = Request { build, exclusions: exclusions_for(wire::Roster::WithUntyped) };
        assert_eq!(request.qualify(Mode::Combined).unwrap(), wire::Roster::WithUntyped);
        assert_eq!(request.qualify(Mode::Ordinary).unwrap_err().kind(), io::ErrorKind::Unsupported);
        assert_eq!(request.qualify(Mode::GenericV2(JudgmentV2::Raw)).unwrap_err().kind(), io::ErrorKind::Unsupported);
        request.exclusions = exclusions_for(wire::Roster::Base);
        assert_eq!(request.qualify(Mode::Ordinary).unwrap(), wire::Roster::Base);
        assert_eq!(request.qualify(Mode::GenericV2(JudgmentV2::Raw)).unwrap(), wire::Roster::Base);
        assert_eq!(request.qualify(Mode::Combined).unwrap_err().kind(), io::ErrorKind::InvalidInput);
    }
}

enum CompletedFrame {
    Semantic(wire::Frame),
    Raw(wire::RawFrame),
}

pub(super) struct Completed {
    roster: wire::Roster,
    mode: Mode,
    frame: CompletedFrame,
    clean: bool,
    diagnostics: Option<Verified>,
    checker: Option<(dq_analyze::selected_exclusions_wire::Frame, Verified)>,
    report: Verified,
    _credit: dm_preprocess::source_arena_credit::SourceArenaCredit,
}

impl Completed {
    pub(super) fn stage(host: &mut BuildHost, build: BuildRequest, roster: wire::Roster, exclusions: &[String], mode: Mode) -> Result<Self, Box<dyn Error>> {
        if roster == wire::Roster::AllRawFilePolicies && mode == Mode::Ordinary {
            return host.with_raw_file_exclusions_report(build, exclusions, |prepared, clean, report, credit| {
                let frame = CompletedFrame::Raw(wire::RawFrame::from_prepared(prepared)?);
                Ok(Self { roster, mode, frame, clean, diagnostics: None, checker: None, report, _credit: credit })
            });
        }
        let combined = mode == Mode::Combined;
        host.with_selected_original_reports_using(build, exclusions, mode, |selected, prepared, clean, diagnostics, checker, report, credit| {
            if selected != roster || checker.is_some() != combined {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "staged exclusions differ from the admitted roster"));
            }
            let frame = CompletedFrame::Semantic(wire::Frame::from_prepared(prepared)?);
            Ok(Self { roster, mode, frame, clean, diagnostics, checker, report, _credit: credit })
        })
    }

    pub(super) fn send(self, stream: &mut impl Write, work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork) -> Result<(), wire::SendFailure> {
        let Self { roster, mode, frame, clean, diagnostics, checker, report, _credit } = self;
        match (mode, checker, frame) {
            (Mode::Combined, Some(checker), CompletedFrame::Semantic(frame)) => wire::send_combined(stream, roster, frame, clean, diagnostics, checker, report, work),
            (Mode::Ordinary, None, CompletedFrame::Raw(frame)) if roster == wire::Roster::AllRawFilePolicies && diagnostics.is_none() =>
                wire::send_raw_selected(stream, frame, clean, report, work),
            (Mode::Ordinary, None, CompletedFrame::Semantic(frame)) => wire::send(stream, roster, frame, clean, diagnostics, report, work),
            (Mode::GenericV2(judgment), None, CompletedFrame::Semantic(frame)) => wire::send_v2(stream, roster, frame, clean, diagnostics, report, work, judgment),
            _ => Err(wire::SendFailure::BeforePublication(io::Error::other("selected report checker transcript differs from its mode"))),
        }
    }
}

pub fn run_file(path: &Path) -> Result<bool, Box<dyn Error>> {
    run_file_mode(path, Mode::Ordinary)
}

pub fn run_combined_file(path: &Path) -> Result<bool, Box<dyn Error>> {
    run_file_mode(path, Mode::Combined)
}

pub fn run_v2_file(path: &Path) -> Result<bool, Box<dyn Error>> {
    let (request, mode) = read_file::<RequestV2>(path)?.into_mode();
    run_request_mode(request, mode)
}

fn run_file_mode(path: &Path, mode: Mode) -> Result<bool, Box<dyn Error>> {
    run_request_mode(read_file(path)?, mode)
}

fn read_file<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T, Box<dyn Error>> {
    let mut bytes = Vec::new();
    File::open(path)?.take(protocol::MAX_FRAME as u64 + 1).read_to_end(&mut bytes)?;
    if bytes.len() > protocol::MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "exclusions request exceeds the daemon frame bound").into());
    }
    Ok(serde_json::from_slice(&bytes)?)
}

fn run_request_mode(request: Request, mode: Mode) -> Result<bool, Box<dyn Error>> {
    let roster = request.qualify(mode)?;
    super::build_admission::validate(&request.build)?;
    let (_, cache) = BuildHost::original_exclusions_paths(&request.build, roster)?;
    let mut stream = super::connect_generation()?;
    transport::set_timeout(&mut stream, transport::BUILD_DEADLINE)?;
    match mode {
        Mode::Combined => {
            protocol::send(&mut stream, &protocol::Request::CombinedSelectedReports(request))?;
            let report = wire::receive_combined(&mut stream, &cache, roster)?;
            Ok(report.publish(&mut io::stderr().lock(), &mut io::stdout().lock())?)
        }
        Mode::Ordinary => {
            protocol::send(&mut stream, &protocol::Request::SelectedExclusions(request))?;
            if roster == wire::Roster::AllRawFilePolicies {
                let report = wire::receive_raw_selected(&mut stream, &cache)?;
                Ok(report.publish(&mut io::stderr().lock(), &mut io::stdout().lock())?)
            } else {
                let report = wire::receive(&mut stream, &cache, roster)?;
                Ok(report.publish(&mut io::stderr().lock(), &mut io::stdout().lock())?)
            }
        }
        Mode::GenericV2(judgment) => {
            let request = RequestV2 { build: request.build, exclusions: request.exclusions, judgment };
            protocol::send(&mut stream, &protocol::Request::SelectedExclusionsV2(request))?;
            let report = wire::receive_v2(&mut stream, &cache, roster, judgment)?;
            Ok(report.publish(&mut io::stderr().lock(), &mut io::stdout().lock())?)
        }
    }
}
