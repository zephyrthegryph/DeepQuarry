//! Explicit transitional boolean requirement callbacks. Existing sites are fingerprinted;
//! converting their callbacks to null-or-reason req() shrinks this ratchet.
//!
//! Union typed proc-body calls with comment/string-stripped source calls. CAPABILITIES and other
//! declaration macro bodies are intentionally also counted even when the semantic parser places
//! their expanded calls in excluded generated files. Macro definitions containing the legacy form
//! are sites themselves. Never let a successful typed parse suppress source evidence.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "requirement_bool",
    group: "",
    label: "requirement_bool",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "boolean_callback",
        hint: "merge the callback and refusal into req(PROC_REF(x)): return null to allow or a reason to refuse",
    }, RuleMeta {
        name: "legacy_macro",
        hint: "the requirement macro compiler was retired: use native null-or-reason requirements in acceptance() or needs()",
    }],
    allow: &[],
    lists: &["retired_macros"],
};

/// Match a complete retired identifier, not a request outcome or a longer live name.
fn retired_name_in(code: &str, name: &str) -> bool {
    let word = |b: u8| b.is_ascii_alphanumeric() || b == b'_';
    code.match_indices(name).any(|(at, _)| {
        let end = at + name.len();
        (at == 0 || !word(code.as_bytes()[at - 1]))
            && (end == code.len() || !word(code.as_bytes()[end]))
    })
}

struct RequirementBool {
    call: Pat,
    declaration: Pat,
}

impl Lint for RequirementBool {
    fn meta(&self) -> &Meta { &META }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        // Cached per file inside call_sites: an edit re-reads only the edited files' bodies.
        let typed: Option<Vec<(String, u32, String)>> = cx.sem().map(|sem| crate::sem::procs::call_sites(&sem, cx.tree, &["req_bool"]));
        // The text rules are a function of one file and the retired-macro list: cached per file, so an edit re-scans that file only.
        let retired: Vec<String> = cx.list("retired_macros").to_vec();
        let ctx = crate::incr::ctx_key(&retired);
        let text: Vec<(Vec<usize>, Vec<usize>)> = crate::incr::keyed("requirement-bool-text", ctx, &files, |file| self.text_sites(file, &retired));
        let calls: Vec<&[usize]> = text.iter().map(|(c, _)| c.as_slice()).collect();
        let sites = Self::merge_sites(&files, typed, &calls);
        for (rel, line) in sites {
            out.site_in("boolean_callback", &rel, line);
        }
        // This lint has no engine exemption: retired requirements cannot return
        // as definitions or calls there while content stays clean.
        for (file, (_, legacy)) in files.iter().zip(&text) {
            for line in legacy {
                out.site_in("legacy_macro", &file.rel, *line);
            }
        }
    }
}

impl RequirementBool {
    /// The typed sites in the selected files, united with each file's text call sites (`calls[i]` for `files[i]`): a successful typed
    /// parse never suppresses source evidence.
    fn merge_sites(files: &[&SourceFile], typed: Option<Vec<(String, u32, String)>>, calls: &[&[usize]]) -> std::collections::BTreeSet<(String, usize)> {
        let mut sites: std::collections::BTreeSet<(String, usize)> = std::collections::BTreeSet::new();
        if let Some(typed_sites) = typed {
            let selected: std::collections::HashSet<&str> = files.iter().map(|f| f.rel.as_str()).collect();
            for (rel, line, _) in typed_sites {
                if selected.contains(rel.as_str()) {
                    sites.insert((rel, line as usize));
                }
            }
        }
        for (file, lines) in files.iter().zip(calls) {
            for line in lines.iter() {
                sites.insert((file.rel.clone(), *line));
            }
        }
        sites
    }

    #[cfg(test)]
    fn collect_sites(&self, files: &[&SourceFile], typed: Option<Vec<(String, u32, String)>>) -> std::collections::BTreeSet<(String, usize)> {
        let text: Vec<Vec<usize>> = files.iter().map(|f| self.text_sites(f, &[]).0).collect();
        let calls: Vec<&[usize]> = text.iter().map(|c| c.as_slice()).collect();
        Self::merge_sites(files, typed, &calls)
    }

    /// One file's text sites: `req_bool(` calls and definitions, and lines naming a retired macro.
    fn text_sites(&self, file: &SourceFile, retired: &[String]) -> (Vec<usize>, Vec<usize>) {
        let mut calls = Vec::new();
        let mut legacy = Vec::new();
        for (line, code) in file.code().numbered() {
            if self.call.is_match(code) || self.declaration.is_match(code) {
                calls.push(line);
            }
            if retired.iter().any(|name| retired_name_in(code, name)) {
                legacy.push(line);
            }
        }
        (calls, legacy)
    }

    /// The text rule: a `req_bool(` on a code line (the fallback when the model is unavailable).
    #[cfg(test)]
    fn scan_text(&self, file: &SourceFile, out: &mut Sink) {
        for (line, code) in file.code().numbered() {
            if self.call.is_match(code) || self.declaration.is_match(code) {
                out.site("boolean_callback", line);
            }
        }
    }
}

pub fn register(registry: &mut Registry) {
    registry.add(RequirementBool {
        call: Pat::new(r"(?<![\w./])req_bool\s*\("),
        declaration: Pat::new(r"^\s*/(?:\w+/)*req_bool\s*\("),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::Tree;

    #[test]
    fn requirement_bool_counts_calls_and_definitions_without_comment_or_string_noise() {
        let tree = Tree::from_files(vec![]);
        let scope = crate::scopes::LintScope::default();
        let context = Cx { tree: &tree, meta: &META, scope: &scope };
        let source = SourceFile::from_text("code/probe.dm", concat!(
            "/proc/req_bool(what, because = null)\n",
            "\treturn req(what)\n",
            "// req_bool(PROC_REF(old))\n",
            "\tvar/message = \"req_bool(old)\"\n",
            "\tneeds(req_bool(PROC_REF(old)))\n",
            "\tneeds(req_bool(\n",
            "\t\tPROC_REF(other)))\n",
            "\tother_req_bool(old)\n",
            "\tobject.req_bool(old)\n",
            "\treq(PROC_REF(final))\n",
        ));
        let _ = &context;
        let lint = RequirementBool { call: Pat::new(r"(?<![\w./])req_bool\s*\("), declaration: Pat::new(r"^\s*/(?:\w+/)*req_bool\s*\(") };
        let mut sink = Sink::new();
        sink.cur = source.rel.clone();
        lint.scan_text(&source, &mut sink);
        assert_eq!(sink.sites.iter().map(|site| site.line).collect::<Vec<_>>(), vec![1, 5, 6]);
        assert!(sink.allow_used.is_empty());
    }

    #[test]
    fn req_bool_definitions_cannot_reintroduce_the_retired_protocol() {
        let source = SourceFile::from_text("code/engine/probe.dm", concat!(
            "/proc/req_bool(value)\n",
            "/datum/probe/proc/req_bool(value)\n",
            "/datum/probe/req_bool(value)\n",
            "/proc/my_req_bool(value)\n",
            "// /proc/req_bool(value)\n",
            "var/message = \"/proc/req_bool(value)\"\n",
            "object.req_bool(value)\n",
        ));
        let lint = RequirementBool { call: Pat::new(r"(?<![\w./])req_bool\s*\("), declaration: Pat::new(r"^\s*/(?:\w+/)*req_bool\s*\(") };
        let sites = lint.collect_sites(&[&source], Some(vec![]));
        assert_eq!(sites.iter().map(|(_, line)| *line).collect::<Vec<_>>(), vec![1, 2, 3]);
    }

    #[test]
    fn typed_calls_are_at_the_line_of_the_call() {
        let root = tempfile::tempdir().unwrap();
        let text = concat!(
            "/proc/req_bool(what)\n",
            "\treturn what\n",
            "/proc/needs(x)\n",
            "\treturn x\n",
            "#define WRAPPED(x) req_bool(x)\n",
            "/obj/probe/proc/caps()\n",
            "\tneeds(\n",
            "\t\treq_bool(1))\n",
            "\tvar/s = \"req_bool(2)\"\n",
            "\tneeds(WRAPPED(3))\n",
        );
        std::fs::create_dir_all(root.path().join("code")).unwrap();
        std::fs::write(root.path().join("code/probe.dm"), text).unwrap();
        let tree = Tree::from_files(vec![SourceFile::from_text("code/probe.dm", text)]);
        let sem = crate::sem::Sem::build(root.path(), &tree).unwrap();
        let lines: Vec<u32> = crate::sem::procs::call_sites(&sem, &tree, &["req_bool"]).into_iter().map(|(_, l, _)| l).collect();
        assert_eq!(lines, vec![8, 10]);
    }
    #[test]
    fn source_macro_calls_survive_successful_empty_typed_scan() {
        let source = SourceFile::from_text("code/probe.dm", concat!(
            "/proc/req_bool(what)\n",
            "\treturn what\n",
            "#define WRAPPED(x) req_bool(x)\n",
            "CAPABILITIES(/obj/probe)\n",
            "\top(\"use\", needs(req_bool(PROC_REF(old))))\n",
            "\tneeds(req_bool(\n",
            "\t\tPROC_REF(other)))\n",
            "// req_bool(old)\n",
            "\tvar/text = \"req_bool(old)\"\n",
            "\tother_req_bool(old)\n",
            "\tobject.req_bool(old)\n",
        ));
        let lint = RequirementBool { call: Pat::new(r"(?<![\w./])req_bool\s*\("), declaration: Pat::new(r"^\s*/(?:\w+/)*req_bool\s*\(") };
        let files = [&source];
        let empty_typed = lint.collect_sites(&files, Some(vec![]));
        let fallback = lint.collect_sites(&files, None);
        assert_eq!(empty_typed, fallback);
        assert_eq!(empty_typed.iter().map(|(_, line)| *line).collect::<Vec<_>>(), vec![1, 3, 5, 6]);
        let overlapping = lint.collect_sites(&files, Some(vec![("code/probe.dm".into(), 5, "req_bool".into()), ("code/engine/_generated/probe.dm".into(), 50, "req_bool".into())]));
        assert_eq!(overlapping, empty_typed);
    }

    #[test]
    fn retired_macro_names_are_exact_and_code_only() {
        for name in ["CONSTRAINT", "PREDICATE", "PREDICATE_PASSES", "PREDICATE_REASON"] {
            assert!(retired_name_in(&format!("#define {name}(x) x"), name));
            assert!(retired_name_in(&format!("value = {name}(x)"), name));
            assert!(!retired_name_in(&format!("{name}_LIVE(x)"), name));
        }
        assert!(!retired_name_in("acceptance(CONSTRAINT_HOLD)", "CONSTRAINT"));
        assert!(retired_name_in("#define REQ_TAG(subject, tag) list(tag)", "REQ_TAG"));
        assert!(retired_name_in("needs(REQ_TAG(thing, TAG_SHARP))", "REQ_TAG"));
        assert!(!retired_name_in("request_end(src, REQ_CANCELLED, null)", "REQ_TAG"));
        assert!(!retired_name_in("REQ_TAG_EXTRA(x)", "REQ_TAG"));
        assert!(!retired_name_in("LIVE_REQ_TAG(x)", "REQ_TAG"));
        let file = SourceFile::from_text("code/engine/probe.dm", "// REQ_TAG(x)\nvar/message = \"REQ_TAG(x)\"\nREQ_TAG(x)\n");
        let lines: Vec<usize> = file.code().numbered().filter_map(|(line, code)| retired_name_in(code, "REQ_TAG").then_some(line)).collect();
        assert_eq!(lines, vec![3]);
    }

}
