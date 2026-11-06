//! Explicit, read-only Analyze exclusions report over the resident service.
use super::{protocol, selected_report_wire as wire, transport};
use crate::{request::BuildRequest, runner_host::BuildHost, selected_report_spool::Verified};
use serde::{Deserialize, Serialize};
use std::{error::Error, fs::File, io::{self, Read, Write}, path::Path};

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Request {
    pub(super) build: BuildRequest,
    pub(super) exclusions: Vec<String>,
}

impl Request {
    pub(super) fn qualify(&self) -> io::Result<wire::Roster> {
        if self.build.timeout_seconds.is_none() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "resident exclusions requires an explicit request deadline"));
        }
        BuildHost::qualify_original_exclusions(&self.exclusions)
    }
}

pub(super) struct Completed {
    roster: wire::Roster,
    frame: wire::Frame,
    clean: bool,
    diagnostics: Option<Verified>,
    report: Verified,
    _credit: dm_preprocess::source_arena_credit::SourceArenaCredit,
}

impl Completed {
    pub(super) fn stage(host: &mut BuildHost, build: BuildRequest, roster: wire::Roster, exclusions: &[String]) -> Result<Self, Box<dyn Error>> {
        host.with_original_exclusions_report(build, exclusions, |selected, prepared, clean, diagnostics, report, credit| {
            if selected != roster {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "staged exclusions differ from the admitted roster"));
            }
            let frame = wire::Frame::from_prepared(prepared)?;
            Ok(Self { roster, frame, clean, diagnostics, report, _credit: credit })
        })
    }

    pub(super) fn send(self, stream: &mut impl Write, work: &dyn dm_preprocess::source_arena_credit::SourceArenaWork) -> Result<(), wire::SendFailure> {
        let Self { roster, frame, clean, diagnostics, report, _credit } = self;
        wire::send(stream, roster, frame, clean, diagnostics, report, work)
    }
}

pub fn run_file(path: &Path) -> Result<bool, Box<dyn Error>> {
    let mut bytes = Vec::new();
    File::open(path)?.take(protocol::MAX_FRAME as u64 + 1).read_to_end(&mut bytes)?;
    if bytes.len() > protocol::MAX_FRAME {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "exclusions request exceeds the daemon frame bound").into());
    }
    let request: Request = serde_json::from_slice(&bytes)?;
    drop(bytes);
    let roster = request.qualify()?;
    super::build_admission::validate(&request.build)?;
    let (_, cache) = BuildHost::original_exclusions_paths(&request.build)?;
    let mut stream = super::connect_generation()?;
    transport::set_timeout(&mut stream, transport::BUILD_DEADLINE)?;
    protocol::send(&mut stream, &protocol::Request::SelectedExclusions(request))?;
    let report = wire::receive(&mut stream, &cache, roster)?;
    Ok(report.publish(&mut io::stderr().lock(), &mut io::stdout().lock())?)
}
