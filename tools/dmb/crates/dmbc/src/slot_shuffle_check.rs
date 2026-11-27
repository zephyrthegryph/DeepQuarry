//! `dmbc slot-shuffle-check [dme] [seed]`: the guard that no reader takes a member slot number for declaration order.
//!
//! Builds the analysis front end of `dme` cold twice in this process, once with member slots numbered in declaration order and
//! once with them shuffled (`dm_tree::member_order::shuffle`), and compares what analysis reads from each: the object tree
//! dq-analyze's model is built from (`analysis_tree::parse_from_front`, with its diagnostics) and DreamChecker's native input
//! (`dreamchecker_input::with_input`: types, declarations, values, body indexes and body statements). Every line must be equal;
//! the first differences are printed. The compile side is checked by compiling with `DMB_MEMBER_SLOT_SHUFFLE=<seed>` and
//! comparing the output with an ordinary compile.
use std::path::Path;

/// One line per type (and per body), in the order the conversion produced them.
struct Lines {
    analysis: Vec<String>,
    checker: Vec<String>,
}

fn lines(dme: &Path) -> Result<Lines, String> {
    let started = std::time::Instant::now();
    let front = crate::analysis_tree::front(dme)?;
    eprintln!("slot-shuffle-check: front end in {:.1?}", started.elapsed());
    let mut checker = Vec::new();
    crate::dreamchecker_input::with_input(&front, |input, registered, stats| {
        for ty in &input.model.types {
            checker.push(format!(
                "type {} at {:?} parent {:?}/{:?} children {:?} vars {:?} procs {:?}",
                ty.path, ty.location, ty.parent_path, ty.parent_type, ty.children, ty.vars, ty.procs
            ));
        }
        for (index, body) in input.bodies.iter().enumerate() {
            checker.push(format!("body {index} {:x}", xxhash_rust::xxh3::xxh3_128(format!("{:?}", body.statements).as_bytes())));
        }
        for hint in &registered {
            checker.push(format!("registered {hint}"));
        }
        checker.push(format!("stats {} bodies {} vars {} procs", stats.bodies, stats.vars, stats.procs));
    });
    let parsed = crate::analysis_tree::parse_from_front(front, true);
    dq_analyze::sem::model_store::ensure_codec();
    let mut analysis = Vec::new();
    for ty in parsed.objtree.iter_types() {
        analysis.push(serde_json::to_string(ty.get()).map_err(|e| e.to_string())?);
    }
    analysis.extend(parsed.errors.iter().map(|e| format!("error {e}")));
    if let Some(raw) = &parsed.raw {
        analysis.extend(raw.stream.iter().map(|e| format!("stream {e}")));
        analysis.extend(raw.finish.iter().map(|e| format!("finish {e}")));
        analysis.push(format!("summary {:?}", raw.summary));
    }
    eprintln!("slot-shuffle-check: converted in {:.1?}", started.elapsed());
    Ok(Lines { analysis, checker })
}

fn compare(what: &str, plain: &[String], shuffled: &[String]) -> usize {
    let mut differences = 0;
    for index in 0..plain.len().max(shuffled.len()) {
        let (a, b) = (plain.get(index), shuffled.get(index));
        if a != b {
            differences += 1;
            if differences <= 5 {
                let cut = |line: Option<&String>| line.map_or("<none>".to_string(), |l| l.chars().take(600).collect());
                eprintln!("slot-shuffle-check: {what} line {index} differs\n  plain:    {}\n  shuffled: {}", cut(a), cut(b));
            }
        }
    }
    println!("slot-shuffle-check: {what}: {} lines, {differences} differ", plain.len());
    differences
}

pub fn run(dme: &Path, seed: u64) -> Result<(), Box<dyn std::error::Error>> {
    dm_tree::member_order::shuffle::set_process_seed(0);
    let plain = lines(dme)?;
    dm_tree::member_order::shuffle::set_process_seed(seed);
    let shuffled = lines(dme)?;
    dm_tree::member_order::shuffle::set_process_seed(0);
    let differences = compare("analysis object tree", &plain.analysis, &shuffled.analysis)
        + compare("dreamchecker input", &plain.checker, &shuffled.checker);
    if differences != 0 {
        return Err(format!("{differences} lines depend on member slot numbers (seed {seed})").into());
    }
    println!("slot-shuffle-check: equal with member slots shuffled (seed {seed})");
    Ok(())
}
