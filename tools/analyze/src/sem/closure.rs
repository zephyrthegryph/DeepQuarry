//! `analyze sem closure [--write]`: what changed when the lints moved from the legacy read walk to the closed walk.
//!
//! The lints (`untracked_inputs`, `sem/reads`) used to judge handlers with a walk that skipped the engine-internal directories, followed a
//! call on the receiver's static type only and stopped at every global proc without `READS_FROM`. They now judge the closed walk
//! ([`ReadsEngine::closed`], the one the generated subscriptions already used): engine bodies are entered, a virtual call is the union of its
//! overrides, a global proc is walked like any other, and global state is classified (`sem/globals.rs`). The two are compared here: what only
//! the closed walk finds was invisible to the old baseline (the measurement changed; the code did not), and what only the old walk reported
//! was a site the closed walk walks into and resolves.
//!
//! `--write` writes `doc/rewrite/reads_closure_newly_visible.md`; without it the report goes to stdout.

use crate::{tree::Tree,gens::deps,reactive_dependency_view::Analysis};
struct LegacyLines<'a>(&'a Tree);
impl crate::reactive_closure_report::Lines for LegacyLines<'_>{fn line(&self,relative:&str,line:u32)->Option<&str>{self.0.get(relative)?.raw().text.split('\n').nth(line as usize-1)}}
pub fn report(tree:&Tree)->Option<String>{let base=deps::analyzed_legacy(tree);let closed=deps::analyzed(tree);let(base,closed)=(base.as_ref().as_ref()?,closed.as_ref().as_ref()?);Some(crate::reactive_closure_report::report(Analysis::Owned(base),Analysis::Owned(closed),&LegacyLines(tree)))}

/// The `analyze sem closure` command.
pub fn run(tree: &Tree, root: &std::path::Path, write: bool) -> std::process::ExitCode {
    let Some(text) = report(tree) else {
        eprintln!("analyze sem closure: the semantic model could not be built");
        return std::process::ExitCode::from(2);
    };
    if write {
        let path = root.join("doc/rewrite/reads_closure_newly_visible.md");
        if let Err(e) = std::fs::write(&path, &text) {
            eprintln!("analyze sem closure: {}: {}", path.display(), e);
            return std::process::ExitCode::from(2);
        }
        println!("wrote {}", path.display());
    } else {
        print!("{}", text);
    }
    std::process::ExitCode::SUCCESS
}
