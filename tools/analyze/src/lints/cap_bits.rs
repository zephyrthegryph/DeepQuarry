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
        self.selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
    }

    fn selftest_with_fixture(&self, fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
        const REG: &str = "code/defines/engine/cap_bits.dm";
        let files = fixture.collect([
            fixture.file(REG, "#define CAP_A (1<<0)\n#define CAP_B (1<<1)\n")?,
            fixture.file(
                "code/x.dm",
                "#define CAP_C (1<<1)\n/obj/x\n\tcap_state = CAP_A\n/obj/x/proc/y()\n\tcap_state |= CAP_B\n",
            )?,
            fixture.file("code/y.dm", "#define CAP_D (1<<30)\n")?,
        ])?;
        let mut scope = LintScope::default();
        fixture.map_insert(&mut scope.lists,fixture.own("registry")?,fixture.collect([fixture.own(REG)?])?)?;
        fixture.map_insert(&mut scope.lists,fixture.own("writers")?,fixture.collect([fixture.own("code/library/capabilities/capabilities.dm")?])?)?;
        fixture.map_insert(&mut scope.lists,fixture.own("write_exempt_prefixes")?,fixture.collect([fixture.own("code/tests/unit_tests/")?])?)?;
        let refs: Vec<&SourceFile> = fixture.collect(files.iter().map(|file| &**file))?;
        let mut out = fixture.sink()?;
        let mut facts=Vec::new();for file in &refs{let actual=fixture.cap_facts(file,scope.list("writers"),scope.list("write_exempt_prefixes"))?;fixture.push(&mut facts,actual)?;}
        fixture.cap_assemble(refs.iter().zip(&facts).map(|(file,facts)|(file.rel.as_str(),facts)),scope.list("registry"),&mut out)?;
        let has = |pred: &dyn Fn(&crate::lint::Site) -> bool| out.sites.iter().any(pred);
        if !has(&|s| s.msg.contains("outside") && s.msg.contains("CAP_C")) {
            return Err(fixture.own("missing 'outside' for CAP_C")?);
        }
        if !has(&|s| s.msg.contains("shares bit 1")) {
            return Err(fixture.own("missing 'shares bit 1'")?);
        }
        if !has(&|s| s.msg.contains("max 23")) {
            return Err(fixture.own("missing 'max 23'")?);
        }
        if !has(&|s| s.rel == "code/x.dm" && s.line == 5 && s.msg.contains("cap_set")) {
            return Err(fixture.own("missing the raw write at x.dm:5")?);
        }
        if has(&|s| s.rel == "code/x.dm" && s.line == 3) {
            return Err(fixture.own("x.dm:3 is a type default and must not be flagged")?);
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
