//! Resource publication pins and prepared file handoff for one request.
use crate as dmbc;
use std::io;

#[derive(Default)]
pub(super) struct ResourceOutputs {
    pub(super) pins: Vec<dmbc::publish::ResourcePin>,
    pub(super) prepared: Option<dmbc::publish::PreparedOutputFile>,
}
pub(super) struct OutputResourceSink<'a> {
    pub(super) store: &'a dmbc::publish::PairStore,
    pub(super) exact: bool,
    pub(super) destination: &'a std::path::Path,
    pub(super) outputs: &'a std::sync::Mutex<ResourceOutputs>,
}
impl dmbc::assets::ResourceArchiveSink for OutputResourceSink<'_> {
    fn retain(
        &self,
        rows: &[byond_dmb::rsc::NamedResourceView<'_>],
    ) -> io::Result<dmbc::publish::ResourceIdentity> {
        let (identity, pin, prepared) =
            self.store
                .publish_resource_views_prepared(rows, self.exact, Some(self.destination))?;
        let mut outputs = self
            .outputs
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        outputs.pins.push(pin);
        outputs.prepared = prepared;
        Ok(identity)
    }
}
