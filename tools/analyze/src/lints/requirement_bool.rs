//! Explicit transitional boolean requirement callbacks. Existing sites are fingerprinted;
//! converting their callbacks to null-or-reason req() shrinks this ratchet.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "requirement_bool",
    group: "",
    label: "requirement_bool",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
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

    fn scan_file(&self, _cx: &Cx, file: &SourceFile, out: &mut Sink) {
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
        let mut registry = Registry::default();
        register(&mut registry);
        let mut sink = Sink::new();
        sink.cur = source.rel.clone();
        registry.lints[0].scan_file(&context, &source, &mut sink);
        assert_eq!(sink.sites.iter().map(|site| site.line).collect::<Vec<_>>(), vec![5, 6]);
        assert!(sink.allow_used.is_empty());
    }
}
