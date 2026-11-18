//! Original initializer Debug text from the SAME current input/root/token facts.
//! No source read, lexer, expression parser or independent value cache lives here.
use super::*;
use dm_preprocess::original_expression_debug::{self as debug,Tokens};
use std::io;
struct Loan<'a,'source,'op>{input:&'a relative_declarations::OriginalInitializerTokenInput<'source>,mapping:&'a SourceExportMapping,indices:Vec<usize>,facts:dm_syntax::OriginalLiteralFactsView<'a>,a:&'a dm_syntax::SettingAdmission<'op>,_credit:dm_syntax::SettingRootLease}
impl Tokens for Loan<'_,'_,'_>{
 fn checkpoint(&self)->io::Result<()>{self.a.checkpoint().map_err(|e|self.a.take_operational_error().unwrap_or(e))}
 fn admission(&self)->&dm_syntax::SettingAdmission<'_>{self.a}
 fn len(&self)->usize{self.indices.len()}
 fn token(&self,index:usize)->io::Result<debug::Token<'_>>{
  let index=*self.indices.get(index).ok_or(io::ErrorKind::InvalidData)?;let token=self.input.tokens.get(index).ok_or(io::ErrorKind::InvalidData)?;
  let text=self.input.source.get(token.span.range()).ok_or(io::ErrorKind::InvalidData)?;
  let value=match token.kind{
   dm_syntax::TokenKind::Ident=>dm_syntax::OriginalTokenValue::Ident{spelling:debug::Text(text),whitespace:false},
   dm_syntax::TokenKind::Number|dm_syntax::TokenKind::String|dm_syntax::TokenKind::Resource|dm_syntax::TokenKind::Interpolation=>{
    let(rows,origin)=self.facts.raw_parts();let at=dm_syntax::Span::new(token.span.start.checked_add(origin).ok_or(io::ErrorKind::InvalidData)?,token.span.end.checked_add(origin).ok_or(io::ErrorKind::InvalidData)?);let ordinal=rows.partition_point(|(span,_)|span.end<=at.start);let(span,value)=rows.get(ordinal).ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual initializer literal VALUE is unissued"))?;if span!=at{return Err(io::Error::new(io::ErrorKind::InvalidData,"actual initializer literal span differs"))}value.value()?.map_text(|text|debug::Text(*text))
   },
   dm_syntax::TokenKind::Operator|dm_syntax::TokenKind::Punctuation=>{let index=dm_syntax::original_scalar_transport::original_punctuation_storage_index(text).ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual initializer punctuation Debug product unissued"))?;dm_syntax::OriginalTokenValue::Punct(dm_syntax::original_scalar_transport::original_punctuation_storage_value(index).ok_or(io::ErrorKind::InvalidData)?)},
   _=>return Err(io::Error::new(io::ErrorKind::Unsupported,"actual initializer Debug requires significant issued tokens")),
  };
  let current=token.span.start.checked_add(self.input.offset).ok_or(io::ErrorKind::InvalidData)?;let point=self.mapping.borrowed_source_note_point(current).map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;let(_,line,byte_column)=point.reported_coordinates();
  Ok(debug::Token{span:token.span,value,origin:debug::Origin{file_key:current,line:line as usize,byte_column:Some(byte_column as usize)}})
 }
}
fn with_bound<'source,T>(frontend:&'source ColdFrontend,source_input:&OriginalInitializerSource<'source>,produce:impl FnOnce()->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>,a:&dm_syntax::SettingAdmission<'_>,consume:impl FnOnce(&Loan<'_,'_,'_>,&OriginalInitializerExpression<'source>,&dm_syntax::OriginalSettingProducts)->io::Result<T>)->Result<T,BodySyntaxFailure>{
  let pending=(||{
   a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let mapping=frontend.source_export_mapping().ok_or_else(||BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"actual initializer mapping absent")))?;
   if mapping.initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"initializer Debug requires actual Original environment")))}
   let OriginalInitializerSource::Header(input)=source_input else{return Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual static-body initializer Debug token loan is unissued")))};
   let facts=input.owner.original_literal_facts().map_err(BodySyntaxFailure::Operational)?.ok_or_else(||BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual initializer Original facts are unissued")))?;
   if !facts.admitted_by(a){return Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"initializer Debug facts use another resource owner")))}
   let root=produce()?;
   // Reborrow only the SAME already-issued slot observation. The held root
   // keeps its weak slot live; the producer closure never parses or upgrades.
   let(cached,_native,products)=(if input.dimension{input.slots.obtain_dimension_with_original_products(input.ordinal,input.count,input.dimension_index,input.dimension_count,input.value,a,||Err(dm_syntax::SettingSyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual dimension Debug cannot reparse an absent slot"))))}else{input.slots.obtain_with_original_products(input.ordinal,input.count,a,||Err(dm_syntax::SettingSyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual initializer Debug cannot reparse an absent slot"))))}).map_err(|e|match e{dm_syntax::SettingSyntaxFailure::Operational(actual)=>BodySyntaxFailure::Operational(actual),dm_syntax::SettingSyntaxFailure::Syntax(_)=>BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual initializer Debug observation is unavailable"))})?;
   let OriginalInitializerRoot::Header(actual)=&root.root else{return Err(BodySyntaxFailure::Operational(io::ErrorKind::InvalidData.into()))};
   if !cached.same_root(actual)||!products.original_value_for(&cached,a).map_err(BodySyntaxFailure::Operational)?{return Err(BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::Unsupported,"actual initializer Original syntax observation is unissued")))}
   let bytes=input.tokens.len().checked_mul(4*std::mem::size_of::<usize>()).ok_or_else(||BodySyntaxFailure::Operational(io::ErrorKind::OutOfMemory.into()))?;let credit=a.reserve(bytes).map_err(BodySyntaxFailure::Operational)?;
   let mut indices=Vec::new();indices.try_reserve_exact(input.tokens.len()).map_err(|e|BodySyntaxFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
   if indices.capacity().checked_mul(std::mem::size_of::<usize>()).is_none_or(|n|n>bytes){return Err(BodySyntaxFailure::Operational(io::ErrorKind::OutOfMemory.into()))}
   for(index,token)in input.tokens.iter().enumerate(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;if !matches!(token.kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment){indices.push(index);}}
   let loan=Loan{input,mapping,indices,facts,a,_credit:credit};
   consume(&loan,&root,&products).map_err(BodySyntaxFailure::Operational)
  })();match a.take_operational_error(){Some(first)=>Err(BodySyntaxFailure::Operational(first)),None=>pending}
}

fn debug_bound<'source>(frontend:&'source ColdFrontend,input:&OriginalInitializerSource<'source>,produce:impl FnOnce()->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>,a:&dm_syntax::SettingAdmission<'_>,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>)->Result<debug::Formatted,BodySyntaxFailure>{
 with_bound(frontend,input,produce,a,|loan,root,_|debug::format_using(loan,root.ast(),&mut|key|{let point=loan.mapping.borrowed_source_note_point(key).map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;let(path,_,_)=point.reported_coordinates();file(path)}))
}
fn value_bound<'source>(frontend:&'source ColdFrontend,input:&OriginalInitializerSource<'source>,produce:impl FnOnce()->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>,a:&dm_syntax::SettingAdmission<'_>,model:&dyn dm_preprocess::original_model_value::ModelContext,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>)->Result<dm_preprocess::original_model_value::ModelOutcome,BodySyntaxFailure>{
 with_bound(frontend,input,produce,a,|loan,root,products|{
  let mut expression_debug=|expression:&dm_syntax::Expr|debug::format_using(loan,expression,&mut|key|{let point=loan.mapping.borrowed_source_note_point(key).map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;let(path,_,_)=point.reported_coordinates();file(path)});
  dm_preprocess::original_model_value::evaluate_model_using(root.ast(),model,a,Some(products.constructors()),Some(&mut expression_debug))
 })
}
impl OriginalInitializerExpressionInput<'_>{
 pub fn original_debug_using(&self,a:&dm_syntax::SettingAdmission<'_>,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>)->Result<debug::Formatted,BodySyntaxFailure>{debug_bound(self.frontend,&self.input,||self.prepare(a),a,file)}
 pub fn original_value_using(&self,a:&dm_syntax::SettingAdmission<'_>,model:&dyn dm_preprocess::original_model_value::ModelContext,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>)->Result<dm_preprocess::original_model_value::ModelOutcome,BodySyntaxFailure>{value_bound(self.frontend,&self.input,||self.prepare(a),a,model,file)}
}
impl OriginalDeclarationExpressionInput<'_>{
 pub fn original_debug_using(&self,a:&dm_syntax::SettingAdmission<'_>,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>)->Result<debug::Formatted,BodySyntaxFailure>{debug_bound(self.frontend,&self.input,||self.prepare(a),a,file)}
 pub fn original_value_using(&self,a:&dm_syntax::SettingAdmission<'_>,model:&dyn dm_preprocess::original_model_value::ModelContext,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>)->Result<dm_preprocess::original_model_value::ModelOutcome,BodySyntaxFailure>{value_bound(self.frontend,&self.input,||self.prepare(a),a,model,file)}
}

impl OriginalDeclarationExpressionInput<'_>{
 pub fn append_original_array_dimension_using(&self,a:&dm_syntax::SettingAdmission<'_>,model:&dyn dm_preprocess::original_model_value::ModelContext,file:&mut dyn FnMut(&std::path::Path)->io::Result<u32>,array:&mut dm_preprocess::original_model_value::ModelArrayBuilder)->Result<Option<dm_preprocess::original_model_value::ModelOutcome>,BodySyntaxFailure>{
  with_bound(self.frontend,&self.input,||self.prepare(a),a,|loan,root,products|{let mut expression_debug=|expression:&dm_syntax::Expr|debug::format_using(loan,expression,&mut|key|{let point=loan.mapping.borrowed_source_note_point(key).map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;let(path,_,_)=point.reported_coordinates();file(path)});array.push_using(root.ast(),model,a,products.constructors(),&mut expression_debug)})
 }
}
