//! Original body demand with operation-local errors, never another body store.
use crate::untyped::Unsupported;
use dm_tree::frontend::{ArchivedBody, BodyArchive, BodySyntaxFailure};

#[derive(Debug)]
pub enum PolicyFailure {
    Unsupported(Unsupported),
    Operational(std::io::Error),
}
impl From<Unsupported> for PolicyFailure {
    fn from(value: Unsupported) -> Self {
        Self::Unsupported(value)
    }
}
impl From<String> for PolicyFailure {
    fn from(value: String) -> Self {
        Self::Unsupported(Unsupported(value))
    }
}
impl From<&str> for PolicyFailure {
    fn from(value: &str) -> Self {
        value.to_owned().into()
    }
}
impl From<String> for Unsupported {
    fn from(value: String) -> Self {
        Self(value)
    }
}
impl From<&str> for Unsupported {
    fn from(value: &str) -> Self {
        Self(value.to_owned())
    }
}
impl std::fmt::Display for PolicyFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unsupported(e) => e.fmt(f),
            Self::Operational(e) => e.fmt(f),
        }
    }
}
impl std::error::Error for PolicyFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(match self {
            Self::Unsupported(e) => e,
            Self::Operational(e) => e,
        })
    }
}
mod sealed {
    pub trait Sealed {}
}
pub struct Compatibility;
pub struct Checked;
impl sealed::Sealed for Compatibility {}
impl sealed::Sealed for Checked {}
/// Only the demand boundary varies; each caller keeps its one existing policy.
pub trait Demand: sealed::Sealed {
    type Error: From<Unsupported> + From<String> + for<'a> From<&'a str>;
    fn parse<'a>(archive: &'a BodyArchive, ordinal: usize)
        -> Result<ArchivedBody<'a>, Self::Error>;
}
impl Demand for Compatibility {
    type Error = Unsupported;
    fn parse<'a>(
        archive: &'a BodyArchive,
        ordinal: usize,
    ) -> Result<ArchivedBody<'a>, Self::Error> {
        archive.parse(ordinal).map_err(|e| Unsupported(e.message))
    }
}
impl Demand for Checked {
    type Error = PolicyFailure;
    fn parse<'a>(
        archive: &'a BodyArchive,
        ordinal: usize,
    ) -> Result<ArchivedBody<'a>, Self::Error> {
        archive.parse_checked(ordinal).map_err(|e| match e {
            BodySyntaxFailure::Syntax(e) => Unsupported(e.message).into(),
            BodySyntaxFailure::Operational(e) => PolicyFailure::Operational(e),
        })
    }
}

/// Synchronous full-workspace policy work lent by the actual current source
/// host. This carries operation control/storage only, never source authority.
pub trait WorkspaceWork{
 type Error:From<Unsupported>+From<String>+for<'a>From<&'a str>;
 const CHECKED:bool;
 fn checkpoint(&mut self)->Result<(),Self::Error>;
 fn retain(&mut self,bytes:usize)->Result<(),Self::Error>;
 /// A maximum of live temporary backing, scoped to this synchronous fold.
 fn temporary(&mut self,bytes:usize)->Result<(),Self::Error>;
 fn overflow(&mut self)->Self::Error;
 fn allocation_failed(&mut self)->Self::Error;
 fn body<'a>(&mut self,archive:&'a BodyArchive,ordinal:usize)->Result<ArchivedBody<'a>,Self::Error>;
}
