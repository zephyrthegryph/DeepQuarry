//! Exact existing STAT row and emission policy, shared by old and native producers.
//! Type-variable membership is deliberately the old raw lexical policy.
use crate::{captured_generator_budget::Budget, sparse_slots_policy::Output};
use std::sync::Arc;
const BUILTIN_VARS: &[&str] = &[
    "density",
    "opacity",
    "invisibility",
    "luminosity",
    "layer",
    "alpha",
    "color",
    "dir",
    "name",
    "desc",
];
fn split_opt(arg: &str) -> Option<(String, String)> {
    let b = arg.as_bytes();
    let mut i = 0;
    while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
        i += 1;
    }
    if i == 0 {
        return None;
    }
    let rest = arg[i..].trim_start().strip_prefix('=')?;
    if rest.starts_with('=') {
        return None;
    }
    Some((arg[..i].to_string(), rest.trim().to_string()))
}
fn one_line(s: &str) -> String {
    s.replace("\\\r\n", " ")
        .replace("\\\n", " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}
fn rule_base(rule: &str) -> &'static str {
    match rule {
        "ALL" => "TRUE",
        "ANY" => "FALSE",
        "SUM" | "MASK_OR" => "0",
        "PRODUCT" => "1",
        _ => "null",
    }
}
/// Borrowed traversal of exactly the old lexical ancestors (not parent_type).
pub fn declares_var(
    mut contains: impl FnMut(&str, &str) -> bool,
    mut ty: &str,
    name: &str,
) -> bool {
    loop {
        if contains(ty, name) {
            return true;
        }
        match ty.rfind('/') {
            Some(0) | None => return false,
            Some(i) => ty = &ty[..i],
        }
    }
}
struct Upper<'a>(&'a str);
impl std::fmt::Display for Upper<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // String::to_uppercase is exactly this Unicode char expansion, borrowed.
        use std::fmt::Write;
        for c in self.0.chars().flat_map(char::to_uppercase) {
            f.write_char(c)?;
        }
        Ok(())
    }
}
struct Options<'a>(&'a Row);
impl std::fmt::Display for Options<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "id = STAT_{}", Upper(&self.0.name))?;
        for (k, v) in self.0.opts.iter().filter(|(k, _)| k != "virtual") {
            write!(f, ", {} = {}", k, v)?;
        }
        Ok(())
    }
}
struct Row {
    rel: String,
    line: u32,
    ty: String,
    name: String,
    rule: String,
    opts: Vec<(String, String)>,
}
#[derive(Default)]
pub struct Builder {
    rows: Vec<Row>,
    out: Output,
    budget: Option<Arc<Budget>>,
}
impl Builder {
    pub fn captured(budget: Arc<Budget>) -> Self {
        Self {
            rows: Vec::new(),
            out: Output::captured(budget.clone()),
            budget: Some(budget),
        }
    }
    pub fn requests(&self) -> impl Iterator<Item = (&str, &str)> {
        self.rows.iter().map(|r| (r.ty.as_str(), r.name.as_str()))
    }
    pub fn push(&mut self, rel: &str, line: u32, args: &[String]) {
        if let Some(b) = &self.budget {
            if self.rows.len() >= crate::captured_generator_budget::MAX_ROWS {
                b.deny();
                return;
            }
            // Original split_opt/one_line allocations are bounded BEFORE running
            // them: a Vec<&str> uses FAT pointers (16 bytes on64bit); at
            // most ceil(width/2) words and old+new growth overlap need24width,
            // while replace/join/owned-value buffers and row strings fit the
            // remaining24width. Option slots have separate geometric preflight.
            // Final output text uses actual chunk admission, not this estimate.
            let width = args.iter().try_fold(0usize, |n, a| n.checked_add(a.len()));
            let charge = width
                .and_then(|n| n.checked_mul(48))
                .and_then(|n| {
                    n.checked_add(
                        args.len()
                            .checked_mul(4 * std::mem::size_of::<(String, String)>())?,
                    )
                })
                .and_then(|n| n.checked_add(rel.len().checked_mul(4)?))
                .and_then(|n| n.checked_add(1024));
            if charge.is_none_or(|n| b.charge(n).is_err()) || !b.row(&mut self.rows) {
                b.deny();
                return;
            }
        }
        if args.len() < 3 {
            self.out.diag(
                rel,
                line,
                "STAT(T, name, RULE, ...) needs a type, a name and a rule",
            );
            return;
        }
        let mut opts = Vec::new();
        for a in &args[3..] {
            match split_opt(a) {
                Some((k, v)) => opts.push((k, one_line(&v))),
                None => self.out.diag_fmt(
                    rel,
                    line,
                    format_args!("STAT({}): `{}` is not an option (name = value)", args[1], a),
                ),
            }
        }
        self.rows.push(Row {
            rel: rel.to_owned(),
            line,
            ty: args[0].clone(),
            name: args[1].clone(),
            rule: args[2].clone(),
            opts,
        });
    }
    pub fn finish(self, membership: impl FnMut(&str, &str) -> bool) -> Output {
        self.finish_checked(membership, || Ok(()))
            .expect("legacy generator has no operational cancellation")
    }
    pub fn finish_checked(
        mut self,
        mut membership: impl FnMut(&str, &str) -> bool,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Output, String> {
        checkpoint()?;
        if let Some(b) = &self.budget {
            // Stable sort's temporary element storage is covered before sorting.
            b.charge(
                self.rows
                    .len()
                    .saturating_mul(std::mem::size_of::<Row>())
                    .saturating_add(256),
            )?;
        }
        self.rows.sort_by(|a, b| {
            (a.ty.as_str(), a.name.as_str()).cmp(&(b.ty.as_str(), b.name.as_str()))
        });
        let tests = self
            .rows
            .iter()
            .any(|r| crate::generator_test_scope::test_only(&r.rel));
        for test_only in [false, true] {
            if test_only {
                if !tests {
                    break;
                }
                self.out.line(crate::generator_test_scope::TEST_GUARD);
                self.out.blank();
            }
            for r in self
                .rows
                .iter()
                .filter(|r| crate::generator_test_scope::test_only(&r.rel) == test_only)
            {
                checkpoint()?;
                if let Some(b) = &self.budget {
                    b.require()?;
                }
                let base = r
                    .opts
                    .iter()
                    .find(|(k, _)| k == "base")
                    .map(|(_, v)| v.as_str())
                    .unwrap_or_else(|| rule_base(&r.rule));
                self.out.doc_fmt(format_args!(
                    "STAT({}, {}, {}) at {}:{}",
                    r.ty, r.name, r.rule, r.rel, r.line
                ));
                let is_virtual = r.opts.iter().any(|(k, v)| k == "virtual" && v == "TRUE");
                if !is_virtual
                    && !BUILTIN_VARS.contains(&r.name.as_str())
                    && !membership(&r.ty, &r.name)
                {
                    self.out.line_fmt(format_args!("{}/var/{} = {} // ALLOW(base_vars): a stat's var is its settled value (STAT, code/engine/stats)", r.ty, r.name, base));
                }
                self.out
                    .line_fmt(format_args!("{}/proc/__stat_{}()", r.ty, r.name));
                self.out.line_fmt(format_args!(
                    "\treturn list(\"{}\", \"{}\", list({}))",
                    r.name,
                    r.rule,
                    Options(r)
                ));
                self.out
                    .line_fmt(format_args!("/datum/stat_decl{}/__{}/spec()", r.ty, r.name));
                self.out.line_fmt(format_args!(
                    "\treturn list({}, {}/proc/__stat_{})",
                    r.ty, r.ty, r.name
                ));
                self.out.blank();
            }
            if test_only {
                self.out.line("#endif");
            }
        }
        checkpoint()?;
        if let Some(b) = &self.budget {
            b.require()?;
        }
        Ok(self.out)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn args(a: &[&str]) -> Vec<String> {
        a.iter().map(|a| a.to_string()).collect()
    }
    #[test]
    fn exact_lexical_ancestors_do_not_become_parent_hierarchy() {
        assert!(declares_var(
            |t, n| t == "/obj/a" && n == "x",
            "/obj/a/b",
            "x"
        ));
        assert!(!declares_var(|t, _| t == "/datum/parent", "/obj/a/b", "x"));
        assert!(!declares_var(|t, _| t == "/obj/a", "/obj/ab", "x"));
    }
    #[test]
    fn preserves_options_unicode_duplicate_order_and_test_whitespace() {
        let mut b = Builder::default();
        b.push(
            "code/a.dm",
            1,
            &args(&[
                "/obj/a",
                "éß",
                "SUM",
                "base = 7",
                "bogus",
                "reads = list(\"a  b\")",
            ]),
        );
        b.push(
            "code/a.dm",
            2,
            &args(&["/obj/a", "éß", "ANY", "virtual = TRUE"]),
        );
        b.push("code/tests/t.dm", 1, &args(&["/obj/t", "t", "ALL"]));
        let out = b.finish(|_, _| false);
        assert_eq!(out.diags.len(), 1);
        assert!(out
            .body
            .contains("id = STAT_ÉSS, base = 7, reads = list(\"a b\")"));
        assert!(out.body.find("\"SUM\"").unwrap() < out.body.find("\"ANY\"").unwrap());
        assert!(out
            .body
            .ends_with("\treturn list(/obj/t, /obj/t/proc/__stat_t)\n\n#endif\n"));
    }
    #[test]
    fn denial_latches_before_row_allocation_and_no_renderer_success() {
        let budget = Budget::new(256).unwrap();
        let mut b = Builder::captured(budget.clone());
        b.push("code/a.dm", 1, &args(&["/obj/a", "x", "ALL"]));
        assert!(b.finish_checked(|_, _| false, || Ok(())).is_err());
        assert!(budget.denied());
        let out = Output::default();
        assert!(out
            .captured_named_file_text("stats", "stats.dm", &budget)
            .is_err());
    }
}
