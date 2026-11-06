//! Original image_dir_after_build receiver and location DATA.
//! Does not register report authority or claim a complete host/model receipt.
use super::*;
use crate::image_dir_body::{self, Event, Phase};
use crate::policy_body_demand::WorkspaceWork;
use dm_tree::frontend::OriginalImageDirFrontend;
use dm_tree::SemanticTree;
use std::path::Path;

#[derive(Debug, Eq, PartialEq)]
pub struct ImageDirFinding {
    pub relative: String,
    pub line: usize,
}

fn own<W: WorkspaceWork>(text: &str, work: &mut W) -> Result<String, W::Error> {
    work.checkpoint()?;
    let mut result = String::new();
    if W::CHECKED {
        result.try_reserve_exact(text.len()).map_err(|_| work.allocation_failed())?;
    }
    result.push_str(text);
    Ok(result)
}

// The legacy Prefab type projection ignores tree-path operator spelling and
// its field overrides. Use it only on an actual issued Prefab shape.
fn prefab_path<W: WorkspaceWork>(path: &str, work: &mut W) -> Result<String, W::Error> {
    let mut result = String::new();
    if W::CHECKED {
        let bound = path.len().checked_add(1).ok_or_else(|| work.overflow())?;
        result.try_reserve_exact(bound).map_err(|_| work.allocation_failed())?;
    }
    for part in path.split(['/', '.', ':']).filter(|part| !part.is_empty()) {
        work.checkpoint()?;
        result.push('/');
        result.push_str(part);
    }
    if result.is_empty() {
        result.push('/');
    }
    Ok(result)
}

pub trait ImageDirWork: WorkspaceWork {
    fn operational(&mut self, error: std::io::Error) -> Self::Error;
}

fn formal_return<W: WorkspaceWork>(
    tree:&SemanticTree, formal:Option<dm_tree::MemberId>, work:&mut W,
)->Result<Option<String>,W::Error>{
    let Some(formal)=formal else{return Ok(None)};
    let node=tree.member(formal).ok_or("image dir issued formal member absent")?;
    let signature=&node.metadata.procedure.as_ref().ok_or("image dir formal signature absent")?.signature;
    let Some(annotation)=&signature.return_annotation else{return Ok(None)};
    let text=annotation.source_text(tree.symbols()).ok_or("image dir formal annotation spelling unavailable")?;
    if !text.trim_start().starts_with('/') {return Ok(None)}
    // The pinned TypePath grammar has only slash and identifier components.
    let needed=text.len().checked_add(128).ok_or_else(||work.overflow())?;
    work.temporary(needed)?;
    let mut path=String::new();
    path.try_reserve_exact(text.len()).map_err(|_|work.allocation_failed())?;
    if path.capacity()>text.len(){return Err(work.allocation_failed())}
    for part in text.trim().split('/').skip(1){
        work.checkpoint()?;
        let part=part.trim();
        if part.is_empty()||!part.bytes().all(|byte|byte.is_ascii_alphanumeric()||byte==b'_'){
            return Err("image dir formal return path has unsupported original tokens".into());
        }
        path.push('/');
        path.push_str(part);
    }
    Ok(Some(path))
}

fn callable_return<W: ImageDirWork>(
    inputs:&OriginalImageDirFrontend,owner:SymbolId,name:&str,work:&mut W,
)->Result<Option<String>,W::Error>{
    let archive=inputs.archive();
    let tree=archive.tree();
    if tree.lookup_type(owner).is_none(){return Ok(None)}
    let mut first=None;
    let selected=inputs.callable(owner,SymbolId::of(name),&mut||{
        if first.is_some(){return Err(std::io::ErrorKind::Interrupted.into())}
        work.checkpoint().map_err(|error|{first=Some(error);std::io::ErrorKind::Interrupted.into()})
    });
    if let Some(error)=first{return Err(error)}
    let selected=selected.map_err(|error|work.operational(error))?;
    if let Some(path)=formal_return(tree,selected.formal,work)?{return Ok(Some(path))}
    let Some(ordinal)=selected.body else{return Ok(None)};
    let occurrence=archive.occurrences().get(ordinal).ok_or("image dir selected body ordinal is unavailable")?;
    if Some(occurrence.member)!=selected.value{return Err("image dir selected body member differs".into())}
    let body=work.body(archive,ordinal)?;
    if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){
        return Err("image dir return fact received a foreign original body".into());
    }
    image_dir_body::first_return_prefab(&body,work)?.map(|path|prefab_path(path,work)).transpose()
}

fn field<W: WorkspaceWork>(
    scope: &Walker<'_, SemanticTree>, owner: SymbolId, name: &str, work: &mut W,
) -> Result<Option<String>, W::Error> {
    if scope.tree.lookup_type(owner).is_none() {
        return Ok(None);
    }
    scope.field_type_using(owner, name, &mut || work.checkpoint())
}

fn receiver<W: ImageDirWork>(
    scope: &Walker<'_, SemanticTree>, inputs: &OriginalImageDirFrontend, expression: &Expr, work: &mut W,
) -> Result<Option<String>, W::Error> {
    work.checkpoint()?;
    let global = SymbolId::of("/");
    match &expression.kind {
        ExprKind::Group(node) => receiver(scope, inputs, node, work),
        ExprKind::Ident(name) if name == "src" => {
            if scope.owner == global { return Ok(None) }
            own(scope.tree.symbols().text(scope.owner).ok_or("image dir owner spelling absent")?, work).map(Some)
        }
        ExprKind::Ident(name) if name == "usr" => own("/mob", work).map(Some),
        ExprKind::Ident(name) => {
            if let Some(path) = scope.locals.get(name) {
                return if path.is_empty() { Ok(None) } else { own(path, work).map(Some) };
            }
            if scope.owner != global {
                if let Some(path) = field(scope, scope.owner, name, work)? {
                    return Ok((!path.is_empty()).then_some(path));
                }
            }
            Ok(field(scope, global, name, work)?.filter(|path| !path.is_empty()))
        }
        ExprKind::Member { object, selector, .. } | ExprKind::SafeMember { object, selector, .. } => {
            let Some(owner) = receiver(scope, inputs, object, work)? else { return Ok(None) };
            Ok(field(scope, SymbolId::of(&owner), selector, work)?.filter(|path| !path.is_empty()))
        }
        ExprKind::Unary { op, value } if op == "new" => {
            let target: &Expr = match &value.kind { ExprKind::Call { callee, .. } => callee, _ => value };
            let target: &Expr = match &target.kind { ExprKind::ObjectInitializer { object, .. } => object, _ => target };
            match &target.kind {
                ExprKind::TypePath(path) if path != "/" => prefab_path(path, work).map(Some),
                _ => Ok(None),
            }
        }
        ExprKind::Call { callee, .. } => match &callee.kind {
            ExprKind::Ident(name) if name == "image" => own("/image", work).map(Some),
            ExprKind::Ident(name) if name == "mutable_appearance" => own("/mutable_appearance", work).map(Some),
            ExprKind::Ident(name) if crate::original_base_terms::ordinary_call_name(name) => {
                if scope.owner != global {
                    if let Some(path) = callable_return(inputs, scope.owner, name, work)? {
                        return Ok(Some(path));
                    }
                }
                callable_return(inputs, global, name, work)
            }
            ExprKind::Unary { op, value } if op == "::" => {
                let ExprKind::Ident(name) = &value.kind else { return Err("image dir original global call lacks an identifier".into()) };
                callable_return(inputs, global, name, work)
            }
            ExprKind::Member { object, selector, .. } | ExprKind::SafeMember { object, selector, .. } => {
                let Some(owner) = receiver(scope, inputs, object, work)? else { return Ok(None) };
                callable_return(inputs, SymbolId::of(&owner), selector, work)
            }
            _ => Ok(None),
        },
        _ => Ok(None),
    }
}

fn is_image<W: WorkspaceWork>(tree: &SemanticTree, path: &str, work: &mut W) -> Result<bool, W::Error> {
    let mut cursor = tree.lookup_type(SymbolId::of(path));
    let mut remaining = tree.types().len();
    while let Some(ty) = cursor {
        work.checkpoint()?;
        remaining = remaining.checked_sub(1).ok_or("image dir type ancestry cycles")?;
        let path = tree.type_node(ty).ok_or("image dir type ancestry unavailable")?.path;
        if path == SymbolId::of("/image") || path == SymbolId::of("/mutable_appearance") {
            return Ok(true);
        }
        cursor = tree.parent(ty);
    }
    Ok(false)
}

fn dir_receiver<'a, W: WorkspaceWork>(mut node: &'a Expr, work: &mut W) -> Result<Option<&'a Expr>, W::Error> {
    while let ExprKind::Group(inner) = &node.kind {
        work.checkpoint()?;
        node = inner;
    }
    match &node.kind {
        ExprKind::Member { object, selector, .. } | ExprKind::SafeMember { object, selector, .. } if selector == "dir" => Ok(Some(object)),
        _ => Ok(None),
    }
}

// Legacy engine_line shifts the statement's numeric line using the procedure
// file's lone-CR rows. The line can exceed the procedure file's physical EOF:
// the statement itself can belong to another registered compiler input.
fn legacy_report_line<W: WorkspaceWork>(
    owner: &dm_tree::frontend::SourceFile, statement: usize, work: &mut W,
) -> Result<usize, W::Error> {
    if statement == 0 {
        return Err("image dir original statement line is absent".into());
    }
    let bytes = owner.text.as_str().as_bytes();
    let mut physical_line = 1usize;
    let mut extra = 0usize;
    for (index, byte) in bytes.iter().enumerate() {
        if physical_line >= statement {
            break;
        }
        if index % 1024 == 0 {
            work.checkpoint()?;
        }
        match *byte {
            b'\n' => physical_line = physical_line.checked_add(1).ok_or_else(|| work.overflow())?,
            b'\r' if bytes.get(index + 1) != Some(&b'\n') => {
                extra = extra.checked_add(1).ok_or_else(|| work.overflow())?;
            }
            _ => {}
        }
    }
    statement.checked_add(extra).ok_or_else(|| work.overflow())
}

pub fn image_dir_findings_using<W: ImageDirWork>(
    inputs: &OriginalImageDirFrontend, root: &Path, exempt: impl Fn(&str) -> bool, work: &mut W,
) -> Result<Vec<ImageDirFinding>, W::Error> {
    let archive=inputs.archive();
    let tree=archive.tree();
    let paths=std::iter::once(root).chain(inputs.files().iter().filter(|file|file.captured).map(|file|file.path.as_path()));
    let temp = stored_refs::maximum_policy_temporary_width_for_paths_using(archive, paths, || work.checkpoint(), W::CHECKED)?
        .checked_mul(64).and_then(|bytes| bytes.checked_add(4096)).ok_or_else(|| work.overflow())?;
    work.temporary(temp)?;
    let mut findings = Vec::new();
    for (ordinal, occurrence) in archive.occurrences().iter().enumerate() {
        work.checkpoint()?;
        // Old ProcValue.location is recorded after consuming the opening
        // parenthesis, not at the first expanded token of the declaration.
        let headers = archive.callable_header_source();
        let header = headers.reported_point(occurrence.member)?;
        let (registered, _, _) = header.reported_coordinates();
        let relative = dm_preprocess::regions::relative_filesystem_path(registered, root)
            .unwrap_or_else(|| registered.to_path_buf());
        let relative = dm_preprocess::regions::canonical_path(&relative).to_string_lossy().replace('\\', "/");
        if !relative.starts_with("code/") || exempt(&relative) {
            continue;
        }
        let file = inputs.file_exact(header.physical_path()).ok_or("image dir selected procedure source is not captured as compiled")?;
        let body = work.body(archive, ordinal)?;
        if !body.belongs_to(archive) || !std::ptr::eq(body.occurrence(), occurrence) {
            return Err("image dir selected procedure received a foreign body".into());
        }
        let locals = body.source_locals()?;
        let temporary = locals.scope_admission()?.checked_add(temp).ok_or_else(|| work.overflow())?;
        work.temporary(temporary)?;
        let mut scope = stored_refs_scope::archived_stored_scope_using(&body, &[], locals, work)?.walker;
        image_dir_body::observe(&body, Phase::Initializers, work, |work, event| {
            let Event::Initializer(statement) = event else { return Err("image dir initializer phase received an assignment".into()) };
            let StatementKind::Var { value: Some(value), .. } = &statement.kind else { return Err("image dir initializer shape differs".into()) };
            let [fact] = body.statement_body().parsed().local_variables.in_span(statement.header_span)? else {
                return Err("image dir initializer lacks one exact authored local".into());
            };
            if locals.type_path(fact)?.is_some() {
                return Ok(());
            }
            let name = locals.name(fact)?;
            let Some(path) = receiver(&scope, inputs, value, work)? else { return Ok(()) };
            let entry = scope.locals.get_mut(name).ok_or("image dir initializer absent from seeded local scope")?;
            let bytes = path.capacity().checked_add(128).ok_or_else(|| work.overflow())?;
            work.retain(bytes)?;
            *entry = path;
            Ok(())
        })?;
        image_dir_body::observe(&body, Phase::Assignments, work, |work, event| {
            let Event::Assignment { target, statement, .. } = event else { return Err("image dir assignment phase received an initializer".into()) };
            let Some(target) = dir_receiver(target, work)? else { return Ok(()) };
            let Some(path) = receiver(&scope, inputs, target, work)? else { return Ok(()) };
            if !is_image(tree, &path, work)? {
                return Ok(());
            }
            // Only the actual primary-reported point can supply this scalar.
            // Keep the file from the callable header, as the old lint did.
            let point = archive.borrowed_source_note_point(statement.start)?;
            let (_, statement_line, _) = point.reported_coordinates();
            let line = legacy_report_line(file, statement_line, work)?;
            let bytes = relative.len().checked_add(256).ok_or_else(|| work.overflow())?;
            work.retain(bytes)?;
            findings.try_reserve(1).map_err(|_| work.allocation_failed())?;
            findings.push(ImageDirFinding { relative: own(&relative, work)?, line });
            Ok(())
        })?;
    }
    findings.sort_unstable_by(|a, b| a.relative.cmp(&b.relative).then(a.line.cmp(&b.line)));
    findings.dedup();
    work.checkpoint()?;
    Ok(findings)
}
