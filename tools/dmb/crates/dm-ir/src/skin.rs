//! Interface resources remain symbolic: BYOND interprets the authored DMF
//! payload at runtime. Property text is never invented as compiler metadata.
use std::sync::Arc;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SkinInterface {
    pub archive_alias: Arc<str>,
    pub resource_dependencies: Arc<[Arc<str>]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SkinSelection {
    /// Manifest encounter order. Last included DMF is selected.
    pub interfaces: Arc<[SkinInterface]>,
}
impl SkinSelection {
    pub fn selected(&self) -> Option<&SkinInterface> {
        self.interfaces.last()
    }
}
