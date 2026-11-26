//! `dmbc syntax-coverage [DME]`: how much of a project the typed body model covers (doc/rewrite/proposals/lean_unified.md, "One
//! parse"). The analysis passes can move onto dmbc's front end only where every body has a complete typed model; this counts the
//! bodies with none, the statements it keeps as `Unsupported`, and which statement forms those are.
use dm_syntax::{Statement, StatementKind};
use dm_tree::frontend::{BodyArena, ColdFrontend};
use std::collections::BTreeMap;
use std::path::Path;

#[derive(Default)]
struct Counts {
    bodies: usize,
    no_model: usize,
    complete: usize,
    statements: usize,
    unsupported: usize,
    forms: BTreeMap<String, usize>,
    reasons: BTreeMap<String, usize>,
}

fn walk(statements: &[Statement], c: &mut Counts) -> bool {
    let mut complete = true;
    for s in statements {
        c.statements += 1;
        let children: Vec<&[Statement]> = match &s.kind {
            StatementKind::If { then_branch, else_branch, .. } => vec![then_branch, else_branch],
            StatementKind::While { body, .. }
            | StatementKind::DoWhile { body, .. }
            | StatementKind::Spawn { body, .. }
            | StatementKind::For { body, .. }
            | StatementKind::Label { body, .. } => vec![body],
            StatementKind::Switch { cases, else_branch, .. } => {
                let mut v: Vec<&[Statement]> = cases.iter().map(|k| k.body.as_slice()).collect();
                v.push(else_branch);
                v
            }
            StatementKind::Try { body, catch_body, .. } => vec![body, catch_body],
            StatementKind::Unsupported => {
                complete = false;
                c.unsupported += 1;
                let head: String = s.raw_header.trim_start().chars().take_while(|ch| ch.is_alphanumeric() || *ch == '_').collect();
                *c.forms.entry(if head.is_empty() { s.raw_header.trim().chars().take(12).collect() } else { head }).or_default() += 1;
                vec![]
            }
            _ => vec![],
        };
        for ch in children {
            complete &= walk(ch, c);
        }
    }
    complete
}

pub fn run(dme: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let started = std::time::Instant::now();
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let mut defines = std::collections::BTreeMap::new();
    crate::pinned_target::admit_defines(&mut defines).map_err(|e| format!("{e:?}"))?;
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host.engine(dme.to_path_buf(), defines.clone(), true, include_bytes!("../../../fixtures/native_template.bin").to_vec())?;
    let frontend: ColdFrontend = dm_tree::frontend::build_with_config(
        dme,
        &dm_preprocess::FileSystem,
        &defines,
        dm_tree::frontend::FrontendConfig { workers, engine: Some(engine.frontend_seed()), observer: None },
    )
        .map_err(|d| format!("front end failed: {} diagnostic(s), first: {:?}", d.len(), d.first().map(|x| &x.message)))?;
    eprintln!("syntax-coverage: front end built in {:.1?}", started.elapsed());
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut c = Counts::default();
    for occurrence in frontend.bodies.iter() {
        c.bodies += 1;
        let body = match arena.take_parsed(occurrence) {
            Ok(b) => b,
            Err(e) => {
                c.no_model += 1;
                *c.reasons.entry(e.message.chars().take(60).collect()).or_default() += 1;
                continue;
            }
        };
        let Some(statements) = body.statement_body() else {
            c.no_model += 1;
            *c.reasons.entry("no typed statement model".into()).or_default() += 1;
            continue;
        };
        let parsed = statements.parsed();
        let mut complete = walk(&parsed.statements, &mut c);
        if !parsed.diagnostics.is_empty() {
            complete = false;
            for d in &parsed.diagnostics {
                *c.reasons.entry(d.message.chars().take(60).collect()).or_default() += 1;
            }
        }
        if complete {
            c.complete += 1;
        }
    }
    println!("bodies {}  complete {} ({:.1}%)  no model {}", c.bodies, c.complete, 100.0 * c.complete as f64 / c.bodies.max(1) as f64, c.no_model);
    println!("statements {}  unsupported {} ({:.2}%)", c.statements, c.unsupported, 100.0 * c.unsupported as f64 / c.statements.max(1) as f64);
    let mut forms: Vec<_> = c.forms.into_iter().collect();
    forms.sort_by(|a, b| b.1.cmp(&a.1));
    println!("unsupported statement forms (top 25):");
    for (f, n) in forms.iter().take(25) {
        println!("  {n:>7}  {f}");
    }
    let mut reasons: Vec<_> = c.reasons.into_iter().collect();
    reasons.sort_by(|a, b| b.1.cmp(&a.1));
    println!("diagnostics / reasons (top 15):");
    for (r, n) in reasons.iter().take(15) {
        println!("  {n:>7}  {r}");
    }
    eprintln!("syntax-coverage: done in {:.1?}", started.elapsed());
    Ok(())
}
