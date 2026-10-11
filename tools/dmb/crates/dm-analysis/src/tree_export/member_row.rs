//! Shared current-tree member serializer for full exports and retained pages.
use super::*;
fn member_key(tree: &SemanticTree, id: dm_tree::MemberId) -> Result<String, ExportError> {
    let member = tree
        .member(id)
        .ok_or(ExportError::InvalidModel("unknown exported member"))?;
    let owner = tree
        .type_node(member.owner)
        .ok_or(ExportError::InvalidModel("unknown member owner"))?
        .path;
    let occurrence = tree
        .member_occurrence(id)
        .ok_or(ExportError::InvalidModel("member occurrence unavailable"))?;
    Ok(format!(
        "member:{:016x}:{}:{:016x}:{occurrence}",
        owner.bits(),
        kind(member.kind),
        member.name.bits()
    ))
}
pub(super) fn member_row(tree: &SemanticTree, id: dm_tree::MemberId) -> Result<Value, ExportError> {
    let symbols = tree.symbols();
    let member = tree
        .member(id)
        .ok_or(ExportError::InvalidModel("unknown exported member"))?;
    let metadata = &member.metadata;
    let effective = tree
        .resolve(member.owner, member.name, member.kind)
        .and_then(|id| tree.member(id))
        .ok_or(ExportError::InvalidModel(
            "member has no effective declaration",
        ))?;
    let procedure = metadata.procedure.as_ref().map(|procedure| {
            let parameters = procedure.signature.parameters.iter().map(|parameter| Ok(json!({
                "name":spelling(symbols,parameter.name)?,
                "declared_type":parameter.declared_type.map(|id| spelling(symbols,id)).transpose()?,
                "list_element_type":parameter.list_element_type.map(|id| spelling(symbols,id)).transpose()?,
                "list_element_type_status":"known",
                "flags":parameter.flags,
                "array":parameter.array.as_ref().map(|array| Ok::<_, ExportError>(json!({
                    "element_type":array.element_type.map(|id| spelling(symbols,id)).transpose()?,
                    "dimensions":array.dimensions.iter().map(|dimension| expression(dimension.as_ref(),symbols)).collect::<Result<Vec<_>,_>>()?,
                }))).transpose()?,
                "default":expression(parameter.default.as_ref(),symbols)?,
                "input_annotation":expression(parameter.input_annotation.as_ref(),symbols)?,
                "source_expression":expression(parameter.source_expression.as_ref(),symbols)?,
            }))).collect::<Result<Vec<_>, ExportError>>()?;
            let settings = setting_nodes(&procedure.settings,symbols)?;
            Ok::<_,ExportError>(json!({"parameters":parameters,"variadic":procedure.signature.variadic,
                "return_annotation":expression(procedure.signature.return_annotation.as_ref(),symbols)?,"settings":settings}))
        }).transpose()?;
    let array = metadata.array.as_ref().map(|array| Ok::<_,ExportError>(json!({
            "element_type":array.element_type.map(|id| spelling(symbols,id)).transpose()?,
            "dimensions":array.dimensions.iter().map(|dimension| expression(dimension.as_ref(),symbols)).collect::<Result<Vec<_>,_>>()?,
        }))).transpose()?;
    let opaque = metadata.inherited_opaque.as_ref().map(|base| Ok::<_,ExportError>(json!({
            "owner":spelling(symbols,base.owner)?,"name":spelling(symbols,base.name)?,
            "declared_type":match base.declared_type { DeclaredTypeKnowledge::Known(path)=>Some(spelling(symbols,path)?),DeclaredTypeKnowledge::Unsupported|DeclaredTypeKnowledge::KnownUntyped=>None },
            "declared_type_status":match base.declared_type { DeclaredTypeKnowledge::Known(_)=>"known",DeclaredTypeKnowledge::KnownUntyped=>"known_untyped",DeclaredTypeKnowledge::Unsupported=>"unsupported" },
            "flags_status":"unknown", "formal_default_status":"unknown", "array_shape_status":"unknown",
        }))).transpose()?;
    Ok(
        json!({"row":"member", "id":member_key(tree,id)?, "owner":type_key(tree,member.owner)?,
            "meaning":format!("{:032x}",member.content), "name":spelling(symbols,member.name)?, "kind":kind(member.kind),"definition":definition(member.definition),
            "previous":member.previous.map(|previous| member_key(tree,previous)).transpose()?,
            "declared_type":metadata.declared_type.map(|id| spelling(symbols,id)).transpose()?,
            "list_element_type":metadata.inherited_opaque.is_none().then_some(metadata.list_element_type).flatten().map(|id| spelling(symbols,id)).transpose()?,
            "list_element_type_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" },
            "display_name":metadata.display_name.map(|id| spelling(symbols,id)).transpose()?,
            "inherited_opaque":opaque,
            "flags":metadata.inherited_opaque.is_none().then_some(metadata.flags),
            "flags_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" },
            "effective_flags":effective.metadata.inherited_opaque.is_none().then_some(effective.metadata.flags),
            "effective_flags_status":if effective.metadata.inherited_opaque.is_some() { "unknown" } else { "known" }, "initializer":expression(metadata.initializer.as_ref(),symbols)?,
            "declared_default":expression(metadata.declared_initializer.as_ref(),symbols)?,
            "declared_default_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" },
            "effective_default":expression(effective.metadata.initializer.as_ref(),symbols)?,
            "resolved_constant":metadata.resolved_constant.as_ref().map(|value| constant(value,symbols)).transpose()?,
            "procedure":procedure,"array":array,
            "array_status":if metadata.inherited_opaque.is_some() { "unknown" } else { "known" }}),
    )
}
