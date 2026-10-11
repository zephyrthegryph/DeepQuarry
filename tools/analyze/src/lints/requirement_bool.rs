//! Explicit transitional boolean requirement callbacks. Existing sites are fingerprinted;
//! converting their callbacks to null-or-reason req() shrinks this ratchet.
//!
//! The calls are found on the typed tree (`sem::procs::call_sites`): every `req_bool(...)` call in a proc body, at the line of
//! the call, whatever spells it (a macro that wraps it is a site where the macro is used). When the semantic model cannot be
//! built the lint falls back to the text rule (a `req_bool(` on a code line).

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
    policy: Policy::Sites {
        baseline: "tools/ci/requirement_bool_baseline.txt",
        header: &[
            "Transitional boolean requirement callbacks. rule<TAB>file<TAB>normalized line.",
            "Convert callbacks to null-or-reason req(); analyze baseline --update --lint requirement_bool only shrinks this list.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta {
        name: "boolean_callback",
        hint: "merge the callback and refusal into req(PROC_REF(x)): return null to allow or a reason to refuse",
    }],
    allow: &[],
    lists: &[],
};

struct RequirementBool {
    call: Pat,
    declaration: Pat,
}

impl Lint for RequirementBool {
    fn meta(&self) -> &Meta { &META }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let key = crate::incr::ctx_key(&files.iter().map(|f| (f.rel.as_str(), f.fkey)).collect::<Vec<_>>());
        let typed: Option<Vec<(String, u32, String)>> =
            crate::incr::cached("requirement-bool-calls", key, || cx.sem().map(|sem| crate::sem::procs::call_sites(&sem, &["req_bool"])));
        match typed {
            Some(sites) => {
                let selected: std::collections::HashSet<&str> = files.iter().map(|f| f.rel.as_str()).collect();
                for (rel, line, _) in sites {
                    if selected.contains(rel.as_str()) {
                        out.site_in("boolean_callback", &rel, line as usize);
                    }
                }
            }
            None => {
                for f in files {
                    out.cur = f.rel.clone();
                    self.scan_text(f, out);
                }
            }
        }
    }
}

impl RequirementBool {
    /// The text rule: a `req_bool(` on a code line (the fallback when the model is unavailable).
    fn scan_text(&self, file: &SourceFile, out: &mut Sink) {
        for (line, code) in file.code().numbered() {
            if self.call.is_match(code) && !self.declaration.is_match(code) {
                out.site("boolean_callback", line);
            }
        }
    }
}

pub fn register(registry: &mut Registry) {
    registry.add(RequirementBool {
        call: Pat::new(r"(?<![\w./])req_bool\s*\("),
        declaration: Pat::new(r"^\s*/proc/req_bool\s*\("),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::Tree;

    #[test]
    fn requirement_bool_counts_calls_without_comment_string_or_declaration_noise() {
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
        let lint = RequirementBool { call: Pat::new(r"(?<![\w./])req_bool\s*\("), declaration: Pat::new(r"^\s*/proc/req_bool\s*\(") };
        let mut sink = Sink::new();
        sink.cur = source.rel.clone();
        lint.scan_text(&source, &mut sink);
        assert_eq!(sink.sites.iter().map(|site| site.line).collect::<Vec<_>>(), vec![5, 6]);
        assert!(sink.allow_used.is_empty());
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
        let lines: Vec<u32> = crate::sem::procs::call_sites(&sem, &["req_bool"]).into_iter().map(|(_, l, _)| l).collect();
        assert_eq!(lines, vec![8, 10]);
    }
}
