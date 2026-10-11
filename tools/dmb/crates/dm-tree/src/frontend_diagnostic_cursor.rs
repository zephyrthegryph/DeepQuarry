//! Diagnostic lexer cursors bound exclusively through the current captured source plan.
use super::ColdFrontend;
use std::sync::Arc;

impl ColdFrontend {
    /// Resolve a lexer cursor after a current expanded body offset. Include
    /// returns use the directive planner's checked decoded resume position.
    pub fn diagnostic_cursor_after(&self, end: usize) -> Option<(Arc<str>, usize)> {
        let text = self.expanded.text.as_ref();
        if end == 0 || end > text.len() || !text.is_char_boundary(end) {
            return None;
        }
        let before = self.location(end - 1)?;
        let next = dm_syntax::next_significant_token(text, end)
            .and_then(|token| self.location(token.span.start));
        if let Some(next) = &next {
            if next.include_occurrence == before.include_occurrence {
                return Some((next.semantic_path.clone(), next.line));
            }
        }
        let mut occurrence = before.include_occurrence;
        for _ in 0..=self.plan.occurrences.len() {
            let included = self.plan.occurrences.get(occurrence)?;
            if let Some(cursor) = included.return_cursor() {
                let parent = self.plan.occurrences.get(cursor.parent_occurrence())?;
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
                        return Some((next.semantic_path.clone(), next.line));
                    }
                }
                if let Some(line) = cursor.directive_anchor_line() {
                    return Some((parent.semantic_path.clone(), line));
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
            return (line != 0).then(|| (included.semantic_path.clone(), line));
        }
        None
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
            let occurrence = frontend.plan.occurrences.last().unwrap();
            let cursor = occurrence.return_cursor().unwrap();
            let source = &frontend.plan.source_texts[frontend.plan.occurrences
                [cursor.parent_occurrence()]
            .path
            .as_ref()];
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
