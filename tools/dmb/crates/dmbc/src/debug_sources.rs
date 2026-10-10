//! Occurrence-only debug source map for the shared encoder.
//!
//! Symbolic code records only an ordinal. The current source occurrence supplies
//! exact semantic path spelling and absolute line at link time. No filesystem
//! reads, global binding clones, or absolute paths participate in code identity.
use dm_tree::frontend::ColdFrontend;
#[cfg(test)]
use dm_tree::frontend::SourceLocation;
use std::{cell::RefCell, collections::BTreeMap, sync::Arc};

/// Source-independent recipes interpreted only against the current body issuer.
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum RelativeDebugAnchor {
    AtBodyOffset(usize),
    LexerCursorAfterBodyOffset(usize),
    UnresolvedCursorAtBodyOffset(usize),
    Unbound,
}
impl RelativeDebugAnchor {
    pub(crate) fn bind(
        self,
        base: usize,
        length: usize,
    ) -> Option<dm_codegen_byond::DiagnosticAnchor> {
        use dm_codegen_byond::DiagnosticAnchor as A;
        match self {
            Self::AtBodyOffset(offset) if offset < length => {
                Some(A::AtOffset(base.checked_add(offset)?))
            }
            Self::LexerCursorAfterBodyOffset(offset) if offset > 0 && offset <= length => {
                Some(A::LexerCursorAfterOffset(base.checked_add(offset)?))
            }
            Self::UnresolvedCursorAtBodyOffset(offset) if offset < length => {
                Some(A::UnresolvedCursorAtOffset(base.checked_add(offset)?))
            }
            _ => None,
        }
    }
}

/// Unknown include-return cursors retain the expression's source context but
/// line zero explicitly denotes no issued exact cursor line. Such origins are
/// diagnostic-only and must never be used by an instruction debug operand.
pub(crate) fn diagnostic_origin(
    frontend: &ColdFrontend,
    anchor: dm_codegen_byond::DiagnosticAnchor,
) -> Result<DebugOrigin, String> {
    use dm_codegen_byond::DiagnosticAnchor as A;
    match anchor {
        A::AtOffset(offset) => frontend.origin(offset),
        A::UnresolvedCursorAtOffset(offset) => {
            let mut origin = frontend.origin(offset)?;
            origin.line = 0;
            Ok(origin)
        }
        A::LexerCursorAfterOffset(end) => {
            if let Some((semantic_path, line)) = frontend.diagnostic_cursor_after(end) {
                return Ok(DebugOrigin {
                    semantic_path,
                    line: u32::try_from(line)
                        .map_err(|_| "diagnostic cursor line exceeds debug operand range")?,
                });
            }
            let text = frontend.expanded.text.as_ref();
            if end == 0 || end > text.len() || !text.is_char_boundary(end) {
                return Err("diagnostic cursor outside current source".into());
            }
            // Expanded text alone cannot certify an include-return cursor.
            let mut origin = frontend.origin(end - 1)?;
            origin.line = 0;
            Ok(origin)
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DebugOrigin {
    pub semantic_path: Arc<str>,
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
        let (semantic_path, line) = self.debug_site(expanded_offset).ok_or_else(|| {
            format!("missing captured source origin at expanded offset {expanded_offset}")
        })?;
        Ok(DebugOrigin {
            semantic_path,
            line: u32::try_from(line)
                .map_err(|_| "source line exceeds BYOND debug operand range".to_string())?,
        })
    }
}
#[cfg(test)]
fn origin_from_location(location: &SourceLocation) -> Result<DebugOrigin, String> {
    Ok(DebugOrigin {
        semantic_path: location.semantic_path.clone(),
        line: u32::try_from(location.line)
            .map_err(|_| "source line exceeds BYOND debug operand range".to_string())?,
    })
}

/// First-emission ordering remains deterministic. Repeated use of one source
/// site shares an ordinal; rebasing changes entries, never symbolic operands.
#[derive(Default)]
pub struct DebugOriginCollector {
    by_offset: BTreeMap<usize, u32>,
    by_anchor: BTreeMap<dm_codegen_byond::DiagnosticAnchor, u32>,
    origins: DebugOrigins,
}
impl DebugOriginCollector {
    pub fn record_anchor(
        &mut self,
        frontend: &ColdFrontend,
        anchor: dm_codegen_byond::DiagnosticAnchor,
    ) -> Result<u32, String> {
        if let dm_codegen_byond::DiagnosticAnchor::AtOffset(offset) = anchor {
            return self.record(frontend, offset);
        }
        if let Some(ordinal) = self.by_anchor.get(&anchor) {
            return Ok(*ordinal);
        }
        let origin = diagnostic_origin(frontend, anchor)?;
        let ordinal = u32::try_from(self.origins.entries.len())
            .map_err(|_| "too many diagnostic source sites".to_owned())?;
        self.origins.entries.push(origin);
        self.by_anchor.insert(anchor, ordinal);
        Ok(ordinal)
    }
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
    fn diagnostic_ordinal(
        &self,
        anchor: dm_codegen_byond::DiagnosticAnchor,
    ) -> Result<Option<u32>, String> {
        self.collector
            .borrow_mut()
            .record_anchor(self.frontend, anchor)
            .map(Some)
    }
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
    fn narrow_debug_projection_matches_full_provenance_at_origin_boundaries() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, path: &std::path::Path) -> Result<String, String> {
                if path.file_name().is_some_and(|name| name == "included.dm") {
                    Ok("#define NUMBER 17\n/proc/included()\n    return NUMBER\n".into())
                } else {
                    Ok("#include \"included.dm\"\n/proc/root()\n    return 2\n".into())
                }
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source,
            &BTreeMap::new(),
            1,
        )
        .unwrap();
        let mut offsets = vec![0, frontend.expanded.text.len(), usize::MAX];
        for origin in frontend.expanded.origins.iter() {
            offsets.push(origin.output_span.start);
            offsets.push(origin.output_span.end);
            offsets.push(origin.output_span.end.saturating_sub(1));
        }
        for offset in offsets {
            let narrow = frontend.debug_site(offset);
            let full = frontend.location(offset);
            assert_eq!(narrow.is_some(), full.is_some(), "offset {offset}");
            if let (Some((path, line)), Some(location)) = (narrow, full) {
                assert!(Arc::ptr_eq(&path, &location.semantic_path));
                assert_eq!(line, location.line);
                let debug = frontend.origin(offset).unwrap();
                assert_eq!(debug.semantic_path, location.semantic_path);
                assert_eq!(debug.line as usize, location.line);
            }
        }
    }
    #[test]
    fn captured_debug_sites_share_the_source_path_allocation() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("/proc/probe()\n    return 1\n".into())
            }
        }
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source,
            &BTreeMap::new(),
            1,
        )
        .unwrap();
        let location = &frontend.bodies[0].source;
        let first = origin_from_location(location).unwrap();
        let second = origin_from_location(location).unwrap();
        assert!(Arc::ptr_eq(&first.semantic_path, &location.semantic_path));
        assert!(Arc::ptr_eq(&first.semantic_path, &second.semantic_path));
        assert_eq!(
            first.semantic_path.as_bytes(),
            location.semantic_path.as_bytes()
        );
    }
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

mod frozen_origins;
pub use frozen_origins::{DebugOriginView, FrozenDebugOrigins, OriginAccess};
