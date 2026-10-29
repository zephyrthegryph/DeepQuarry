//! Independent declaration-token oracle: actual old Sem versus current native
//! primary-token/source receipt. No expected native rows or fallback parser.
use dq_analyze::run::{registry, Engine, Options};
use std::{collections::BTreeMap, path::PathBuf};
#[path = "../../dmb/crates/dm-analysis/examples/support/acquired_files.rs"]
mod acquired_files;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(std::env::args().nth(1).ok_or("expected fixture root")?);
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let points = std::env::args().any(|arg| arg == "--points");
    let unsupported = std::env::args().any(|arg| arg == "--expect-unsupported");
    let old = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root.clone()),
            lints: vec!["untyped".into()],
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let sem = dq_analyze::sem::sem_for(&old.tree).ok_or("old semantic oracle unavailable")?;
    if std::env::args().any(|arg| arg == "--audit-old") {
        let mut declarations = Vec::new();
        for ty in sem.objtree.iter_types() {
            let owner = if ty.get().path.is_empty() {
                "/"
            } else {
                ty.get().path.as_str()
            };
            for (name, value) in &ty.get().vars {
                let Some(declaration) = &value.declaration else {
                    continue;
                };
                if declaration.location.is_builtins() {
                    continue;
                }
                let signature = sem.var_decl_unrecorded(owner, name);
                declarations.push(serde_json::json!({"owner":owner,"name":name.to_string(),
                    "raw_declaration":{"file":sem.rel(declaration.location),"line":declaration.location.line,"column":declaration.location.column},
                    "raw_value":{"file":sem.rel(value.value.location),"line":value.value.location.line,"column":value.value.location.column},
                    "var_decl":signature.map(|sig|serde_json::json!({"file":sig.file,"line":sig.line,"declared":sig.declared,"static":sig.is_static,"const":sig.is_const}))}));
            }
        }
        if declarations.is_empty() {
            return Err("old authored declaration audit is empty".into());
        }
        println!(
            "{}",
            serde_json::json!({"scope":"independent-old-authored-locations-audit","declarations":declarations,"native_parity_claimed":false})
        );
        return Ok(());
    }
    let mut expected = BTreeMap::new();
    for ty in sem.objtree.iter_types() {
        let owner = if ty.get().path.is_empty() {
            "/"
        } else {
            ty.get().path.as_str()
        };
        for (name, value) in &ty.get().vars {
            let Some(decl) = &value.declaration else {
                continue;
            };
            let file = sem.rel(decl.location);
            if !decl.location.is_builtins() && !file.is_empty() {
                expected.insert(
                    (owner.to_owned(), name.to_string()),
                    (
                        file.to_owned(),
                        decl.location.line as usize,
                        if points {
                            decl.location.column as usize
                        } else {
                            0
                        },
                    ),
                );
            }
        }
    }
    if expected.is_empty() {
        return Err("empty old declaration oracle cannot prove this fixture".into());
    }
    let files = acquired_files::AcquiredFiles::default();
    let executor = dm_exec::BuildExecutor::new(1).map_err(|e| format!("native executor: {e:?}"))?;
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),
        &files,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .map_err(|e| format!("native frontend: {e:?}"))?;
    let archive = frontend.body_archive().ok_or("native archive not issued")?;
    let tree = archive.tree();
    let mut actual = BTreeMap::new();
    let mut refusals = Vec::new();
    for (member, node) in tree.members().iter().enumerate() {
        if node.kind != dm_tree::MemberKind::Var
            || node.definition != dm_tree::DefinitionMode::Declare
        {
            continue;
        }
        let owner = tree
            .symbols()
            .text(
                tree.type_node(node.owner)
                    .ok_or("member owner unavailable")?
                    .path,
            )
            .ok_or("owner spelling unavailable")?;
        let name = tree
            .symbols()
            .text(node.name)
            .ok_or("name spelling unavailable")?;
        let member = dm_tree::MemberId(member as u32);
        let result = archive
            .member_policy_compatibility_cursor(member)
            .and_then(|origin| {
                let rel = dm_preprocess::regions::relative_filesystem_path(&origin.path, &root)
                    .ok_or("foreign compatibility path")?
                    .to_string_lossy()
                    .replace('\\', "/");
                let column = if points {
                    origin
                        .byte_column
                        .ok_or("line-only macro receipt has no compatibility column")?
                } else {
                    0
                };
                Ok((rel, origin.line, column))
            });
        match result {
            Ok((rel, line, column)) => {
                actual.insert((owner.to_owned(), name.to_owned()), (rel, line, column));
            }
            Err(error) => refusals.push(format!("{owner}::{name}: {error}")),
        }
    }
    if unsupported {
        if refusals.is_empty() {
            return Err("expected an explicit unsupported original token case".into());
        }
        println!(
            "{}",
            serde_json::json!({"scope":"declaration-token/explicit-unsupported-fixture","native_findings_emitted":false,"refusals":refusals,"reference_declarations":expected.iter().map(|((owner,name),(file,line,column))|serde_json::json!({"owner":owner,"name":name,"file":file,"line":line,"byte_column":column})).collect::<Vec<_>>() })
        );
        return Ok(());
    }
    if !refusals.is_empty() {
        return Err(format!("unsupported declaration coordinates: {refusals:?}").into());
    }
    if expected != actual {
        return Err(format!(
            "old declaration token rows {expected:?} differ from native {actual:?}"
        )
        .into());
    }
    println!(
        "{}",
        serde_json::json!({"scope":"declaration-token/independent-old-Sem","declarations":expected.len(),"matched":true,"full_workspace_parity":false})
    );
    Ok(())
}
