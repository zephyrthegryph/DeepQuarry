//! Independent variable-visibility findings from the ORIGINAL native owner/Db.
use std::{path::Path, sync::Arc};
#[path = "../../dm-analysis/examples/support/acquired_files.rs"]
mod acquired_files;
#[path = "../../dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let project = std::env::args()
        .nth(1)
        .ok_or("expected explicit DME fixture")?;
    let project = Path::new(&project);
    if !project.is_absolute() {
        return Err("fixture must be caller-absolute".into());
    }
    let files = acquired_files::AcquiredFiles::default();
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1)?;
    let db = Arc::new(dmbc::query_db::QueryDb::default());
    let diagnostic_mode = std::env::args()
        .skip(2)
        .any(|arg| arg == "--diagnostic-declarations");
    let (archive, _diagnostic_owner) = if diagnostic_mode {
        let front = dm_tree::frontend::build_for_checker_diagnostics(
            project,
            &files,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
            None,
            &executor,
        )
        .map_err(|e| format!("native diagnostic frontend: {e:?}"))?
        .with_body_queries(db.clone())?;
        let archive = Arc::clone(front.source_view()?.archive());
        (archive, Some(front))
    } else {
        let front = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
            project,
            &files,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
            None,
            &executor,
            None,
            true,
        )
        .map_err(|e| format!("native visibility frontend: {e:?}"))?
        .with_body_queries(db.clone());
        let archive = front.body_archive().ok_or("original archive unavailable")?;
        (archive, None)
    };
    let profile = archive
        .tree()
        .checker_builtin_profile()
        .ok_or("pinned checker profile unavailable")?;
    let context = dm_analysis::checker_context::CheckerContext::archived(
        &archive,
        db.as_ref(),
        archive.tree(),
        profile,
    )?;
    let selected = dm_analysis::check_configuration::select(project, None);
    let config = match std::fs::read(&selected.path) {
        Ok(bytes) => Some(bytes),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => return Err(e.into()),
    };
    let loaded = dm_analysis::check_configuration::load(
        &selected,
        dm_analysis::check_configuration::Capture {
            path: &selected.path,
            read: match &config {
                Some(bytes) => dm_analysis::check_configuration::CapturedRead::Bytes(bytes),
                None => dm_analysis::check_configuration::CapturedRead::AutodetectAbsent,
            },
        },
    )?;
    for finding in context.variable_visibility_archived(&loaded.policy, || Ok(()))? {
        let d = finding.finding.diagnostic();
        let at = finding.finding.origin();
        let severity = match finding.severity {
            dm_analysis::check_policy::DiagnosticSeverity::Error => "error",
            dm_analysis::check_policy::DiagnosticSeverity::Warning => "warning",
            dm_analysis::check_policy::DiagnosticSeverity::Info => "info",
            dm_analysis::check_policy::DiagnosticSeverity::Hint => "hint",
        };
        let notes=d.notes.iter().map(|n|{let s=n.source.as_ref().expect("visibility definitions require exact issued note points");serde_json::json!({"file":s.path,"line":s.line,"column":s.byte_column,"message":n.message})}).collect::<Vec<_>>();
        println!(
            "{}",
            serde_json::json!({"family":d.family,"registration_tag":finding.finding.registration_tag(),"file":at.path,"line":at.line,"column":at.byte_column,"severity":severity,"message":d.message,"notes":notes})
        );
    }
    Ok(())
}
