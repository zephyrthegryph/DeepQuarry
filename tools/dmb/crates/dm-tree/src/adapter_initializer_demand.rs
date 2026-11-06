//! Existing adapter policy with a typed, operation-local original-RHS demand.
//! This does not issue namespace/type semantics or own a parallel declaration model.
use super::*;
use crate::procedure::adapter_rows::AdapterRows;
mod sealed{pub trait Sealed{}}
pub(super) enum WalkFailure<E>{Source(String),Operational(E)}
impl<E> From<String> for WalkFailure<E>{fn from(message:String)->Self{Self::Source(message)}}
impl<E> From<&str> for WalkFailure<E>{fn from(message:&str)->Self{Self::Source(message.into())}}
pub(super) enum VariableParts<'owner,'normalized>{
    Compatibility{declaration:&'normalized str,initializer:Option<&'normalized str>},
    Original(crate::procedure::header_input::IssuedVariableParts<'owner,'normalized>),
}
impl VariableParts<'_,'_>{
    pub(super) fn declaration(&self)->&str{match self{Self::Compatibility{declaration,..}=>declaration,Self::Original(parts)=>parts.declaration()}}
    pub(super) fn symbolic(&self,symbols:&mut SymbolTable)->Result<Option<dm_ir::SymbolicExpression>,String>{match self{Self::Compatibility{initializer,..}=>initializer.map(|text|crate::procedure::expression(text,symbols)).transpose(),Self::Original(parts)=>parts.symbolic(symbols)}}
}
pub(super) struct Compatibility;
pub(super) struct Checked<'op,'cap>{pub(super) admission:&'op dm_syntax::SettingAdmission<'cap>}
impl sealed::Sealed for Compatibility{}
impl sealed::Sealed for Checked<'_,'_>{}
pub(super) trait AdapterDemand:sealed::Sealed{
    type Operational;
    fn checkpoint(&self)->Result<(),Self::Operational>;
    fn original_settings(
        &self,items:&[Item],symbols:&mut SymbolTable,headers:&crate::procedure::OriginalProcedureHeaders,offset:usize,
        _prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    )->Result<(AdapterRows<dm_ir::ProcedureSettingNode>,AdapterRows<crate::procedure::header_input::SettingFootprint>),WalkFailure<Self::Operational>>{
        crate::settings::extract_settings_original_rows(items,symbols,headers,offset).map_err(WalkFailure::Source)
    }
    fn procedure_metadata(
        &self,signature:dm_ir::ProcedureSignature,settings:SettingRows,
        prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    )->Result<Arc<dm_ir::ProcedureMetadata>,Self::Operational>;
    fn reserve_header_row(&self, rows:&mut AdapterRows<crate::procedure::header_input::HeaderAllocationRow>)
        -> Result<bool, Self::Operational>;
    fn member_metadata(&self, metadata:MemberMetadata,
        prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    ) -> Result<Arc<MemberMetadata>,Self::Operational>;
    fn intern_adapter_spelling(
        &self, symbols:&mut SymbolTable,text:&str,
        _prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    )->Result<SymbolId,WalkFailure<Self::Operational>>{
        symbols.intern(text).map_err(|error|WalkFailure::Source(error.to_string()))
    }
    fn procedure_canonical(
        &self, header:Arc<[u8]>, procedure:&dm_ir::ProcedureMetadata,
        prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    )->Result<Arc<[u8]>,Self::Operational>;
    fn variable<'o,'n>(&self,span:dm_syntax::Span,normalized:&'n str,headers:Option<(&'o crate::procedure::OriginalProcedureHeaders,usize)>)->Result<VariableParts<'o,'n>,WalkFailure<Self::Operational>>;
    fn constant(&self,parts:&VariableParts<'_,'_>,expression:Option<&dm_ir::SymbolicExpression>,symbols:&mut SymbolTable)->Result<Option<dm_ir::SemanticValue>,WalkFailure<Self::Operational>>;
    fn assignment(&self,span:dm_syntax::Span,header:&str,index:usize,headers:Option<(&crate::procedure::OriginalProcedureHeaders,usize)>,symbols:&mut SymbolTable)->Result<dm_ir::SymbolicExpression,WalkFailure<Self::Operational>>;
}
fn append_procedure_canonical_unmetered(header:Arc<[u8]>,procedure:&dm_ir::ProcedureMetadata)->Arc<[u8]>{
    let mut bytes=header.to_vec();
    drop(header);
    bytes.extend_from_slice(&procedure.canonical_bytes());
    bytes.into()
}
pub(super) enum SettingRows {
    Original(AdapterRows<dm_ir::ProcedureSettingNode>),
    Existing(Arc<[dm_ir::ProcedureSettingNode]>),
}
impl SettingRows {
    fn into_shared(self)->Arc<[dm_ir::ProcedureSettingNode]>{
        match self{Self::Original(rows)=>rows.into_shared(),Self::Existing(rows)=>rows}
    }
}
impl AdapterDemand for Compatibility{
    type Operational=std::convert::Infallible;
    fn procedure_metadata(&self,signature:dm_ir::ProcedureSignature,settings:SettingRows,_:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>)->Result<Arc<dm_ir::ProcedureMetadata>,Self::Operational>{
        Ok(Arc::new(dm_ir::ProcedureMetadata{signature,settings:settings.into_shared()}))
    }
    fn reserve_header_row(&self, rows:&mut AdapterRows<crate::procedure::header_input::HeaderAllocationRow>)->Result<bool,Self::Operational>{
        Ok(rows.reserve_compatibility().is_ok())
    }
    fn member_metadata(&self, metadata:MemberMetadata,_:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>)->Result<Arc<MemberMetadata>,Self::Operational>{
        Ok(Arc::new(metadata))
    }
    fn procedure_canonical(&self,header:Arc<[u8]>,procedure:&dm_ir::ProcedureMetadata,_:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>)->Result<Arc<[u8]>,Self::Operational>{
        Ok(append_procedure_canonical_unmetered(header,procedure))
    }
    fn checkpoint(&self)->Result<(),Self::Operational>{Ok(())}
    fn variable<'o,'n>(&self,_:dm_syntax::Span,header:&'n str,_:Option<(&'o crate::procedure::OriginalProcedureHeaders,usize)>)->Result<VariableParts<'o,'n>,WalkFailure<Self::Operational>>{
        let(declaration,initializer)=dm_syntax::top_level_assignment_index(header).map_or((header,None),|index|(header[..index].trim(),Some(header[index+1..].trim())));
        let initializer=initializer.map(crate::procedure::variable_initializer).transpose()?;
        Ok(VariableParts::Compatibility{declaration,initializer})
    }
    fn constant(&self,parts:&VariableParts<'_,'_>,_:Option<&dm_ir::SymbolicExpression>,symbols:&mut SymbolTable)->Result<Option<dm_ir::SemanticValue>,WalkFailure<Self::Operational>>{
        let VariableParts::Compatibility{initializer,..}=parts else{return Err("compatibility adapter received foreign original input".into())};
        initializer.and_then(|text|crate::constants::evaluate_with(text,|_|None,|_|None,|_|None)).map(|value|value.to_semantic(symbols)).transpose().map_err(|error|WalkFailure::Source(error.to_string()))
    }
    fn assignment(&self,_:dm_syntax::Span,header:&str,index:usize,_:Option<(&crate::procedure::OriginalProcedureHeaders,usize)>,symbols:&mut SymbolTable)->Result<dm_ir::SymbolicExpression,WalkFailure<Self::Operational>>{crate::procedure::expression(header[index+1..].trim(),symbols).map_err(Into::into)}
}
impl AdapterDemand for Checked<'_,'_>{
    type Operational=std::io::Error;
    fn original_settings(
        &self,items:&[Item],symbols:&mut SymbolTable,headers:&crate::procedure::OriginalProcedureHeaders,offset:usize,
        prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    )->Result<(AdapterRows<dm_ir::ProcedureSettingNode>,AdapterRows<crate::procedure::header_input::SettingFootprint>),WalkFailure<Self::Operational>>{
        let mut prepared=prepared;
        crate::settings::extract_settings_original_rows_using(items,symbols,headers,offset,
            &mut |headers,header,offset,symbols|match prepared.as_deref_mut(){
                Some(actual)=>headers.parse_setting_original_admitted(header,offset,symbols,actual,self.admission),
                None=>headers.parse_setting_original(header,offset,symbols).map_err(crate::procedure::header_input::OriginalHeaderFailure::Source),
            },
            &mut |nodes,footprints|{
                nodes.reserve_checked(self.admission)?;
                footprints.reserve_checked(self.admission)?;
                Ok(())
            })
            .map_err(|error|match error{
                crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>WalkFailure::Source(message),
                crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>WalkFailure::Operational(actual),
            })
    }
    fn procedure_metadata(&self,signature:dm_ir::ProcedureSignature,settings:SettingRows,prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>)->Result<Arc<dm_ir::ProcedureMetadata>,Self::Operational>{
        match prepared{
            Some(actual)=>{
                let SettingRows::Original(settings)=settings else{return Err(std::io::ErrorKind::InvalidInput.into())};
                actual.procedure_metadata(signature,settings,self.admission)
            }
            None=>Ok(Arc::new(dm_ir::ProcedureMetadata{signature,settings:settings.into_shared()})),
        }
    }
    fn reserve_header_row(&self, rows:&mut AdapterRows<crate::procedure::header_input::HeaderAllocationRow>)->Result<bool,Self::Operational>{
        rows.reserve_checked(self.admission)?;
        Ok(true)
    }
    fn member_metadata(&self, metadata:MemberMetadata,prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>)->Result<Arc<MemberMetadata>,Self::Operational>{
        match prepared {
            Some(actual)=>actual.member_metadata(metadata,self.admission),
            None=>Ok(Arc::new(metadata)),
        }
    }
    fn intern_adapter_spelling(
        &self,symbols:&mut SymbolTable,text:&str,
        prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>,
    )->Result<SymbolId,WalkFailure<Self::Operational>>{
        let inserted=match prepared{
            Some(actual)=>actual.intern_adapter_spelling(symbols,text,self.admission).map_err(WalkFailure::Operational)?,
            None=>symbols.intern(text),
        };
        inserted.map_err(|error|WalkFailure::Source(error.to_string()))
    }
    fn procedure_canonical(&self,header:Arc<[u8]>,procedure:&dm_ir::ProcedureMetadata,prepared:Option<&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures>)->Result<Arc<[u8]>,Self::Operational>{
        match prepared{
            Some(actual)=>actual.append_procedure_canonical(header,procedure,self.admission),
            None=>Ok(append_procedure_canonical_unmetered(header,procedure)),
        }
    }
    fn checkpoint(&self)->Result<(),Self::Operational>{let status=self.admission.checkpoint();if let Some(actual)=self.admission.take_operational_error(){return Err(actual);}status}
    fn variable<'o,'n>(&self,span:dm_syntax::Span,normalized:&'n str,headers:Option<(&'o crate::procedure::OriginalProcedureHeaders,usize)>)->Result<VariableParts<'o,'n>,WalkFailure<Self::Operational>>{
        let(headers,offset)=headers.ok_or("checked variable requires original primary headers")?;
        Ok(VariableParts::Original(headers.variable_parts(span,offset,normalized)?))
    }
    fn constant(&self,parts:&VariableParts<'_,'_>,expression:Option<&dm_ir::SymbolicExpression>,symbols:&mut SymbolTable)->Result<Option<dm_ir::SemanticValue>,WalkFailure<Self::Operational>>{
        let VariableParts::Original(parts)=parts else{return Err("checked adapter cannot select compatibility source".into())};
        let Some(expression)=expression else{return Ok(None)};
        parts.constant(expression,symbols,self.admission).map_err(|failure|match failure{crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>WalkFailure::Source(message),crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>WalkFailure::Operational(actual)})
    }
    fn assignment(&self,span:dm_syntax::Span,_:&str,_:usize,headers:Option<(&crate::procedure::OriginalProcedureHeaders,usize)>,symbols:&mut SymbolTable)->Result<dm_ir::SymbolicExpression,WalkFailure<Self::Operational>>{
        let(headers,offset)=headers.ok_or("checked assignment requires original primary headers")?;
        headers.authored_initializer(span,offset,false,symbols).map_err(Into::into)
    }
}
