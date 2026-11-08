//! The native canonical byte encoder, with demand-owned transient storage.
//!
//! Framed children append to the SAME buffer and backpatch their own length.
//! The borrowed task stack replaces recursive child Vecs; it is not a semantic
//! view or retained cache. Every allocator growth is admitted before it happens.
use crate::*;
use std::{io, mem::size_of};

pub trait CanonicalWork {
    fn poll(&mut self) -> io::Result<()>;
    fn reserve(&mut self, bytes: usize) -> io::Result<()>;
    /// Resource settlement after allocator growth or actual destruction.
    /// Other encoders may keep their existing operation-lifetime envelope.
    fn release_retired(&mut self,_bytes:usize)->io::Result<()>{Ok(())}
}
pub(crate) struct Unmetered;
impl CanonicalWork for Unmetered {
    fn poll(&mut self) -> io::Result<()> { Ok(()) }
    fn reserve(&mut self, _: usize) -> io::Result<()> { Ok(()) }
}
fn oom(message: &'static str) -> io::Error { io::Error::new(io::ErrorKind::OutOfMemory, message) }
fn grow<T>(value: &mut Vec<T>, additional: usize, work: &mut dyn CanonicalWork) -> io::Result<()> {
    work.poll()?;
    let needed = value.len().checked_add(additional).ok_or_else(|| oom("canonical capacity overflow"))?;
    if needed <= value.capacity() { return Ok(()) }
    let target = needed.checked_next_power_of_two().ok_or_else(|| oom("canonical capacity overflow"))?;
    let bound = target.checked_mul(4).ok_or_else(|| oom("canonical allocator bound overflow"))?;
    // Admit the whole new allocation while the old buffer may still be live.
    let grant=bound.checked_mul(size_of::<T>()).and_then(|n| n.checked_add(128)).ok_or_else(|| oom("canonical allocation geometry overflow"))?;
    let old_capacity=value.capacity();
    work.reserve(grant)?;
    value.try_reserve_exact(target - value.len()).map_err(|e| io::Error::new(io::ErrorKind::OutOfMemory,e))?;
    if value.capacity() > bound { return Err(oom("canonical allocator exposed excess capacity")) }
    let refund=(bound-value.capacity()).checked_add(old_capacity)
        .and_then(|n|n.checked_mul(size_of::<T>()))
        .and_then(|n|n.checked_add(if old_capacity!=0{128}else{0}))
        .ok_or_else(||oom("canonical allocation settlement overflow"))?;
    // The old allocation no longer exists. Preserve only the current Vec's
    // actual capacity. Failed resize leaves its whole pregrant until unwind.
    work.release_retired(refund)
}
pub(crate) enum Root<'a> {
    Expression(&'a SymbolicExpression), Signature(&'a ProcedureSignature),
    Procedure(&'a ProcedureMetadata), Array(&'a ArrayDeclaration),
    Semantic(&'a SemanticValue), Opaque(&'a OpaqueFieldBase),
    Declaration(&'a DeclarationMeaning), Meaning(&'a ResolvedMeaning),
    Static(&'a ProcedureStaticDeclaration),
}
enum Task<'a> {
    Root(Root<'a>), Frame(Root<'a>), EndFrame { at: usize, start: usize },
    DeclarationField(&'a DeclarationMeaning,u8),
    Parameters(&'a [Parameter],usize), Parameter(&'a Parameter,u8),
    SignatureReturn(&'a ProcedureSignature),
    Settings(&'a [ProcedureSettingNode]), SettingItems(&'a [ProcedureSettingNode],usize),
    ListItems(&'a [(Option<SemanticValue>,SemanticValue)],usize),
    MeaningItems(&'a [ResolvedMeaning],usize),
    StaticField(&'a ProcedureStaticDeclaration,u8),
}
struct Encoder<'a,'w> { out:Vec<u8>, tasks:Vec<Task<'a>>, work:&'w mut dyn CanonicalWork }
impl<'a> Encoder<'a,'_> {
    fn bytes(&mut self, bytes:&[u8])->io::Result<()> { grow(&mut self.out,bytes.len(),self.work)?;self.out.extend_from_slice(bytes);Ok(()) }
    fn byte(&mut self,byte:u8)->io::Result<()> { self.bytes(&[byte]) }
    fn length(&mut self,len:usize)->io::Result<()> { self.bytes(&u64::try_from(len).map_err(|_|oom("canonical length exceeds u64"))?.to_le_bytes()) }
    fn symbol(&mut self,symbol:SymbolId)->io::Result<()> { self.bytes(&symbol.bits().to_le_bytes()) }
    fn push(&mut self,task:Task<'a>)->io::Result<()> { grow(&mut self.tasks,1,self.work)?;self.tasks.push(task);Ok(()) }
    fn root(&mut self,root:Root<'a>)->io::Result<()> { self.push(Task::Root(root)) }
    fn frame(&mut self,root:Root<'a>)->io::Result<()> {
        self.push(Task::Frame(root))
    }
    fn optional_expression(&mut self,value:Option<&'a SymbolicExpression>)->io::Result<()> {
        self.byte(u8::from(value.is_some()))?;if let Some(value)=value{self.frame(Root::Expression(value))?}Ok(())
    }
    fn procedure_identity(&mut self,identity:&ProcedureIdentity)->io::Result<()> {
        self.symbol(identity.owner)?;self.symbol(identity.name)?;self.byte(u8::from(identity.verb))?;self.bytes(&identity.occurrence.to_le_bytes())
    }
    fn expression(&mut self,value:&SymbolicExpression)->io::Result<()> {
        value.try_write_canonical(&mut|chunk|self.bytes(chunk))
    }
    fn step(&mut self,task:Task<'a>)->io::Result<()> {
        match task {
            Task::Frame(root)=>{let at=self.out.len();self.length(0)?;let start=self.out.len();self.push(Task::EndFrame{at,start})?;self.root(root)?;},
            Task::EndFrame{at,start}=>{let len=self.out.len().checked_sub(start).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"canonical frame frontier changed"))?;let bytes=u64::try_from(len).map_err(|_|oom("canonical frame length exceeds u64"))?.to_le_bytes();self.out.get_mut(at..start).filter(|field|field.len()==8).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"canonical frame placeholder changed"))?.copy_from_slice(&bytes);},
            Task::Root(Root::Expression(value))=>self.expression(value)?,
            Task::Root(Root::Opaque(value))=>{
                self.bytes(b"dm-opaque-intrinsic-field-v1\0")?;self.symbol(value.owner)?;self.symbol(value.name)?;
                match value.declared_type{DeclaredTypeKnowledge::Known(path)=>{self.byte(1)?;self.symbol(path)?},DeclaredTypeKnowledge::Unsupported=>self.byte(0)?,DeclaredTypeKnowledge::KnownUntyped=>self.byte(2)?}
            },
            Task::Root(Root::Declaration(value))=>{self.bytes(b"dm-declaration-meaning-v1\0")?;self.push(Task::DeclarationField(value,0))?;},
            Task::DeclarationField(value,field)=>{
                if field<10{self.push(Task::DeclarationField(value,field+1))?}
                match field{
                    0=>{self.byte(u8::from(value.inherited_opaque.is_some()))?;if let Some(v)=&value.inherited_opaque{self.frame(Root::Opaque(v))?}},
                    1|2|3=>{let v=match field{1=>value.declared_type,2=>value.list_element_type,_=>value.display_name};self.byte(u8::from(v.is_some()))?;if let Some(v)=v{self.length(8)?;self.symbol(v)?}},
                    4=>self.bytes(&value.flags.to_le_bytes())?,
                    5=>{self.byte(u8::from(value.procedure.is_some()))?;if let Some(v)=&value.procedure{self.frame(Root::Procedure(v))?}},
                    6=>{self.byte(u8::from(value.array.is_some()))?;if let Some(v)=&value.array{self.frame(Root::Array(v))?}},
                    7=>self.optional_expression(value.initializer.as_ref())?,
                    8=>self.optional_expression(value.declared_initializer.as_ref())?,
                    9=>{self.byte(u8::from(value.resolved_constant.is_some()))?;if let Some(v)=&value.resolved_constant{self.frame(Root::Semantic(v))?}},
                    10=>{self.length(value.canonical.len())?;self.bytes(&value.canonical)?},
                    _=>unreachable!(),
                }
            },
            Task::Root(Root::Signature(value))=>{
                self.bytes(b"dm-procedure-signature-v2\0")?;self.byte(u8::from(value.variadic))?;self.length(value.parameters.len())?;
                self.push(Task::SignatureReturn(value))?;self.push(Task::Parameters(&value.parameters,0))?;
            },
            Task::SignatureReturn(value)=>self.optional_expression(value.return_annotation.as_ref())?,
            Task::Parameters(values,index)=>{if let Some(value)=values.get(index){self.push(Task::Parameters(values,index+1))?;self.push(Task::Parameter(value,0))?}},
            Task::Parameter(value,field)=>{
                if field<6{self.push(Task::Parameter(value,field+1))?}
                match field{
                    0=>{self.symbol(value.name)?;self.bytes(&value.flags.to_le_bytes())?;self.byte(u8::from(value.array.is_some()))?;if let Some(v)=&value.array{self.frame(Root::Array(v))?}},
                    1=>{self.byte(u8::from(value.declared_type.is_some()))?;self.bytes(&value.declared_type.map(SymbolId::bits).unwrap_or(0).to_le_bytes())?},
                    2=>self.optional_expression(value.default.as_ref())?,
                    3=>{self.byte(u8::from(value.list_element_type.is_some()))?;self.bytes(&value.list_element_type.map(SymbolId::bits).unwrap_or(0).to_le_bytes())?},
                    4=>self.optional_expression(value.input_annotation.as_ref())?,
                    5=>self.optional_expression(value.source_expression.as_ref())?,
                    6=>{},_=>unreachable!(),
                }
            },
            Task::Root(Root::Procedure(value))=>{
                self.bytes(b"dm-procedure-metadata-v2\0")?;self.push(Task::Settings(&value.settings))?;self.frame(Root::Signature(&value.signature))?;
            },
            Task::Settings(values)=>{self.length(values.len())?;self.push(Task::SettingItems(values,0))?},
            Task::SettingItems(values,index)=>{
                if let Some(value)=values.get(index){self.push(Task::SettingItems(values,index+1))?;match value{
                    ProcedureSettingNode::Setting(value)=>{self.byte(0)?;self.symbol(value.name)?;self.byte(value.operation as u8)?;self.optional_expression(Some(&value.value))?},
                    ProcedureSettingNode::Conditional{condition,then_branch,else_branch}=>{self.byte(1)?;self.push(Task::Settings(else_branch))?;self.push(Task::Settings(then_branch))?;self.optional_expression(Some(condition))?},
                    ProcedureSettingNode::UnsupportedContext{canonical_header,children}=>{self.byte(2)?;self.push(Task::Settings(children))?;self.optional_expression(Some(canonical_header))?},
                }}
            },
            Task::Root(Root::Array(value))=>value.try_write_canonical(&mut|chunk|self.bytes(chunk))?,
            Task::Root(Root::Semantic(value))=>match value{
                SemanticValue::Null=>self.byte(0)?,
                SemanticValue::NumberBits(bits)=>{self.byte(1)?;self.bytes(&bits.to_le_bytes())?},
                SemanticValue::Text(bytes)=>{self.byte(2)?;self.length(bytes.len())?;self.bytes(bytes)?},
                SemanticValue::Type(path)=>{self.byte(3)?;self.symbol(*path)?},
                SemanticValue::Resource(path)=>{self.byte(4)?;self.symbol(*path)?},
                SemanticValue::Procedure(identity)=>{self.byte(6)?;self.procedure_identity(identity)?},
                SemanticValue::ModifiedInstance(value)=>{self.byte(7)?;self.length(value.canonical_bytes().len())?;self.bytes(value.canonical_bytes())?},
                SemanticValue::List(values)=>{self.byte(5)?;self.length(values.len())?;self.push(Task::ListItems(values,0))?},
            },
            Task::ListItems(values,index)=>{if let Some((key,value))=values.get(index){self.push(Task::ListItems(values,index+1))?;self.byte(u8::from(key.is_some()))?;self.frame(Root::Semantic(value))?;if let Some(key)=key{self.frame(Root::Semantic(key))?}}},
            Task::Root(Root::Static(value))=>{
                self.bytes(b"dm-procedure-static-declaration-v2-lexical-locals\0")?;self.bytes(b"dm-procedure-static-identity-v1\0")?;self.procedure_identity(&value.identity.procedure)?;self.symbol(value.identity.name)?;self.bytes(&value.modifiers.to_le_bytes())?;
                self.byte(u8::from(value.declared_type.is_some()))?;if let Some(path)=value.declared_type{self.symbol(path)?}
                self.push(Task::StaticField(value,0))?;
            },
            Task::StaticField(value,field)=>match field{
                0=>{self.push(Task::StaticField(value,1))?;self.byte(u8::from(value.declared_array.is_some()))?;if let Some(value)=&value.declared_array{self.frame(Root::Array(value))?}},
                1=>{self.length(value.lexical_locals.len())?;for(name,ty)in value.lexical_locals.iter(){self.work.poll()?;self.symbol(*name)?;self.byte(u8::from(ty.is_some()))?;if let Some(ty)=ty{self.symbol(*ty)?}}self.push(Task::StaticField(value,2))?},
                2=>match &value.initializer{InitializerValue::NoAuthoredValue=>self.byte(0)?,InitializerValue::Expression(value)=>{self.byte(1)?;self.frame(Root::Expression(value))?},InitializerValue::ArrayAllocation(value)=>{self.byte(2)?;self.frame(Root::Array(value))?}},
                _=>unreachable!(),
            },
            Task::Root(Root::Meaning(value))=>self.meaning(value)?,
            Task::MeaningItems(values,index)=>{if let Some(value)=values.get(index){self.push(Task::MeaningItems(values,index+1))?;self.frame(Root::Meaning(value))?}},
        }Ok(())
    }
    fn meaning(&mut self,value:&'a ResolvedMeaning)->io::Result<()> {
        use ResolvedMeaning as M;
        if matches!(value,M::Missing|M::Symbol(_)|M::Symbols(_)) {
            let mut writer=crate::hierarchy_canonical::Writer::new(|bytes:&[u8]|self.bytes(bytes));
            return match value{M::Missing=>writer.missing(),M::Symbol(symbol)=>writer.symbol(*symbol),M::Symbols(symbols)=>{writer.symbols_start(symbols.len())?;for symbol in symbols.iter(){writer.symbol_item(*symbol)?}Ok(())},_=>unreachable!()};
        }
        self.bytes(b"dm-resolved-meaning-v1\0")?;
        match value{
            M::Missing=>unreachable!(),
            M::Unsupported(query)=>{
                self.byte(1)?;let at=self.out.len();self.length(0)?;let start=self.out.len();
                let mut first=None;
                struct Writer<'a,'b,'w>{owner:&'a mut Encoder<'b,'w>,first:&'a mut Option<io::Error>}
                impl io::Write for Writer<'_,'_,'_>{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::Error::other("earlier actual canonical sink failure"))}match self.owner.bytes(bytes){Ok(())=>Ok(bytes.len()),Err(actual)=>{*self.first=Some(actual);Err(io::Error::other("actual canonical sink failure"))}}}fn flush(&mut self)->io::Result<()>{Ok(())}}
                let result=serde_json::to_writer(Writer{owner:self,first:&mut first},query);
                if let Some(actual)=first{return Err(actual)}result.map_err(io::Error::other)?;self.step(Task::EndFrame{at,start})?;
            },
            M::Presence(value)=>{self.byte(2)?;self.byte(u8::from(*value))?},
            M::DeclaredType(value)=>{self.byte(3)?;self.byte(u8::from(value.is_some()))?;if let Some(value)=value{self.symbol(*value)?}},
            M::InstanceField{declaring_owner,name}=>{self.byte(4)?;self.symbol(*declaring_owner)?;self.symbol(*name)?},
            M::Value(value)=>{self.byte(5)?;self.frame(Root::Semantic(value))?},
            M::Slot{symbol,owner,name}=>{self.byte(6)?;self.symbol(*symbol)?;self.symbol(*owner)?;self.symbol(*name)?},
            M::Symbol(_)=>unreachable!(),
            M::Symbols(_)=>unreachable!(),
            M::Members(values)=>{self.byte(9)?;self.length(values.len())?;self.push(Task::MeaningItems(values,0))?},
            M::IntrinsicProc{declaring_owner,name}=>{self.byte(10)?;self.symbol(*declaring_owner)?;self.symbol(*name)?},
            M::RetainedProc{declaring_owner,name,verb,engine_identity,..}=>{self.byte(11)?;self.symbol(*declaring_owner)?;self.symbol(*name)?;self.byte(u8::from(*verb))?;self.bytes(&engine_identity.to_le_bytes())?},
            M::Member{owner,name,data,..}=>{self.byte(12)?;self.symbol(*owner)?;self.symbol(*name)?;self.frame(Root::Declaration(data))?},
            M::Resource{path,content}=>{self.byte(13)?;self.symbol(*path)?;self.bytes(&content.to_le_bytes())?},
            M::ProcedureStatic(value)=>{self.byte(14)?;self.frame(Root::Static(value))?},
            M::Declaration{identity,definition,previous,data}=>{self.byte(15)?;self.byte(u8::from(previous.is_some()))?;self.procedure_identity(identity)?;if let Some(previous)=previous{self.procedure_identity(previous)?}self.byte(match definition{ProcedureDefinition::Declare=>0,ProcedureDefinition::Override=>1,ProcedureDefinition::Reopen=>2,ProcedureDefinition::Implicit=>3})?;self.frame(Root::Declaration(data))?},
        }Ok(())
    }
}
pub(crate) fn encode(root:Root<'_>,work:&mut dyn CanonicalWork)->io::Result<Vec<u8>> {
    let mut encoder=Encoder{out:Vec::new(),tasks:Vec::new(),work};encoder.root(root)?;
    while let Some(task)=encoder.tasks.pop(){encoder.work.poll()?;encoder.step(task)?}
    let scratch=encoder.tasks.capacity().checked_mul(size_of::<Task<'_>>()).and_then(|n|n.checked_add(128))
        .ok_or_else(||oom("canonical task storage geometry overflow"))?;
    drop(encoder.tasks);
    encoder.work.release_retired(scratch)?;
    Ok(encoder.out)
}

#[cfg(test)]
#[path="canonical_encoding_tests.rs"]
mod tests;
