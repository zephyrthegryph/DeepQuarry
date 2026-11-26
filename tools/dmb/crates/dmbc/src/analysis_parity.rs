//! `dmbc analysis-parity [DME]`: how many proc bodies `analysis_bridge` converts to exactly what dreammaker's own parser builds
//! (doc/rewrite/proposals/lean_unified.md, "One program", step 2a).
//!
//! Both trees are built from the same `.dme` in one preprocessor environment: dmbc's front end (pinned BYOND defines, engine seed, as
//! `syntax-coverage` does) and dreammaker's parse (`dq_analyze::sem::parse_for_checker_with_env`) with its predefined macros replaced
//! by dmbc's ([`shared_environment`]). Strings that differ only in stringify spacing or `__FILE__` separators count as equal
//! ([`spelling_equal`]); the CONVERTER PARITY line is the converter's own number. Bodies are matched by (repo-relative file, proc header line). The structural
//! metric compares the trees ignoring every location (dreammaker's `Spanned` equality skips them); the line-aware metric also requires
//! every statement's line to agree. For each differing body the first differing node is classified by its pair of node kinds.
//!
//! `DQ_PARITY_EXAMPLES` (default 3) sets examples per category; `DQ_PARITY_CATEGORIES` (default 40) how many categories print.
use crate::analysis_bridge;
use dm_tree::frontend::{BodyArena, ColdFrontend};
use dreammaker::ast::{Block, Statement};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};

pub(crate) fn norm(p: &str) -> String {
    let s = p.replace('\\', "/").to_ascii_lowercase();
    s.trim_start_matches("./").to_owned()
}

/// Strip location fields so that two serialized trees compare structurally.
pub(crate) fn strip(v: &mut Value) {
    match v {
        Value::Object(m) => {
            m.remove("location");
            if let (Some(_), true) = (m.get("elem"), m.len() == 1) {
                let inner = m.remove("elem").unwrap();
                *v = inner;
                strip(v);
                return;
            }
            for (_, x) in m.iter_mut() {
                strip(x);
            }
        }
        Value::Array(a) => a.iter_mut().for_each(strip),
        _ => {}
    }
}

pub(crate) fn kind(v: &Value) -> String {
    match v {
        Value::Object(m) if m.len() == 1 => m.keys().next().unwrap().clone(),
        Value::Object(m) => format!("{{{}}}", m.keys().cloned().collect::<Vec<_>>().join(",")),
        Value::String(s) if s.len() <= 24 => format!("\"{s}\""),
        Value::String(_) => "string".into(),
        Value::Array(a) => format!("[{}]", a.len()),
        Value::Null => "null".into(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
    }
}

/// The first point where the two trees differ: (path of node kinds, dmbc value, dreammaker value).
pub(crate) fn first_diff<'v>(a: &'v Value, b: &'v Value, path: &mut Vec<String>) -> Option<(&'v Value, &'v Value)> {
    if a == b {
        return None;
    }
    match (a, b) {
        (Value::Object(x), Value::Object(y)) if x.keys().eq(y.keys()) => {
            if x.len() == 1 {
                path.push(kind(a));
            }
            for (k, xv) in x {
                let yv = &y[k];
                if xv != yv {
                    if x.len() > 1 {
                        path.push(k.clone());
                    }
                    return first_diff(xv, yv, path).or(Some((xv, yv)));
                }
            }
            None
        }
        (Value::Array(x), Value::Array(y)) if x.len() == y.len() => {
            for (xv, yv) in x.iter().zip(y) {
                if xv != yv {
                    return first_diff(xv, yv, path).or(Some((xv, yv)));
                }
            }
            None
        }
        (Value::Array(x), Value::Array(y)) => {
            // Different lengths: the first element that differs (one side may have run out).
            let i = x.iter().zip(y).position(|(p, q)| p != q).unwrap_or(x.len().min(y.len()));
            path.push(format!("len {}/{} at #{i}", x.len(), y.len()));
            match (x.get(i), y.get(i)) {
                (Some(p), Some(q)) => Some((p, q)),
                (Some(p), None) => Some((p, &Value::Null)),
                (None, Some(q)) => Some((&Value::Null, q)),
                (None, None) => Some((a, b)),
            }
        }
        _ => Some((a, b)),
    }
}

/// dreammaker's parse defines `SPACEMAN_DMM`, so macros guarded by it add `set SpacemanDMM_*` statements dmbc's build never sees.
fn without_spaceman_settings(block: &Block) -> Option<Block> {
    let is = |s: &dreammaker::ast::Spanned<Statement>| matches!(&s.elem, Statement::Setting { name, .. } if name.starts_with("SpacemanDMM_"));
    if !block.iter().any(is) {
        return None;
    }
    Some(block.iter().filter(|s| !is(s)).cloned().collect())
}

pub(crate) fn short(v: &Value, n: usize) -> String {
    let s = v.to_string();
    if s.len() > n {
        let mut cut = n;
        while !s.is_char_boundary(cut) {
            cut -= 1;
        }
        format!("{}...", &s[..cut])
    } else {
        s
    }
}

fn statement_lines(block: &Block, out: &mut Vec<u32>) {
    for s in block.iter() {
        out.push(s.location.line);
        let mut blocks: Vec<&Block> = Vec::new();
        match &s.elem {
            Statement::While { block, .. }
            | Statement::DoWhile { block, .. }
            | Statement::ForInfinite { block }
            | Statement::ForLoop { block, .. }
            | Statement::Spawn { block, .. }
            | Statement::Label { block, .. } => blocks.push(block),
            Statement::ForList(f) => blocks.push(&f.block),
            Statement::ForKeyValue(f) => blocks.push(&f.block),
            Statement::ForRange(f) => blocks.push(&f.block),
            Statement::If { arms, else_arm } => {
                blocks.extend(arms.iter().map(|(_, b)| b));
                blocks.extend(else_arm.iter());
            }
            Statement::Switch { cases, default, .. } => {
                blocks.extend(cases.iter().map(|(_, b)| b));
                blocks.extend(default.iter());
            }
            Statement::TryCatch { try_block, catch_block, .. } => {
                blocks.push(try_block);
                blocks.push(catch_block);
            }
            _ => {}
        }
        for b in blocks {
            statement_lines(b, out);
        }
    }
}

/// Why a difference is not the converter's: the two parses see different preprocessor environments (dreammaker defines
/// `SPACEMAN_DMM` and knows BYOND's constants as built-ins; dmbc builds with the pinned BYOND defines) or dmbc keeps what dreammaker drops.
fn explain(da: &Value, db: &Value) -> Option<&'static str> {
    let ta = da.to_string();
    let tb = db.to_string();
    let env_markers = ["SpacemanDMM_", "\"guarded\"", "\"test_", "__verdigris_ffi_calls", "dq_test_shard_count", "dq_rx_flush", "schema_log"];
    if env_markers.iter().any(|m| tb.contains(m) && !ta.contains(m)) {
        return Some("environment: macro expands differently under SPACEMAN_DMM / test defines");
    }
    let upper_ident = |v: &Value| matches!(v.get("Ident"), Some(Value::String(s)) if s.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_'));
    let literalish = |v: &Value| v.get("Int").is_some() || v.get("Float").is_some() || v.get("String").is_some() || v.get("Expr").is_some();
    if upper_ident(db) && literalish(da) {
        return Some("environment: BYOND constant is a pinned macro in dmbc, a built-in name in dreammaker");
    }
    if let (Value::String(a), Value::String(b)) = (da, db) {
        let squash = |s: &str| s.chars().filter(|c| !c.is_whitespace()).collect::<String>();
        if squash(a) == squash(b) {
            return Some("environment: dreammaker's #x stringify puts spaces between tokens");
        }
        if a.replace('\\', "/") == b.replace('\\', "/") {
            return Some("environment: __FILE__ path separator");
        }
        if b.chars().all(|c| c.is_ascii_uppercase() || c == '_') {
            return Some("environment: macro defined only in dreammaker's parse");
        }
    }
    if da.get("Int").is_some() && db.get("Int").is_some() {
        return Some("environment: DM_VERSION/DM_BUILD differ");
    }
    if matches!(da.get("Base").and_then(|b| b.get("term")), Some(Value::String(t)) if t == "Null") {
        return Some("dreammaker drops an empty argument (`f(a, , b)`); dmbc keeps it as null, as BYOND does");
    }
    if ta.contains(crate::analysis_bridge::UNCONVERTED) {
        return Some("converter or dm-syntax gap (unconverted node)");
    }
    None
}

struct Example {
    site: String,
    dmbc: String,
    dm: String,
}

fn source_line(root: &Path, cache: &mut HashMap<String, Option<Vec<String>>>, file: &str, line: usize) -> String {
    let lines = cache.entry(file.to_owned()).or_insert_with(|| {
        std::fs::read(root.join(file)).ok().map(|b| String::from_utf8_lossy(&b).lines().map(str::to_owned).collect())
    });
    lines.as_ref().and_then(|l| l.get(line.wrapping_sub(1))).map(|s| s.trim().chars().take(160).collect()).unwrap_or_default()
}

/// The caller defines of dmbc's build: the pinned DM_VERSION/DM_BUILD.
pub(crate) fn native_defines() -> BTreeMap<String, String> {
    let mut defines = BTreeMap::new();
    crate::pinned_target::admit_defines(&mut defines).expect("the pinned target admits its own defaults");
    defines
}

/// One preprocessor environment for both parses: dreammaker's predefined macros (its BYOND constants, `SPACEMAN_DMM`, its DM_VERSION
/// and DM_BUILD) are replaced by exactly what dmbc's preprocess starts with, its pinned predefines plus the caller defines. So `NORTH`
/// is `1` on both sides, neither defines `SPACEMAN_DMM`, and both see BYOND 516.1687.
pub(crate) fn shared_environment() -> dq_analyze::sem::ParseEnvironment {
    let mut defines = dm_preprocess::regions::predefined_macros();
    defines.extend(native_defines().into_iter().map(|(n, v)| (n, None, v)));
    dq_analyze::sem::ParseEnvironment { defines }
}

/// Equal up to spelling the two preprocessors are free to differ in: a string that differs only in whitespace (`#x` stringify puts
/// spaces between tokens in dreammaker) or in path separators (`__FILE__`).
pub(crate) fn spelling_equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::String(x), Value::String(y)) => {
            x == y || {
                let squash = |s: &str| s.chars().filter(|c| !c.is_whitespace()).map(|c| if c == '\\' { '/' } else { c }).collect::<String>();
                squash(x) == squash(y)
            }
        }
        (Value::Object(x), Value::Object(y)) => x.len() == y.len() && x.iter().all(|(k, v)| y.get(k).is_some_and(|w| spelling_equal(v, w))),
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(v, w)| spelling_equal(v, w)),
        _ => a == b,
    }
}

pub fn run(dme: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let started = std::time::Instant::now();
    let root: PathBuf = dme.parent().map(Path::to_path_buf).filter(|p| !p.as_os_str().is_empty()).unwrap_or_else(|| PathBuf::from("."));
    let examples_per = std::env::var("DQ_PARITY_EXAMPLES").ok().and_then(|v| v.parse().ok()).unwrap_or(3usize);
    let category_count = std::env::var("DQ_PARITY_CATEGORIES").ok().and_then(|v| v.parse().ok()).unwrap_or(40usize);

    // dreammaker's parse runs beside the front end build.
    let dm_dme = dme.to_path_buf();
    let dm_thread = std::thread::Builder::new()
        .name("parity-dreammaker".into())
        .stack_size(64 * 1024 * 1024)
        .spawn(move || dq_analyze::sem::parse_for_checker_with_env(&dm_dme, &dm_dme, shared_environment()))?;

    let frontend = build_frontend(dme)?;
    eprintln!("analysis-parity: front end built in {:.1?}", started.elapsed());

    let parsed = dm_thread.join().map_err(|_| "dreammaker parse panicked")??;
    eprintln!("analysis-parity: dreammaker parse ready at {:.1?}", started.elapsed());
    let mut dm_file_ids: HashMap<String, dreammaker::FileId> = HashMap::new();
    let mut dm_paths: Vec<PathBuf> = Vec::new();
    parsed.files.for_each(|p| dm_paths.push(p.to_path_buf()));
    for p in &dm_paths {
        if let Some(id) = parsed.files.get_id(p) {
            dm_file_ids.insert(norm(&p.to_string_lossy()), id);
        }
    }

    // dreammaker bodies by (file, line).
    let mut dm_bodies: HashMap<(String, u32), Vec<&Block>> = HashMap::new();
    let mut dm_total = 0usize;
    let mut dm_path_cache: HashMap<dreammaker::FileId, String> = HashMap::new();
    for ty in parsed.objtree.iter_types() {
        for (_, tp) in ty.get().procs.iter() {
            for pv in &tp.value {
                let Some(code) = pv.code.as_ref() else { continue };
                let file = dm_path_cache.entry(pv.location.file).or_insert_with(|| norm(&parsed.files.get_path(pv.location.file).to_string_lossy())).clone();
                if file == "(builtins)" {
                    continue;
                }
                dm_total += 1;
                dm_bodies.entry((file, pv.location.line)).or_default().push(code);
            }
        }
    }

    // dmbc bodies, converted.
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut line_cache: HashMap<usize, (u32, dreammaker::FileId)> = HashMap::new();
    let mut converted: Vec<((String, u32), Block)> = Vec::new();
    let mut no_model = 0usize;
    let convert_started = std::time::Instant::now();
    for occurrence in frontend.bodies.iter() {
        let Ok(body) = arena.take_parsed(occurrence) else {
            no_model += 1;
            continue;
        };
        let Some(statements) = body.statement_body() else {
            no_model += 1;
            continue;
        };
        let file = norm(&occurrence.source.semantic_path);
        let fallback = dm_file_ids.get(&file).copied().unwrap_or_default();
        let mut locate = |offset: usize| -> dreammaker::Location {
            let (line, file) = *line_cache.entry(offset).or_insert_with(|| match frontend.debug_site(offset) {
                Some((path, line)) => (line as u32, dm_file_ids.get(&norm(&path)).copied().unwrap_or(fallback)),
                None => (0, fallback),
            });
            dreammaker::Location { file, line, column: 0 }
        };
        let block = analysis_bridge::convert_body_with(&statements.parsed().statements, &mut locate);
        converted.push(((file, occurrence.source.line as u32), block));
    }
    eprintln!("analysis-parity: {} bodies converted in {:.1?}", converted.len(), convert_started.elapsed());

    // Match.
    let mut dmbc_by_key: HashMap<(String, u32), Vec<Block>> = HashMap::new();
    for (k, b) in converted {
        dmbc_by_key.entry(k).or_default().push(b);
    }
    let mut matched = 0usize;
    let mut identical = 0usize;
    let mut raw_identical = 0usize;
    let mut spelling_identical = 0usize;
    let mut explained: BTreeMap<&'static str, usize> = BTreeMap::new();
    let mut line_identical = 0usize;
    let mut only_dmbc = 0usize;
    let mut only_dm = 0usize;
    let mut count_mismatch = 0usize;
    let mut only_dmbc_examples: Vec<String> = Vec::new();
    let mut only_dm_examples: Vec<String> = Vec::new();
    let mut line_examples: Vec<String> = Vec::new();
    let mut categories: BTreeMap<String, (usize, Vec<Example>)> = BTreeMap::new();
    let mut src_cache: HashMap<String, Option<Vec<String>>> = HashMap::new();
    let mut keys: Vec<_> = dmbc_by_key.keys().cloned().collect();
    keys.sort();
    for key in &keys {
        let mine = &dmbc_by_key[key];
        let Some(theirs) = dm_bodies.get(key) else {
            only_dmbc += mine.len();
            if only_dmbc_examples.len() < 12 {
                only_dmbc_examples.push(format!("{}:{}  {}", key.0, key.1, source_line(&root, &mut src_cache, &key.0, key.1 as usize)));
            }
            continue;
        };
        if mine.len() != theirs.len() {
            count_mismatch += 1;
        }
        // Pair each converted body with an identical dreammaker body when there is one, else in order.
        let mut used = vec![false; theirs.len()];
        let mut pairs: Vec<(usize, usize)> = Vec::new();
        let mut unpaired: Vec<usize> = Vec::new();
        for (i, b) in mine.iter().enumerate() {
            match (0..theirs.len()).find(|&j| !used[j] && **theirs[j] == **b) {
                Some(j) => {
                    used[j] = true;
                    pairs.push((i, j));
                }
                None => unpaired.push(i),
            }
        }
        for i in unpaired {
            match (0..theirs.len()).find(|&j| !used[j]) {
                Some(j) => {
                    used[j] = true;
                    pairs.push((i, j));
                }
                None => only_dmbc += 1,
            }
        }
        only_dm += used.iter().filter(|u| !**u).count();
        for (i, j) in pairs {
            matched += 1;
            let a = &mine[i];
            let b = theirs[j];
            let normalized = without_spaceman_settings(b);
            let b: &Block = normalized.as_ref().unwrap_or(b);
            if normalized.is_none() && **a == **b {
                raw_identical += 1;
            }
            if **a == **b {
                identical += 1;
                let (mut la, mut lb) = (Vec::new(), Vec::new());
                statement_lines(a, &mut la);
                statement_lines(b, &mut lb);
                if la == lb {
                    line_identical += 1;
                } else if line_examples.len() < 10 {
                    let at = la.iter().zip(&lb).position(|(x, y)| x != y).unwrap_or(0);
                    line_examples.push(format!(
                        "{}:{}  statement #{at}: dmbc line {:?} vs dreammaker line {:?}",
                        key.0,
                        key.1,
                        la.get(at),
                        lb.get(at)
                    ));
                }
                continue;
            }
            let mut va = serde_json::to_value(&**a).unwrap_or(Value::Null);
            let mut vb = serde_json::to_value(&**b).unwrap_or(Value::Null);
            // Find the first differing statement to report its line.
            let stmt_line = a.iter().zip(b.iter()).find(|(x, y)| x != y).map(|(x, _)| x.location.line).unwrap_or(key.1);
            strip(&mut va);
            strip(&mut vb);
            if spelling_equal(&va, &vb) {
                spelling_identical += 1;
                continue;
            }
            let mut path = Vec::new();
            let (da, db) = first_diff(&va, &vb, &mut path).unwrap_or((&va, &vb));
            let ctx: Vec<_> = path.iter().rev().take(2).rev().cloned().collect();
            if let Some(why) = explain(da, db) {
                *explained.entry(why).or_default() += 1;
            }
            let category = format!("{} | dmbc {} vs dreammaker {}", ctx.join(">"), kind(da), kind(db));
            let entry = categories.entry(category).or_default();
            entry.0 += 1;
            if entry.1.len() < examples_per {
                entry.1.push(Example {
                    site: format!("{}:{}  {}", key.0, stmt_line, source_line(&root, &mut src_cache, &key.0, stmt_line as usize)),
                    dmbc: short(da, 300),
                    dm: short(db, 300),
                });
            }
        }
    }
    for (key, theirs) in &dm_bodies {
        if !dmbc_by_key.contains_key(key) {
            only_dm += theirs.len();
            if only_dm_examples.len() < 12 {
                only_dm_examples.push(format!("{}:{}  {}", key.0, key.1, source_line(&root, &mut src_cache, &key.0, key.1 as usize)));
            }
        }
    }
    only_dm_examples.sort();

    let pct = |n: usize| 100.0 * n as f64 / matched.max(1) as f64;
    println!("dmbc bodies {} (no typed model {})  dreammaker bodies {}", dmbc_by_key.values().map(Vec::len).sum::<usize>(), no_model, dm_total);
    println!("matched {}  only dmbc {}  only dreammaker {}  keys with differing counts {}", matched, only_dmbc, only_dm, count_mismatch);
    println!("structurally identical as parsed {} ({:.2}%)", raw_identical, pct(raw_identical));
    println!("structurally identical without dreammaker's SPACEMAN_DMM-only `set SpacemanDMM_*` statements {} ({:.2}%)", identical, pct(identical));
    println!("identical with statement lines {} ({:.2}%)", line_identical, pct(line_identical));
    println!("equal up to stringify spacing / __FILE__ separators {}", spelling_identical);
    let converter_equal = identical + spelling_identical;
    println!("CONVERTER PARITY (one environment, spelling normalized) {} of {} ({:.2}%)", converter_equal, matched, pct(converter_equal));
    let explained_total: usize = explained.values().sum();
    println!("differences by cause (first difference per body): {} classified, {} other", explained_total, matched - converter_equal - explained_total);
    for (why, n) in &explained {
        println!("  {n:>6}  {why}");
    }
    let mut cats: Vec<_> = categories.into_iter().collect();
    cats.sort_by(|a, b| b.1 .0.cmp(&a.1 .0));
    println!("difference categories: {} (top {category_count})", cats.len());
    for (name, (n, examples)) in cats.iter().take(category_count) {
        println!("  {n:>6}  {name}");
        for e in examples {
            println!("          at {}", e.site);
            println!("            dmbc: {}", e.dmbc);
            println!("            dm:   {}", e.dm);
        }
    }
    if !line_examples.is_empty() {
        println!("line differences (structurally identical bodies):");
        for e in &line_examples {
            println!("  {e}");
        }
    }
    println!("only in dmbc (first {}):", only_dmbc_examples.len());
    for e in &only_dmbc_examples {
        println!("  {e}");
    }
    println!("only in dreammaker (first {}):", only_dm_examples.len());
    for e in &only_dm_examples {
        println!("  {e}");
    }
    eprintln!("analysis-parity: done in {:.1?}", started.elapsed());
    Ok(())
}

/// `--tree`: the declaration feed's object tree against dreammaker's (`analysis_tree`).
pub fn run_tree(dme: &Path) -> Result<(), Box<dyn std::error::Error>> {
    crate::analysis_tree::run(dme)
}

/// dmbc's front end of `dme` under its pinned defines and engine seed.
pub(crate) fn build_frontend(dme: &Path) -> Result<ColdFrontend, Box<dyn std::error::Error>> {
    build_frontend_with(dme, native_defines())
}

/// [`build_frontend`] under the caller's defines.
pub(crate) fn build_frontend_with(dme: &Path, defines: BTreeMap<String, String>) -> Result<ColdFrontend, Box<dyn std::error::Error>> {
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host.engine(dme.to_path_buf(), defines.clone(), true, include_bytes!("../../../fixtures/native_template.bin").to_vec())?;
    let frontend = dm_tree::frontend::build_with_config(
        dme,
        &dm_preprocess::FileSystem,
        &defines,
        dm_tree::frontend::FrontendConfig { workers, engine: Some(engine.frontend_seed()), observer: None },
    )
    .map_err(|d| format!("front end failed: {} diagnostic(s), first: {:?}", d.len(), d.first().map(|x| &x.message)))?;
    Ok(frontend)
}
