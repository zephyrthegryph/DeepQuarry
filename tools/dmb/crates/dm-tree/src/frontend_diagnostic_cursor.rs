//! Diagnostic lexer cursors bound exclusively through the current captured source plan.
use super::{ColdFrontend, SourceLocation};
use std::sync::Arc;

enum CapturedCursor {
    Token(SourceLocation),
    Boundary {
        path: Arc<str>,
        line: usize,
        location: Option<SourceLocation>,
    },
}
impl ColdFrontend {
    /// Factory issuance over original primary newline cursors and the existing
    /// checked diagnostic continuation resolver. No source text is reparsed.
    pub(super) fn issue_declaration_compatibility(&mut self) {
        use super::source_export_mapping::DeclarationCompatibility;
        let mut rows = Vec::new();
        for (ordinal, cursor) in self.source_export_mapping.primary_declaration_cursors() {
            if self.expanded.text.as_bytes().get(cursor) != Some(&10u8) {
                continue;
            }
            let before = self.location(cursor);
            let next_token = dm_syntax::next_significant_token(&self.expanded.text, cursor + 1);
            let next = next_token.as_ref().and_then(|token| self.location(token.span.start));
            if before
                .as_ref()
                .zip(next.as_ref())
                .is_some_and(|(a, b)| a.include_occurrence == b.include_occurrence)
            {
                continue;
            }
            let mut row = DeclarationCompatibility {
                ordinal,
                occurrence: None,
                line: 0,
                column: 0,
                source_len: 0,
                logical_boundary: true,
            };
            if let Some(CapturedCursor::Boundary {
                location: Some(location),
                ..
            }) = self.diagnostic_cursor_kind(cursor + 1, true)
            {
                if let Some(included) = self.plan.occurrences().get(location.include_occurrence) {
                    if let Some(eof) = included.logical_eof_cursor() {
                        if let (Some(file), Some(acquired)) = (
                            self.files
                                .iter()
                                .find(|file| file.path == included.path && file.captured),
                            self.plan
                                .source_acquisitions()
                                .get(&location.include_occurrence),
                        ) {
                            if included.parent.is_none()&&location.line==eof.line()
                                &&location.encounter_ordinal==eof.encounter()
                                &&location.span.start as usize==file.text.len()
                                &&location.span.start==location.span.end
                                &&acquired.source_text().same_view(&file.text)
                                // Pinned LocationTracker.next() advances after a real LF;
                                // Lexer.next() then emits its final newline at column1.
                                // Without real LF the planner has not proved that column.
                                &&file.text.ends_with('\n')
                            {
                                row.occurrence = Some(location.include_occurrence);
                                row.line = eof.line();
                                row.column = 1;
                                row.source_len = file.text.len();
                            }
                        }
                    }
                }
            }
            // The expanded primary token is the declaration lexer's next token,
            // including a sibling reached after directives. The general diagnostic
            // resolver intentionally stops at directive anchors instead. Issue
            // this token's existing primary-source point; do not
            // turn an unissued boundary or a LINE-only receipt into a column.
            if let (Some(before), Some(token), Some(location)) = (
                before.as_ref(), next_token.as_ref(), next.as_ref(),
            ) {
                if let (Some(included), Some(acquired), Some(file), Ok(point)) = (
                    self.plan.occurrences().get(location.include_occurrence),
                    self.plan.source_acquisitions().get(&location.include_occurrence),
                    self.files.iter().find(|file| file.path == location.path && file.captured),
                    self.source_export_mapping.borrowed_source_note_point(token.span.start),
                ) {
                    let (path, line, column) = point.physical_coordinates();
                    if before.include_occurrence != location.include_occurrence
                        && path == included.path.as_path()
                        && file.id == location.span.file
                        && acquired.source_text().same_view(&file.text)
                    {
                        row.occurrence = Some(location.include_occurrence);
                        row.line = line;
                        row.column = column;
                        row.source_len = acquired.source_text().len();
                        row.logical_boundary = false;
                    }
                }
            }
            rows.push(row);
        }
        Arc::get_mut(&mut self.source_export_mapping)
            .expect("unpublished mapping")
            .bind_declaration_compatibility(rows.into_boxed_slice());
    }

    /// Resolve a lexer cursor after a current expanded body offset. Include
    /// returns use the directive planner's checked decoded resume position.
    pub fn diagnostic_cursor_after(&self, end: usize) -> Option<(Arc<str>, usize)> {
        self.diagnostic_cursor(end).map(|cursor| match cursor {
            CapturedCursor::Token(location) => (location.semantic_path, location.line),
            CapturedCursor::Boundary { path, line, .. } => (path, line),
        })
    }
    /// Bind a lexer token or a planner-issued return/EOF boundary to the exact
    /// current source occurrence and ordered encounter-stream cursor.
    pub fn diagnostic_cursor_location_after(&self, end: usize) -> Option<SourceLocation> {
        match self.diagnostic_cursor(end)? {
            CapturedCursor::Token(location) => Some(location),
            CapturedCursor::Boundary { location, .. } => location,
        }
    }
    fn diagnostic_cursor(&self, end: usize) -> Option<CapturedCursor> {
        self.diagnostic_cursor_kind(end, false)
    }
    fn diagnostic_cursor_kind(&self, end: usize, declaration_eof: bool) -> Option<CapturedCursor> {
        let text = self.expanded.text.as_ref();
        if end == 0 || end > text.len() || !text.is_char_boundary(end) {
            return None;
        }
        let before = self.location(end - 1)?;
        let next = dm_syntax::next_significant_token(text, end)
            .and_then(|token| self.location(token.span.start));
        if let Some(next) = &next {
            if next.include_occurrence == before.include_occurrence {
                return Some(CapturedCursor::Token(next.clone()));
            }
        }
        let mut occurrence = before.include_occurrence;
        for _ in 0..=self.plan.occurrences().len() {
            let included = self.plan.occurrences().get(occurrence)?;
            if let Some(cursor) = included.return_cursor() {
                let parent = self.plan.occurrences().get(cursor.parent_occurrence())?;
                if included.parent != Some(cursor.parent_occurrence()) {
                    return None;
                }
                let file = self
                    .files
                    .iter()
                    .find(|file| file.path == parent.path && file.captured)?;
                let offset = cursor.decoded_offset();
                if offset > file.text.len() || !file.text.is_char_boundary(offset) {
                    return None;
                }
                if let Some(next) = &next {
                    if next.include_occurrence == cursor.parent_occurrence() {
                        return Some(CapturedCursor::Token(next.clone()));
                    }
                }
                // Declarations at terminal separators use the completed reader's
                // real EOF progression, not error-recovery directive anchors.
                // No remaining expanded language token plus each privately
                // issued child EOF/return receipt proves omitted directives and
                // empty repeated includes were actually consumed by this plan.
                if declaration_eof && next.is_none() {
                    included.logical_eof_cursor()?;
                    occurrence = cursor.parent_occurrence();
                    continue;
                }
                if let Some(line) = cursor.directive_anchor_line() {
                    return self.return_cursor_boundary(
                        cursor.parent_occurrence(),
                        offset,
                        line,
                        cursor.encounter_ordinal(),
                    );
                }
                // A terminal parent include returns again. This test uses the
                // captured decoded text, never an invented line increment.
                if dm_syntax::next_significant_token(file.text.as_ref(), offset).is_none() {
                    occurrence = cursor.parent_occurrence();
                    continue;
                }
                // A remaining raw directive is not a lexer token boundary.
                // Its execution may return from another include or suppress
                // text; the current plan has not issued that cursor progression.
                return None;
            }
            if included.parent.is_some() || next.is_some() {
                return None;
            }
            let file = self
                .files
                .iter()
                .find(|file| file.path == included.path && file.captured)?;
            if occurrence == before.include_occurrence {
                // This offset belongs to the original root occurrence only;
                // never apply a child's source span to a returned parent.
                let after = usize::try_from(before.span.end).ok()?;
                if before.span.file != file.id
                    || after > file.text.len()
                    || !file.text.is_char_boundary(after)
                    || dm_syntax::next_significant_token(file.text.as_ref(), after).is_some()
                {
                    return None;
                }
            }
            let line = included.eof_cursor_line()?;
            return self.return_cursor_boundary(
                occurrence,
                file.text.len(),
                line,
                included.eof_cursor_encounter(),
            );
        }
        None
    }
    fn return_cursor_boundary(
        &self,
        occurrence: usize,
        offset: usize,
        line: usize,
        encounter: Option<usize>,
    ) -> Option<CapturedCursor> {
        if line == 0 {
            return None;
        }
        let included = self.plan.occurrences().get(occurrence)?;
        let file = self
            .files
            .iter()
            .find(|file| file.path == included.path && file.captured)?;
        if offset > file.text.len() || !file.text.is_char_boundary(offset) {
            return None;
        }
        let location = encounter
            .filter(|ordinal| *ordinal <= self.plan.items().len())
            .and_then(|encounter_ordinal| {
                let mut chain = vec![occurrence];
                let mut current = occurrence;
                for _ in 0..self.plan.occurrences().len() {
                    match self.plan.occurrences().get(current)?.parent {
                        Some(parent) => {
                            chain.push(parent);
                            current = parent;
                        }
                        None => {
                            chain.reverse();
                            return Some(SourceLocation {
                                span: dm_ir::Span {
                                    file: file.id,
                                    start: u32::try_from(offset).ok()?,
                                    end: u32::try_from(offset).ok()?,
                                },
                                path: included.path.clone(),
                                semantic_path: included.semantic_path.clone(),
                                line,
                                encounter_ordinal,
                                include_occurrence: occurrence,
                                include_chain: chain.into(),
                                // Physical directive-reader boundaries are not macro-expanded tokens.
                                macro_expansions: Default::default(),
                            });
                        }
                    }
                }
                None
            });
        Some(CapturedCursor::Boundary {
            path: included.semantic_path.clone(),
            line,
            location,
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        collections::BTreeMap,
        path::{Path, PathBuf},
    };
    struct Memory(BTreeMap<PathBuf, String>);
    impl dm_preprocess::SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.0
                .get(path)
                .cloned()
                .ok_or_else(|| "missing fixture source".into())
        }
    }
    fn fixture(manifest: &str, parent: Option<&str>, child: &str) -> ColdFrontend {
        let mut files = BTreeMap::from([
            (PathBuf::from("cursor.dme"), manifest.into()),
            (PathBuf::from("child.dm"), child.into()),
        ]);
        if let Some(parent) = parent {
            files.insert(PathBuf::from("parent.dm"), parent.into());
        }
        super::super::build(
            Path::new("cursor.dme"),
            &Memory(files),
            &Default::default(),
            1,
        )
        .unwrap()
    }
    #[test]
    fn parent_eof_uses_planner_issued_encounter_and_current_parent_provenance() {
        let frontend = fixture("#include \"child.dm\"\n", None, "/datum/probe\n");
        let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
        let (path, line) = frontend.diagnostic_cursor_after(end).unwrap();
        assert_eq!(path.as_ref(), "cursor.dme");
        assert_eq!(line, 2);
        let location = frontend.diagnostic_cursor_location_after(end).unwrap();
        assert_eq!(location.semantic_path, path);
        assert_eq!(location.line, line);
        assert_eq!(location.include_occurrence, 0);
        assert_eq!(
            location.encounter_ordinal,
            frontend.plan.occurrences()[0].eof_cursor_encounter().unwrap()
        );
        assert_eq!(
            location.span.file,
            frontend
                .files
                .iter()
                .find(|file| file.path == location.path)
                .unwrap()
                .id
        );
        assert!(location.macro_expansions.is_empty());
    }
    #[test]
    fn included_eof_uses_checked_repeated_nested_and_physical_resume_cursors() {
        let child = "/datum/probe\n";
        for (manifest, parent, expected) in [
            ("#include \"child.dm\"\n", None, 2),
            (
                "#include \"parent.dm\"\n",
                Some("#include \"child.dm\"\n"),
                2,
            ),
            ("#include \\\n \"child.dm\"\n", None, 3),
            ("#include \"child.dm\"", None, 2),
        ] {
            let frontend = fixture(manifest, parent, child);
            let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
            let (path, line) = frontend.diagnostic_cursor_after(end).unwrap();
            assert_eq!(path.as_ref(), "cursor.dme");
            assert_eq!(line, expected);
            let occurrence = frontend.plan.occurrences().last().unwrap();
            let cursor = occurrence.return_cursor().unwrap();
            let source = frontend.plan.source_texts().get(frontend.plan.occurrences()
                [cursor.parent_occurrence()]
            .path
            .as_ref()).unwrap();
            assert!(cursor.decoded_offset() <= source.len());
            assert!(source.is_char_boundary(cursor.decoded_offset()));
        }
        let frontend = fixture(
            "#include \"child.dm\"\n#include \"child.dm\"\n",
            None,
            child,
        );
        for (index, (start, _)) in frontend
            .expanded
            .text
            .match_indices("/datum/probe")
            .enumerate()
        {
            let cursor = frontend.diagnostic_cursor_after(start + "/datum/probe".len());
            if index == 0 {
                let (path, line) = cursor.unwrap();
                assert_eq!(path.as_ref(), "cursor.dme");
                assert_eq!(line, 1);
            } else {
                let (path, line) = cursor.unwrap();
                assert_eq!(path.as_ref(), "cursor.dme");
                assert_eq!(line, 3);
            }
        }
    }
    #[test]
    fn completed_directive_progression_uses_authenticated_include_site() {
        for (manifest, parent) in [
            ("#include \"child.dm\"\n#define X 1\n", None),
            (
                "#include \"child.dm\"\n#if 0\n/datum/skipped\n#endif\n",
                None,
            ),
            (
                "#include \"parent.dm\"\n",
                Some("#include \"child.dm\"\n#define X 1\n"),
            ),
            (
                "#include \"parent.dm\"\n#define X 1\n",
                Some("#include \"child.dm\"\n"),
            ),
        ] {
            let frontend = fixture(manifest, parent, "/datum/probe\n");
            let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
            let (path, line) = frontend.diagnostic_cursor_after(end).unwrap();
            assert_eq!(
                path.as_ref(),
                if parent.is_some_and(|text| text.contains("#define")) {
                    "parent.dm"
                } else {
                    "cursor.dme"
                }
            );
            assert_eq!(line, 1);
        }
        let frontend = fixture(
            "#include \"child.dm\"\n#undef UNKNOWN\n",
            None,
            "/datum/probe\n",
        );
        let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
        assert!(
            frontend.diagnostic_cursor_after(end).is_none(),
            "unproven directive stays unknown"
        );
    }
    #[test]
    fn direct_root_eof_requires_checked_trailing_trivia_not_skipped_directives() {
        for suffix in ["#define X 1\n", "#if 0\n/datum/skipped\n#endif\n"] {
            let frontend = fixture(&format!("/datum/probe\n{suffix}"), None, "");
            let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
            assert!(frontend.diagnostic_cursor_after(end).is_none());
        }
        let frontend = fixture("/datum/probe\n// trailing comment\n\n", None, "");
        let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
        let (path, line) = frontend.diagnostic_cursor_after(end).unwrap();
        assert_eq!(path.as_ref(), "cursor.dme");
        assert_eq!(line, 4);
    }
    #[test]
    fn nonterminal_return_uses_next_significant_parent_token_and_no_newline_is_checked() {
        let frontend = fixture(
            "#include \"child.dm\"\n\n// comment\n/datum/after\n",
            None,
            "/datum/probe",
        );
        let end = frontend.expanded.text.find("/datum/probe").unwrap() + "/datum/probe".len();
        let (path, line) = frontend.diagnostic_cursor_after(end).unwrap();
        assert_eq!(path.as_ref(), "cursor.dme");
        assert_eq!(line, 4);
        assert!(frontend.diagnostic_cursor_after(0).is_none());
        assert!(frontend
            .diagnostic_cursor_after(frontend.expanded.text.len() + 1)
            .is_none());
    }
}
