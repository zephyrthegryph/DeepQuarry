//! Occurrence-only debug source map for the shared encoder.
//!
//! Symbolic code records only an ordinal. The current source occurrence supplies
//! exact semantic path spelling and absolute line at link time. No filesystem
//! reads, global binding clones, or absolute paths participate in code identity.
use dm_tree::frontend::{ColdFrontend, SourceLocation};
use std::{cell::RefCell, collections::BTreeMap};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DebugOrigin {
    pub semantic_path: String,
    pub line: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DebugOrigins {
    pub entries: Vec<DebugOrigin>,
}

/// A provider is borrowed for one lowering operation. An expanded byte position
/// is resolved by the frontend's captured mapping, not inferred from proc lines.
pub trait DebugOriginProvider {
    fn origin(&self, expanded_offset: usize) -> Result<DebugOrigin, String>;
}
impl DebugOriginProvider for ColdFrontend {
    fn origin(&self, expanded_offset: usize) -> Result<DebugOrigin, String> {
        let location = self.location(expanded_offset).ok_or_else(|| {
            format!("missing captured source origin at expanded offset {expanded_offset}")
        })?;
        origin_from_location(&location)
    }
}
fn origin_from_location(location: &SourceLocation) -> Result<DebugOrigin, String> {
    Ok(DebugOrigin {
        semantic_path: location.semantic_path.to_string(),
        line: u32::try_from(location.line)
            .map_err(|_| "source line exceeds BYOND debug operand range".to_string())?,
    })
}

/// First-emission ordering remains deterministic. Repeated use of one source
/// site shares an ordinal; rebasing changes entries, never symbolic operands.
#[derive(Default)]
pub struct DebugOriginCollector {
    by_offset: BTreeMap<usize, u32>,
    origins: DebugOrigins,
}
impl DebugOriginCollector {
    pub fn record(
        &mut self,
        provider: &dyn DebugOriginProvider,
        expanded_offset: usize,
    ) -> Result<u32, String> {
        if let Some(ordinal) = self.by_offset.get(&expanded_offset) {
            return Ok(*ordinal);
        }
        let origin = provider.origin(expanded_offset)?;
        let ordinal = u32::try_from(self.origins.entries.len())
            .map_err(|_| "too many debug source sites".to_string())?;
        self.origins.entries.push(origin);
        self.by_offset.insert(expanded_offset, ordinal);
        Ok(ordinal)
    }
    pub fn finish(self) -> DebugOrigins {
        self.origins
    }
}

/// One borrowed frontend map per procedure; mutable ordinal assignment is local.
pub struct FrontendDebugProvider<'a> {
    frontend: &'a ColdFrontend,
    header_offset: usize,
    collector: RefCell<DebugOriginCollector>,
}
impl<'a> FrontendDebugProvider<'a> {
    pub fn new(frontend: &'a ColdFrontend, header_offset: usize) -> Self {
        Self {
            frontend,
            header_offset,
            collector: RefCell::new(DebugOriginCollector::default()),
        }
    }
    pub fn finish(self) -> DebugOrigins {
        self.collector.into_inner().finish()
    }
}
impl dm_codegen_byond::DebugSourceProvider for FrontendDebugProvider<'_> {
    fn entry_ordinal(&self) -> Result<u32, String> {
        self.ordinal(self.header_offset)
    }
    fn ordinal(&self, expanded_offset: usize) -> Result<u32, String> {
        self.collector
            .borrow_mut()
            .record(self.frontend, expanded_offset)
    }
}
impl DebugOrigins {
    pub fn source_bindings(&self) -> dm_link::SourceBindings {
        let mut result = dm_link::SourceBindings::default();
        for (ordinal, origin) in self.entries.iter().enumerate() {
            let ordinal = u32::try_from(ordinal).expect("collector bounds ordinals");
            result
                .files
                .insert(ordinal, dm_ir::SymbolId::of(&origin.semantic_path));
            result.lines.insert(ordinal, origin.line);
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rebasing_does_not_change_file_identity() {
        let first = DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: "body.dm".into(),
                line: 3,
            }],
        };
        let mut moved = first.clone();
        moved.entries[0].line = 30;
        assert_eq!(first.source_bindings().files, moved.source_bindings().files);
        assert_eq!(first.source_bindings().lines.get(&0), Some(&3));
        assert_eq!(moved.source_bindings().lines.get(&0), Some(&30));
    }
}
