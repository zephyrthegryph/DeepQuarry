//! Same legacy cache/selftest adapter; unique event rules live in raw_tree_cap_bits_policy.
use crate::{raw_tree_cap_bits_policy::{self as policy,META,Facts},incr,lint::{Cx,Lint,Meta,Registry,Sink},parity::{ParseKind,Parity},scopes::LintScope,tree::SourceFile};
struct CapBits;
/// Uncached check (the selftest's entry).
fn check(files: &[&SourceFile], registry: &[String], writers: &[String], write_exempt: &[String], out: &mut Sink) {
    let facts: Vec<Facts> = files.iter().map(|f| policy::facts_of(f, writers, write_exempt)).collect();
    policy::assemble(files.iter().zip(&facts).map(|(file,facts)|(file.rel.as_str(),facts)),registry,out);
}

impl Lint for CapBits {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let (writers, write_exempt) = (cx.list("writers"), cx.list("write_exempt_prefixes"));
        let ctx = incr::ctx_key(&(writers, write_exempt));
        let facts = incr::keyed("cap_bits-facts", ctx, &files, |f| policy::facts_of(f, writers, write_exempt));
        policy::assemble(files.iter().zip(&facts).map(|(file,facts)|(file.rel.as_str(),facts)),cx.list("registry"),out);
        let n = out.sites.len();
        out.note(format!("cap_bits_lint: {} problem(s)", n));
    }

    fn selftest(&self) -> Result<String, String> {
        const REG: &str = "code/defines/engine/cap_bits.dm";
        let files = vec![
            SourceFile::from_text(REG, "#define CAP_A (1<<0)\n#define CAP_B (1<<1)\n"),
            SourceFile::from_text(
                "code/x.dm",
                "#define CAP_C (1<<1)\n/obj/x\n\tcap_state = CAP_A\n/obj/x/proc/y()\n\tcap_state |= CAP_B\n",
            ),
            SourceFile::from_text("code/y.dm", "#define CAP_D (1<<30)\n"),
        ];
        let mut scope = LintScope::default();
        scope.lists.insert("registry".into(), vec![REG.into()]);
        scope.lists.insert("writers".into(), vec!["code/library/capabilities/capabilities.dm".into()]);
        scope.lists.insert("write_exempt_prefixes".into(), vec!["code/tests/unit_tests/".into()]);
        let refs: Vec<&SourceFile> = files.iter().collect();
        let mut out = Sink::new();
        check(&refs, scope.list("registry"), scope.list("writers"), scope.list("write_exempt_prefixes"), &mut out);
        let has = |pred: &dyn Fn(&crate::lint::Site) -> bool| out.sites.iter().any(pred);
        if !has(&|s| s.msg.contains("outside") && s.msg.contains("CAP_C")) {
            return Err("missing 'outside' for CAP_C".into());
        }
        if !has(&|s| s.msg.contains("shares bit 1")) {
            return Err("missing 'shares bit 1'".into());
        }
        if !has(&|s| s.msg.contains("max 23")) {
            return Err("missing 'max 23'".into());
        }
        if !has(&|s| s.rel == "code/x.dm" && s.line == 5 && s.msg.contains("cap_set")) {
            return Err("missing the raw write at x.dm:5".into());
        }
        if has(&|s| s.rel == "code/x.dm" && s.line == 3) {
            return Err("x.dm:3 is a type default and must not be flagged".into());
        }
        Ok(String::new())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/cap_bits_lint.py"],
            old_raw: &[&["tools/ci/cap_bits_lint.py"]],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: Some(&["tools/ci/cap_bits_lint.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(CapBits);
}
