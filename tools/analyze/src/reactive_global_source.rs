//! Borrowed actual-source seam for the SAME global/write classifier.
//! No semantic model, source receipt, body clone, cache or default provider.
use crate::{captured_generator_budget::Budget,reactive_reads_native::Failure,reactive_original_source::ReadSource};
use std::sync::Arc;
use dm_tree::MemberKind;
pub(crate) struct Callable<'a>{pub owner:&'a str,pub name:&'a str,pub ordinal:usize,pub member:dm_tree::MemberId,pub header:usize}
pub(crate) enum SelectedCallable<'a>{Source(Callable<'a>),Builtin,Missing}
pub(crate) trait Body{
 fn statement_body(&self)->&dm_tree::frontend::StatementBody;
 fn source_locals(&self)->Result<dm_tree::frontend::SourceLocalView<'_>,String>;
 fn source_parameters(&self)->Result<dm_tree::frontend::SourceParameterView<'_>,String>;
}
impl Body for dm_tree::frontend::ArchivedBody<'_>{
 fn statement_body(&self)->&dm_tree::frontend::StatementBody{self.statement_body()}
 fn source_locals(&self)->Result<dm_tree::frontend::SourceLocalView<'_>,String>{self.source_locals()}
 fn source_parameters(&self)->Result<dm_tree::frontend::SourceParameterView<'_>,String>{self.source_parameters()}
}
impl Body for dm_tree::frontend::GenerationBodyLoan<'_>{
 fn statement_body(&self)->&dm_tree::frontend::StatementBody{self.statements()}
 fn source_locals(&self)->Result<dm_tree::frontend::SourceLocalView<'_>,String>{self.source_locals()}
 fn source_parameters(&self)->Result<dm_tree::frontend::SourceParameterView<'_>,String>{self.source_parameters()}
}
pub(crate) trait Source{
 fn occurrences(&self)->&[dm_tree::frontend::BodyOccurrence];
 fn raw_body_text(&self,ordinal:usize)->Result<&str,Failure>;
 fn variable(&self,owner:&str,name:&str)->Result<Option<crate::reactive_original_source::ReadVariable<'_>>,Failure>;
 fn callable(&self,owner:&str,name:&str)->Result<SelectedCallable<'_>,Failure>;
 fn parent_callable(&self,ordinal:usize)->Result<Option<Callable<'_>>,Failure>;
 fn visit_overrides<'source>(&'source self,owner:&str,name:&str,poll:&mut dyn FnMut()->Result<(),Failure>,emit:&mut dyn FnMut(Callable<'source>)->Result<(),Failure>)->Result<(),Failure>;
 fn site(&self,ordinal:usize,offset:usize)->Result<(String,u32),Failure>;
 fn site_line(&self,ordinal:usize,line:u32)->Result<(String,u32),Failure>;
 fn line_at(&self,offset:usize)->Result<u32,Failure>;
 fn reserve(&self,bytes:Option<usize>)->Result<(),Failure>{let bytes=bytes.ok_or_else(||{self.budget().deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original question allocation overflow"))})?;self.budget().charge(bytes).map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}
 fn parent_type(&self,owner:&str)->Result<Option<&str>,Failure>;
 fn own_callable_exists(&self,owner:&str,name:&str)->Result<bool,Failure>;
 fn dependency_marker_rows(&self,poll:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'_>,Failure>;
 fn dependency_defines(&self)->Result<std::collections::BTreeSet<String>,Failure>{let mut defines=std::collections::BTreeSet::new();if !self.with_policy_files(&mut|_,views|{crate::raw_key_calls_policy::visit_headers_admitted(views.marker()?,|_,_|{},|name|{defines.insert(name.to_owned());},|bytes|{self.checkpoint()?;self.reserve(Some(bytes))},||{self.budget().deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"dependency define capacity overflow"))})?;Ok(true)})?{return Err("original define traversal incomplete".into())}self.checkpoint()?;self.require()?;Ok(defines)}
 fn marker_rows(&self,poll:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'_>,Failure>;
 fn raw_metadata(&self,poll:&mut dyn FnMut()->std::io::Result<()>,emit:&mut dyn FnMut(&str,crate::raw_reactive_metadata_policy::Event<'_>)->Result<(),Failure>)->Result<(),Failure>;
 fn raw_width(&self)->Result<usize,Failure>;
 fn definition_neighbors(&self,relative:&str,line:u32,poll:&mut dyn FnMut()->Result<(),Failure>)->Result<(Option<(usize,&str,&str)>,Option<(usize,&str,&str)>),Failure>;
 fn with_policy_files(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>;
 fn with_reaction_code(&self,hint:&str,visit:&mut dyn FnMut(&str,&crate::tree::View)->Result<bool,Failure>)->Result<(),Failure>{self.with_policy_files(&mut|relative,views|{if !views.raw()?.contains(hint){return Ok(true)}visit(relative,views.code()?)})?;Ok(())}
 fn member_has_source(&self,member:dm_tree::MemberId)->Result<bool,Failure>;
 fn with_header_line(&self,member:dm_tree::MemberId,consume:&mut dyn FnMut(&str,usize,&str)->Result<(),Failure>)->Result<(),Failure>;
 fn visit_setter_definitions(&self,emit:&mut dyn FnMut(&str,&str)->Result<(),Failure>)->Result<(),Failure>{visit_setter_definitions_original(self,emit)}
 fn visit_own_declared_variables(&self,emit:&mut dyn FnMut(&str,&str)->Result<(),Failure>)->Result<(),Failure>{visit_own_declared_variables_original(self,emit)}
 fn visit_setter_call_files(&self,emit:&mut dyn FnMut(&str,&str,&str)->Result<(),Failure>)->Result<(),Failure>{if !self.with_policy_files(&mut|relative,views|{let raw=views.raw()?;if !crate::auto_setter_calls_policy::wants_file(relative,raw){return Ok(true)}emit(relative,raw,&views.code()?.text)?;Ok(true)})?{return Err("original setter-call traversal incomplete".into())}self.checkpoint()?;self.require()}
 fn complete_inputs(&self)->Option<&dm_analysis::policy_inputs::PolicyInputs>{None}
 fn plans_marker_rows(&self)->Result<crate::captured_marker_rows::Rows<'_>,Failure>;
 fn with_plan_metadata_files(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>,bool)->Result<bool,Failure>)->Result<bool,Failure>;
 fn with_plan_reader_file(&self,ordinal:usize,name:&str,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<(),Failure>)->Result<(),Failure>;
 fn has_original_body(&self,member:dm_tree::MemberId)->Result<bool,Failure>;
 fn tree(&self)->&dm_tree::SemanticTree;
 fn budget(&self)->&Arc<Budget>;
 /// Actual operation root only for physical child scratch; not cache/source authority.
 fn operation_budget(&self)->&Arc<Budget>{self.budget()}
 fn require(&self)->Result<(),Failure>;
 fn checkpoint(&self)->std::io::Result<()>;
 fn variable_type(&self,owner:&str,name:&str)->Result<Option<String>,Failure>;
 fn receiver_variable_type(&self,owner:&str,name:&str)->Result<Option<String>,Failure>{self.variable_type(owner,name)}
 fn declaring_owner<'a>(&'a self,owner:&str,name:&str)->Result<Option<&'a str>,Failure>;
 fn is_subtype(&self,child:&str,parent:&str)->Result<bool,Failure>;
 fn body_count(&self)->usize;
 fn visit_callables<'source>(&'source self,names:Option<&[&str]>,poll:&mut dyn FnMut()->Result<(),Failure>,emit:&mut dyn FnMut(Callable<'source>)->Result<(),Failure>)->Result<(),Failure>;
 fn relative_body_file(&self,ordinal:usize)->Result<String,Failure>;
 fn with_body(&self,ordinal:usize,consume:&mut dyn FnMut(&dyn Body)->Result<(),Failure>)->Result<(),Failure>;
 fn with_budget(&self,budget:&Arc<Budget>,consume:&mut dyn FnMut(&dyn Source)->Result<(),Failure>)->Result<(),Failure>;
}
impl Source for ReadSource<'_>{
 fn plans_marker_rows(&self)->Result<crate::captured_marker_rows::Rows<'_>,Failure>{self.plans_marker_rows()}
 fn with_plan_metadata_files(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>,bool)->Result<bool,Failure>)->Result<bool,Failure>{self.with_plan_metadata_files(visit)}
 fn with_plan_reader_file(&self,ordinal:usize,name:&str,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<(),Failure>)->Result<(),Failure>{self.with_plan_reader_file(ordinal,name,visit)}
 fn has_original_body(&self,member:dm_tree::MemberId)->Result<bool,Failure>{self.require()?;Ok(self.inputs().archive().callables().ordinal(member).is_some())}

 fn dependency_marker_rows(&self,poll:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'_>,Failure>{self.dependency_marker_rows()}
 fn member_has_source(&self,member:dm_tree::MemberId)->Result<bool,Failure>{Ok(self.inputs().archive().member_location(member).is_some())}
 fn with_header_line(&self,member:dm_tree::MemberId,consume:&mut dyn FnMut(&str,usize,&str)->Result<(),Failure>)->Result<(),Failure>{self.with_original_header_line(member,consume)}
 fn with_policy_files(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.with_policy_files(visit)}
 fn complete_inputs(&self)->Option<&dm_analysis::policy_inputs::PolicyInputs>{Some(self.inputs())}
 fn occurrences(&self)->&[dm_tree::frontend::BodyOccurrence]{self.inputs().archive().occurrences()}
 fn raw_body_text(&self,ordinal:usize)->Result<&str,Failure>{let body=self.inputs().archive().occurrences().get(ordinal).ok_or("original body occurrence absent")?;self.inputs().archive().expanded_source().get(body.expanded_span.range()).ok_or_else(||Failure::from("original body source outside original arena"))}
 fn variable(&self,owner:&str,name:&str)->Result<Option<crate::reactive_original_source::ReadVariable<'_>>,Failure>{self.variable(owner,name).map_err(Failure::from)}
 fn callable(&self,owner:&str,name:&str)->Result<SelectedCallable<'_>,Failure>{Ok(match self.callable(owner,name)?{crate::reactive_original_source::SelectedCallable::Source(call)=>SelectedCallable::Source(Callable{owner:call.owner,name:call.name,ordinal:call.ordinal,member:call.member,header:call.header}),crate::reactive_original_source::SelectedCallable::Builtin=>SelectedCallable::Builtin,crate::reactive_original_source::SelectedCallable::Missing=>SelectedCallable::Missing})}
 fn parent_callable(&self,ordinal:usize)->Result<Option<Callable<'_>>,Failure>{Ok(self.parent_callable(ordinal)?.map(|call|Callable{owner:call.owner,name:call.name,ordinal:call.ordinal,member:call.member,header:call.header}))}
 fn visit_overrides<'source>(&'source self,owner:&str,name:&str,poll:&mut dyn FnMut()->Result<(),Failure>,emit:&mut dyn FnMut(Callable<'source>)->Result<(),Failure>)->Result<(),Failure>{self.visit_overrides(owner,name,poll,|call|emit(Callable{owner:call.owner,name:call.name,ordinal:call.ordinal,member:call.member,header:call.header}))}
 fn site(&self,ordinal:usize,offset:usize)->Result<(String,u32),Failure>{self.site(ordinal,offset).map_err(Failure::from)}
 fn site_line(&self,ordinal:usize,line:u32)->Result<(String,u32),Failure>{self.site_line(ordinal,line).map_err(Failure::from)}
 fn line_at(&self,offset:usize)->Result<u32,Failure>{self.line_at(offset).map_err(Failure::from)}
 fn parent_type(&self,owner:&str)->Result<Option<&str>,Failure>{self.parent_type(owner).map_err(Failure::from)}
 fn own_callable_exists(&self,owner:&str,name:&str)->Result<bool,Failure>{self.own_callable_exists(owner,name).map_err(Failure::from)}
 fn marker_rows(&self,poll:&mut dyn FnMut()->std::io::Result<()>)->Result<crate::captured_marker_rows::Rows<'_>,Failure>{self.marker_rows_checked(poll)}
 fn raw_metadata(&self,poll:&mut dyn FnMut()->std::io::Result<()>,emit:&mut dyn FnMut(&str,crate::raw_reactive_metadata_policy::Event<'_>)->Result<(),Failure>)->Result<(),Failure>{self.raw_metadata_checked(poll,emit)}
 fn raw_width(&self)->Result<usize,Failure>{self.raw_width_checked()}
 fn definition_neighbors(&self,relative:&str,line:u32,poll:&mut dyn FnMut()->Result<(),Failure>)->Result<(Option<(usize,&str,&str)>,Option<(usize,&str,&str)>),Failure>{self.definition_neighbors(relative,line,poll)}

 fn tree(&self)->&dm_tree::SemanticTree{self.inputs().archive().tree()}
 fn budget(&self)->&Arc<Budget>{self.budget()}
 fn require(&self)->Result<(),Failure>{self.require().map_err(Failure::from)}
 fn checkpoint(&self)->std::io::Result<()>{self.checkpoint()}
 fn variable_type(&self,owner:&str,name:&str)->Result<Option<String>,Failure>{self.variable_type(owner,name).map_err(Failure::from)}
 fn receiver_variable_type(&self,owner:&str,name:&str)->Result<Option<String>,Failure>{Ok(self.variable(owner,name)?.map(|value|value.declared))}
 fn declaring_owner<'a>(&'a self,owner:&str,name:&str)->Result<Option<&'a str>,Failure>{self.variable_declaring_owner(owner,name)}
 fn is_subtype(&self,child:&str,parent:&str)->Result<bool,Failure>{self.is_subtype(child,parent).map_err(Failure::from)}
 fn body_count(&self)->usize{self.inputs().archive().len()}
 fn visit_callables<'source>(&'source self,names:Option<&[&str]>,poll:&mut dyn FnMut()->Result<(),Failure>,emit:&mut dyn FnMut(Callable<'source>)->Result<(),Failure>)->Result<(),Failure>{match names{Some(names)=>self.visit_callables(names,poll,|call|emit(Callable{owner:call.owner,name:call.name,ordinal:call.ordinal,member:call.member,header:call.header})),None=>self.visit_all_callables(poll,|call|emit(Callable{owner:call.owner,name:call.name,ordinal:call.ordinal,member:call.member,header:call.header}))}}
 fn relative_body_file(&self,ordinal:usize)->Result<String,Failure>{Ok(self.site_line(ordinal,1)?.0)}
 fn with_body(&self,ordinal:usize,consume:&mut dyn FnMut(&dyn Body)->Result<(),Failure>)->Result<(),Failure>{let body=self.parse_body(ordinal).map_err(|e|match e{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;consume(&body)}
 fn with_budget(&self,budget:&Arc<Budget>,consume:&mut dyn FnMut(&dyn Source)->Result<(),Failure>)->Result<(),Failure>{self.with_budget(budget,|source|consume(source))}
}

// SAME original Auto declaration/version ordering, factored once for complete
// and generation issuers. Only source/header loans differ between those owners.
fn visit_setter_definitions_original<S:Source+?Sized>(source:&S,emit:&mut dyn FnMut(&str,&str)->Result<(),Failure>)->Result<(),Failure>{
    use crate::reactive_reads_native::Failure;
    source.checkpoint()?;
    source.require()?;
    let tree = source.tree();
    for ty in tree.types() {
        source.checkpoint()?;
        let owner = tree.symbols().text(ty.path).ok_or("setter definition owner absent")?;
        for (i, &member) in ty.members.iter().enumerate() {
            source.checkpoint()?;
            let node = tree.member(member).ok_or("setter definition member absent")?;
            if !matches!(node.kind, MemberKind::Proc | MemberKind::Verb) { continue; }
            let name = tree.symbols().text(node.name).ok_or("setter definition spelling absent")?;
            if !crate::auto_setter_calls_policy::PREFIXES.iter().any(|p| name.starts_with(p)) { continue; }
            // No allocation to deduplicate the group's versions; a type's
            // original member slice is the authority throughout this scan.
            let mut repeated = false;
            for &earlier in &ty.members[..i] {
                source.checkpoint()?;
                let earlier = tree.member(earlier).ok_or("setter predecessor absent")?;
                if earlier.name == node.name && matches!(earlier.kind, MemberKind::Proc | MemberKind::Verb) { repeated = true; break; }
            }
            if repeated { continue; }
            let mut declared = false;
            for &version in ty.members.iter() {
                source.checkpoint()?;
                let version = tree.member(version).ok_or("setter declaration version absent")?;
                if version.name == node.name && matches!(version.kind, MemberKind::Proc | MemberKind::Verb) {
                    declared |= version.definition == dm_tree::DefinitionMode::Declare;
                }
            }
            if !declared { continue; }
            let mut qualified = false;
            for &version in ty.members.iter() {
                source.checkpoint()?;
                source.require()?;
                let version_node = tree.member(version).ok_or("setter version absent")?;
                if version_node.name != node.name || !matches!(version_node.kind, MemberKind::Proc | MemberKind::Verb) { continue; }
                if !source.member_has_source(version)? {
                    // Absence of source is never enough. The existing catalog
                    // issuer checks exact original metadata pointer and owner.
                    let profile = tree.checker_builtin_profile().ok_or("setter builtin profile absent")?;
                    tree.checker_builtin_procedure_identity(profile, ty.path, node.name,
                        version_node.kind == MemberKind::Verb, &version_node.metadata)
                        .map_err(|e| Failure::Unsupported(format!("setter builtin version: {e:?}")))?;
                    qualified = true;
                    continue;
                }
                source.with_header_line(version,&mut|relative,_display,line|{
                    if relative!=crate::auto_setter_calls_policy::AUTO_REL && relative!="code/engine/_generated/tracked_lists.dm" && !line.trim_start().starts_with("TRACKED(") && !line.trim_start().starts_with("TRACKED_BRIDGED("){qualified=true;}Ok(())
                })?;
            }
            if declared && qualified { emit(name, owner)?; }
        }
    }
    source.checkpoint()?;
    source.require()?;
    Ok(())
}
fn visit_own_declared_variables_original<S:Source+?Sized>(source:&S,emit:&mut dyn FnMut(&str,&str)->Result<(),Failure>)->Result<(),Failure>{
    use dm_tree::DefinitionMode;
    source.checkpoint()?;
    source.require()?;
    let tree = source.tree();
    let profile = tree.checker_builtin_profile().ok_or("auto variable profile absent")?;
    let catalog = dm_tree::checker_builtins::pinned_catalog().map_err(|e| format!("auto variable catalog: {e:?}"))?;
    if catalog.profile != profile { return Err("auto variable catalog differs from original source profile".into()); }
    for ty in tree.types() {
        source.checkpoint()?;
        source.require()?;
        let owner = tree.symbols().text(ty.path).ok_or("auto variable owner spelling absent")?;
        if !tree.checker_source_type_presence(profile, owner).map_err(|e| format!("auto variable source type: {e:?}"))? { continue; }
        for &member in ty.members.iter() {
            source.checkpoint()?;
            let node = tree.member(member).ok_or("auto variable original member absent")?;
            if node.kind != MemberKind::Var || node.definition != DefinitionMode::Declare || !source.member_has_source(member)? { continue; }
            let name = tree.symbols().text(node.name).ok_or("auto variable spelling absent")?;
            // This is a declaration roster, not receiver fallback. The existing
            // source formal issuer must identify this exact own member.
            if tree.source_formal_variable_member(ty.path, node.name).map_err(str::to_owned)? != Some(member) { return Err("auto variable declaration does not match original formal issuer".into()); }
            emit(owner, name)?;
        }
        for row in catalog.declarations.iter() {
            source.checkpoint()?;
            if row.owner != ty.path || row.kind != MemberKind::Var || row.definition != DefinitionMode::Declare { continue; }
            // Only an OWN authored declaration replaces this builtin name.
            // The general formal resolver can select an ancestor and correctly
            // refuses a builtin without authored source; neither is absence.
            let mut own_source = false;
            for &member in ty.members.iter() {
                source.checkpoint()?;
                let member_node = tree.member(member).ok_or("auto own-source member absent")?;
                if member_node.name == row.name && member_node.kind == MemberKind::Var
                    && member_node.definition == DefinitionMode::Declare
                    && source.member_has_source(member)? { own_source = true; break; }
            }
            if own_source { continue; }
            let name = tree.checker_builtin_spelling(profile, row.name).ok_or("auto builtin variable spelling absent")?;
            emit(owner, name)?;
        }
    }
    source.checkpoint()?;
    source.require()?;
    Ok(())
}
