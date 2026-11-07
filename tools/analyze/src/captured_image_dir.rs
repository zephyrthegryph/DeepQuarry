//! Captured ImageDir DATA. Does not admit an Original model or install a report route.
use crate::{
    captured_api_pages as fund,
    captured_generator_budget::Budget,
    captured_raw_file::Config,
    captured_reactive_reads::Failure,
    image_dir_policy::{MESSAGE, META, RULE},
    lint::{AllowUse, Meta, Site},
};
use dm_analysis::policy_body_demand::WorkspaceWork;
use dm_tree::frontend::{ArchivedBody, BodyArchive, BodySyntaxFailure, OriginalImageDirFrontend};
use std::{io, path::Path, sync::Arc};

pub struct Data {
    sites: Vec<Site>,
}
impl Data {
    pub fn metadata(&self) -> &'static Meta { &META }
    pub fn sites(&self) -> &[Site] { &self.sites }
    pub fn allow_used(&self) -> &[AllowUse] { &[] }
}

struct Work<'a> {
    budget: &'a Budget,
    poll: &'a dyn Fn() -> io::Result<()>,
    peak: usize,
}
impl WorkspaceWork for Work<'_> {
    type Error = Failure;
    const CHECKED: bool = true;
    fn checkpoint(&mut self) -> Result<(), Failure> { fund::checked(self.budget, self.poll) }
    fn retain(&mut self, bytes: usize) -> Result<(), Failure> {
        self.budget.charge(bytes)
            .map_err(|message| Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory, message)))
    }
    fn temporary(&mut self, bytes: usize) -> Result<(), Failure> {
        if bytes > self.peak {
            self.retain(bytes - self.peak)?;
            self.peak = bytes;
        }
        Ok(())
    }
    fn overflow(&mut self) -> Failure {
        self.budget.deny();
        Failure::Operational(io::ErrorKind::OutOfMemory.into())
    }
    fn allocation_failed(&mut self) -> Failure { self.overflow() }
    fn body<'a>(&mut self, archive: &'a BodyArchive, ordinal: usize) -> Result<ArchivedBody<'a>, Failure> {
        self.checkpoint()?;
        archive.parse_checked(ordinal).map_err(|error| match error {
            BodySyntaxFailure::Operational(actual) => Failure::Operational(actual),
            BodySyntaxFailure::Syntax(error) => Failure::Unsupported(error.message),
        })
    }
}

impl dm_analysis::untyped::ImageDirWork for Work<'_>{
    fn operational(&mut self,error:io::Error)->Failure{Failure::Operational(error)}
}

pub fn metadata() -> &'static Meta { &META }

enum Inputs<'a> {
    Named(&'a OriginalImageDirFrontend),
    Shared(&'a dm_tree::frontend::CleanOriginalImageDirArchive<'a>, &'a dm_analysis::policy_inputs::PolicyInputs),
}
pub fn collect_shared(
    archive: &dm_tree::frontend::CleanOriginalImageDirArchive<'_>,
    inputs: &dm_analysis::policy_inputs::PolicyInputs, root: &Path, config: &Config,
    budget: &Arc<Budget>, poll: &dyn Fn() -> io::Result<()>,
) -> Result<Data, Failure> {
    collect_using(Inputs::Shared(archive, inputs), root, config, budget, poll)
}

pub fn collect(
    inputs: &OriginalImageDirFrontend, root: &Path, config: &Config, budget: &Arc<Budget>,
    poll: &dyn Fn() -> io::Result<()>,
) -> Result<Data, Failure> {
    collect_using(Inputs::Named(inputs), root, config, budget, poll)
}

fn collect_using(
    inputs: Inputs<'_>, root: &Path, config: &Config, budget: &Arc<Budget>,
    poll: &dyn Fn() -> io::Result<()>,
) -> Result<Data, Failure> {
    fund::checked(budget, poll)?;
    let empty = crate::scopes::LintScope::default();
    let scope = config.borrowed_report_scope(META.name, META.group).unwrap_or(&empty);
    let scratch = Budget::scoped_temporaries(budget)
        .map_err(|message| Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory, message)))?;
    let pending = (|| {
        let exempt = |relative: &str| scope.exempt(relative) || scope.list("exempt_files").iter().any(|path| path == relative);
        let mut work = Work { budget: &scratch, poll, peak: 0 };
        let found = match inputs {
            Inputs::Named(inputs) => dm_analysis::untyped::image_dir_findings_using(inputs, root, exempt, &mut work)?,
            Inputs::Shared(archive, inputs) => dm_analysis::untyped::image_dir_findings_shared_using(archive, inputs, root, exempt, &mut work)?,
        };
        let mut sites = Vec::new();
        for row in found {
            fund::checked(budget, poll)?;
            fund::row(budget, poll, &mut sites)?;
            sites.push(Site {
                rule: fund::own(budget, poll, RULE)?,
                rel: fund::own(budget, poll, &row.relative)?,
                line: u32::try_from(row.line).map_err(|_| "image dir original line overflow")?,
                msg: fund::own(budget, poll, MESSAGE)?,
                key: String::new(),
                ident: String::new(),
            });
        }
        fund::checked(budget, poll)?;
        Ok::<_, Failure>(Data { sites })
    })();
    if pending.is_err() {
        scratch.keep_failed_scratch();
    }
    pending
}

#[cfg(all(test, feature = "legacy-sem"))]
#[path = "captured_image_dir_tests.rs"]
mod tests;
