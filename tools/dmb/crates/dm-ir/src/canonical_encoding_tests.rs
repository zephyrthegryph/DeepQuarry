//! Frozen pre-change native encoders, test-only byte authority.
//! Kept verbatim except method name/calls, so the new admitted implementation
//! cannot define its own expected encoding. No new production serializer.
use super::*;
use std::sync::Arc;
trait FrozenOldBytes{fn old_bytes(&self)->Vec<u8>;}
#[derive(Default)]struct Work{bytes:usize,polls:usize,limit:Option<usize>,io_at:Option<usize>}
impl CanonicalWork for Work{
 fn poll(&mut self)->io::Result<()>{self.polls+=1;if self.io_at==Some(self.polls){return Err(io::Error::from_raw_os_error(1450))}Ok(())}
 fn reserve(&mut self,bytes:usize)->io::Result<()>{let next=self.bytes.checked_add(bytes).ok_or_else(||oom("test work overflow"))?;if self.limit.is_some_and(|limit|next>limit){return Err(oom("actual canonical quota denied"))}self.bytes=next;Ok(())}
}
fn expression()->SymbolicExpression{
 use dm_syntax::{Span,TokenKind};
 SymbolicExpression{tokens:Arc::from([
  ExpressionToken{kind:TokenKind::Ident,text:SymbolId::of("x"),relative_span:Span::new(0,1)},
  ExpressionToken{kind:TokenKind::Operator,text:SymbolId::of("+"),relative_span:Span::new(1,2)},
  ExpressionToken{kind:TokenKind::Operator,text:SymbolId::of("+"),relative_span:Span::new(2,3)},
  ExpressionToken{kind:TokenKind::Operator,text:SymbolId::of("+"),relative_span:Span::new(4,5)},
 ])}
}
fn declaration()->DeclarationMeaning{
 let expression=expression();let array=Arc::new(ArrayDeclaration{dimensions:Arc::from([None,Some(expression.clone())]),element_type:Some(SymbolId::of("/datum/value"))});
 let procedure=Arc::new(ProcedureMetadata{
  signature:ProcedureSignature{variadic:true,parameters:Arc::from([Parameter::new(SymbolId::of("value"),Some(SymbolId::of("/list")),Some(SymbolId::of("/datum/value")),0x1234,dm_syntax::Span::new(100,200)).with_tail(crate::ParameterTail{array:Some(array.clone()),default:Some(expression.clone()),input_annotation:Some(expression.clone()),source_expression:Some(expression.clone())})]),return_annotation:Some(expression.clone())},
  settings:Arc::from([ProcedureSettingNode::Conditional{condition:expression.clone(),then_branch:Arc::from([ProcedureSettingNode::Setting(ProcedureSetting{name:SymbolId::of("setting"),operation:SettingOperation::In,value:expression.clone()})]),else_branch:Arc::from([ProcedureSettingNode::UnsupportedContext{canonical_header:expression.clone(),children:Arc::from([ProcedureSettingNode::Setting(ProcedureSetting{name:SymbolId::of("other"),operation:SettingOperation::Assign,value:expression.clone()})])}])}]),
 });
 DeclarationMeaning::new(Some(SymbolId::of("alias")),0x87654321,Some(procedure),"α authored header".as_bytes().into()).with_field_tail(DeclarationFieldMeaning{inherited_opaque:Some(OpaqueFieldBase{owner:SymbolId::of("/base"),name:SymbolId::of("opaque"),declared_type:DeclaredTypeKnowledge::Known(SymbolId::of("/datum"))}),declared_type:Some(SymbolId::of("/datum/value")),list_element_type:Some(SymbolId::of("/datum/element")),array:Some(array),initializer:Some(expression.clone()),declared_initializer:Some(expression),resolved_constant:Some(SemanticValue::List(Arc::from([(Some(SemanticValue::Text(Arc::from("key".as_bytes()))),SemanticValue::List(Arc::from([(None,SemanticValue::NumberBits(0x80000000)),(Some(SemanticValue::Type(SymbolId::of("/datum"))),SemanticValue::Resource(SymbolId::of("file.dmi")))]))),(None,SemanticValue::Null)])))})
}
#[test]fn admitted_native_canonical_encoder_matches_frozen_original_full_declarations_and_answers(){
 let data=Arc::new(declaration());let identity=ProcedureIdentity{owner:SymbolId::of("/datum"),name:SymbolId::of("probe"),verb:true,occurrence:7};
 let values=[SemanticValue::Null,SemanticValue::NumberBits(0x7fc01234),SemanticValue::Text(Arc::from("α".as_bytes())),SemanticValue::Type(identity.owner),SemanticValue::Procedure(identity),SemanticValue::Resource(identity.name),SemanticValue::ModifiedInstance(Arc::new(ModifiedInstance::capture(identity.owner,identity.owner,None,&[]))),data.resolved_constant.clone().unwrap()];
 for value in values{let mut work=Work::default();let actual=value.canonical_bytes_using(&mut work).unwrap();assert_eq!(actual,value.old_bytes());assert!(work.bytes>=actual.capacity());}
 assert_eq!(data.canonical_bytes_using(&mut Work::default()).unwrap(),data.old_bytes());assert_eq!(DeclarationMeaning::default().canonical_bytes_using(&mut Work::default()).unwrap(),DeclarationMeaning::default().old_bytes());
 for knowledge in [DeclaredTypeKnowledge::Known(identity.owner),DeclaredTypeKnowledge::KnownUntyped,DeclaredTypeKnowledge::Unsupported]{let value=OpaqueFieldBase{owner:identity.owner,name:identity.name,declared_type:knowledge};assert_eq!(value.canonical_bytes_using(&mut Work::default()).unwrap(),value.old_bytes());}
 let stored=Arc::new(ProcedureStaticDeclaration{identity:ProcedureStaticIdentity{procedure:identity,name:SymbolId::of("stored")},declared_type:Some(identity.owner),modifiers:19,declared_array:data.array.clone(),initializer:InitializerValue::Expression(expression()),lexical_locals:Arc::from([(identity.name,None),(identity.owner,Some(identity.owner))])});
 let rows=vec![ResolvedMeaning::Missing,ResolvedMeaning::Unsupported(ResolveQuery::Type(identity.owner)),ResolvedMeaning::Presence(false),ResolvedMeaning::DeclaredType(Some(identity.owner)),ResolvedMeaning::InstanceField{declaring_owner:identity.owner,name:identity.name},ResolvedMeaning::Value(data.resolved_constant.clone().unwrap()),ResolvedMeaning::Slot{symbol:identity.name,owner:identity.owner,name:identity.name},ResolvedMeaning::Symbol(identity.owner),ResolvedMeaning::Symbols(Arc::from([identity.owner,identity.name])),ResolvedMeaning::IntrinsicProc{declaring_owner:identity.owner,name:identity.name},ResolvedMeaning::RetainedProc{declaring_owner:identity.owner,name:identity.name,verb:true,engine_identity:123u128.into(),wire_proc:999},ResolvedMeaning::Member{owner:identity.owner,name:identity.name,fingerprint:321u128.into(),data:data.clone()},ResolvedMeaning::Resource{path:identity.name,content:456u128.into()},ResolvedMeaning::ProcedureStatic(stored),ResolvedMeaning::Declaration{identity,definition:ProcedureDefinition::Override,previous:Some(Box::new(ProcedureIdentity{occurrence:6,..identity})),data:data.clone()}];
 let answer=ResolvedMeaning::Members(rows.into());let mut work=Work::default();let actual=answer.canonical_bytes_using(&mut work).unwrap();assert_eq!(actual,answer.old_bytes());assert!(work.bytes>=actual.capacity());
 for initializer in [InitializerValue::NoAuthoredValue,InitializerValue::ArrayAllocation(data.array.clone().unwrap())]{let value=ProcedureStaticDeclaration{identity:ProcedureStaticIdentity{procedure:identity,name:identity.name},declared_type:None,modifiers:0,declared_array:None,initializer,lexical_locals:Arc::from([])};assert_eq!(value.canonical_bytes_using(&mut Work::default()).unwrap(),value.old_bytes());}
}
#[test]fn admitted_native_canonical_encoder_is_iterative_demand_owned_and_keeps_real_io_and_quota_failures(){
 let mut value=SemanticValue::Null;let mut owners=Vec::new();for _ in 0..3000{owners.push(value.clone());value=SemanticValue::List(Arc::from([(None,value)]));}
 let mut work=Work::default();let output=value.canonical_bytes_using(&mut work).unwrap();assert!(output.len()>50_000);assert!(work.polls>3000);assert!(work.bytes<32*1024*1024,"actual emitted bytes and maximum live task stack, never source-wide reservation");
 let denied=value.canonical_bytes_using(&mut Work{limit:Some(1024),..Work::default()}).unwrap_err();assert_eq!(denied.kind(),io::ErrorKind::OutOfMemory);
 let actual=value.canonical_bytes_using(&mut Work{io_at:Some(17),..Work::default()}).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450));
 // Retained shallow owners make fixture teardown iterative too; this control
 // is about the encoder, not changing the model's destruction contract.
 drop(value);while let Some(value)=owners.pop(){drop(value)}
 let healthy=SemanticValue::Null.canonical_bytes_using(&mut Work::default()).unwrap();assert_eq!(healthy,vec![0]);
}
#[test]
fn canonical_encoder_retires_actual_task_and_replaced_output_storage() {
 struct Exact { base: Work, peak: usize }
 impl CanonicalWork for Exact {
  fn poll(&mut self)->io::Result<()>{self.base.poll()}
  fn reserve(&mut self,bytes:usize)->io::Result<()>{
   self.base.reserve(bytes)?;
   self.peak=self.peak.max(self.base.bytes);
   Ok(())
  }
  fn release_retired(&mut self,bytes:usize)->io::Result<()>{
   self.base.bytes=self.base.bytes.checked_sub(bytes).expect("release only real live or prepaid bytes");
   Ok(())
  }
 }
 let procedure=declaration().procedure.unwrap();
 let mut previous=Work::default();
 let expected=procedure.canonical_bytes_using(&mut previous).unwrap();
 let mut exact=Exact{base:Work::default(),peak:0};
 let actual=procedure.canonical_bytes_using(&mut exact).unwrap();
 assert_eq!(actual,expected);
 assert_eq!(exact.base.polls,previous.polls);
 assert_eq!(exact.base.bytes,actual.capacity()+128,"actual task storage has already dropped");
 assert!(exact.peak<previous.bytes);
 let mut tight=Exact{base:Work{limit:Some(exact.peak),..Work::default()},peak:0};
 assert_eq!(procedure.canonical_bytes_using(&mut tight).unwrap(),expected);
 assert!(procedure.canonical_bytes_using(&mut Work{limit:Some(exact.peak),..Work::default()}).is_err());
}

#[test]
fn procedure_canonical_append_reuses_prefix_inline_and_releases_actual_spill() {
 struct Sink(Vec<u8>);
 impl CanonicalByteSink for Sink {
  fn append(&mut self, bytes:&[u8],work:&mut dyn CanonicalWork)->io::Result<()> {
   work.poll()?;
   assert!(self.0.len()+bytes.len()<=self.0.capacity(),"test sink is preallocated");
   self.0.extend_from_slice(bytes);
   Ok(())
  }
  fn written(&mut self)->&mut [u8]{self.0.as_mut_slice()}
 }
 #[derive(Default)]struct Scratch{work:Work,peak:usize}
 impl CanonicalWork for Scratch{
  fn poll(&mut self)->io::Result<()>{self.work.poll()}
  fn reserve(&mut self,n:usize)->io::Result<()>{
   self.work.reserve(n)?;self.peak=self.peak.max(self.work.bytes);Ok(())
  }
  fn release_retired(&mut self,n:usize)->io::Result<()>{self.work.bytes-=n;Ok(())}
 }
 let plain=ProcedureMetadata{
  signature:ProcedureSignature{parameters:Arc::from([]),variadic:false,return_annotation:None},
  settings:Arc::from([]),
 };
 let mut nested=Arc::<[ProcedureSettingNode]>::from([]);
 for _ in 0..24{
  nested=Arc::from([ProcedureSettingNode::UnsupportedContext{
   canonical_header:expression(),children:nested,
  }]);
 }
 let deep=ProcedureMetadata{signature:plain.signature.clone(),settings:nested};
 let prefix=b"issued lexical header";
 for (procedure,spills) in [(&plain,false),(&deep,true)]{
  let expected=procedure.old_bytes();
  let mut output=Sink(Vec::with_capacity(prefix.len()+expected.len()));
  output.0.extend_from_slice(prefix);
  let before=output.0.as_ptr();
  let mut scratch=Scratch::default();
  procedure.append_canonical_using(&mut output,&mut scratch).unwrap();
  assert_eq!(output.0.as_ptr(),before);
  assert_eq!(&output.0[..prefix.len()],prefix);
  assert_eq!(&output.0[prefix.len()..],expected.as_slice());
  assert_eq!(scratch.work.bytes,0);
  assert_eq!(scratch.peak!=0,spills);

  output.0.truncate(prefix.len());
  let mut failed=Scratch{work:Work{io_at:Some(17),..Work::default()},peak:0};
  let actual=procedure.append_canonical_using(&mut output,&mut failed).unwrap_err();
  assert_eq!(actual.raw_os_error(),Some(1450));
  assert_eq!(&output.0[..prefix.len()],prefix);
 }
}

#[test]
fn declaration_field_tail_preserves_empty_reads_and_logical_wire_bytes() {
    let procedure = declaration().procedure.unwrap();
    let a = DeclarationMeaning::new(None, 0, Some(procedure), b"header".as_slice().into());
    let b = a.clone();
    assert!(a.field_tail_allocation().is_none());
    assert!(b.field_tail_allocation().is_none());
    assert!(std::ptr::eq(&*a, &*b), "empty reads borrow one static field view");
    assert_eq!(a.canonical_bytes(), a.old_bytes());
    assert!(a.field_tail_allocation().is_none(), "encoding does not allocate a field tail");

    let mut explicit_empty = a.clone();
    explicit_empty.field_tail_mut();
    assert!(explicit_empty.field_tail_allocation().is_some());
    assert_eq!(a, explicit_empty);
    assert_eq!(a.canonical_bytes(), explicit_empty.canonical_bytes());
    let wire = crate::portable_meaning::PortableMeaning::capture(&a, true).unwrap();
    let same_wire = crate::portable_meaning::PortableMeaning::capture(&explicit_empty, true).unwrap();
    assert_eq!(serde_json::to_vec(&wire).unwrap(), serde_json::to_vec(&same_wire).unwrap());
    let restored = wire.restore(crate::portable_meaning::Names::unchecked()).unwrap();
    assert_eq!(restored, a);
    assert!(restored.field_tail_allocation().is_none());

    let fields = DeclarationFieldMeaning {
        resolved_constant: Some(SemanticValue::NumberBits(1)),
        ..Default::default()
    };
    assert_eq!(fields.allocation_bytes(), std::mem::size_of::<DeclarationFieldMeaning>());
    let field = DeclarationMeaning::default().with_field_tail(fields);
    assert_eq!(field.canonical_bytes(), field.old_bytes());
    assert!(field.field_tail_allocation().is_some());
}

impl FrozenOldBytes for SymbolicExpression{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = Vec::new();
        self.write_canonical(|chunk| bytes.extend_from_slice(chunk));
        bytes
    }}
impl FrozenOldBytes for ProcedureSignature{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-procedure-signature-v2\0");
        bytes.push(u8::from(self.variadic));
        bytes.extend_from_slice(&(self.parameters.len() as u64).to_le_bytes());
        for parameter in self.parameters.iter() {
            bytes.extend_from_slice(&parameter.name.bits().to_le_bytes());
            bytes.extend_from_slice(&parameter.flags.to_le_bytes());
            bytes.push(u8::from(parameter.array.is_some()));
            if let Some(array) = &parameter.array {
                let encoded = array.old_bytes();
                bytes.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
                bytes.extend_from_slice(&encoded);
            }
            bytes.push(u8::from(parameter.declared_type().is_some()));
            bytes.extend_from_slice(
                &parameter
                    .declared_type()
                    .map(SymbolId::bits)
                    .unwrap_or(0)
                    .to_le_bytes(),
            );
            append_expression(&mut bytes, parameter.default.as_ref());
            bytes.push(u8::from(parameter.list_element_type().is_some()));
            bytes.extend_from_slice(
                &parameter
                    .list_element_type()
                    .map(SymbolId::bits)
                    .unwrap_or(0)
                    .to_le_bytes(),
            );
            append_expression(&mut bytes, parameter.input_annotation.as_ref());
            append_expression(&mut bytes, parameter.source_expression.as_ref());
        }
        append_expression(&mut bytes, self.return_annotation.as_ref());
        bytes
    }}
impl FrozenOldBytes for ProcedureMetadata{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-procedure-metadata-v2\0");
        let signature = self.signature.old_bytes();
        bytes.extend_from_slice(&(signature.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&signature);
        append_settings(&mut bytes, &self.settings);
        bytes
    }}
impl FrozenOldBytes for ArrayDeclaration{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = Vec::new();
        self.write_canonical(|chunk| bytes.extend_from_slice(chunk));
        bytes
    }}
impl FrozenOldBytes for SemanticValue{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = Vec::new();
        match self {
            Self::Null => bytes.push(0),
            Self::NumberBits(number) => {
                bytes.push(1);
                bytes.extend_from_slice(&number.to_le_bytes());
            }
            Self::Text(text) => {
                bytes.push(2);
                bytes.extend_from_slice(&(text.len() as u64).to_le_bytes());
                bytes.extend_from_slice(text);
            }
            Self::Type(path) => {
                bytes.push(3);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
            Self::Procedure(procedure) => {
                bytes.push(6);
                bytes.extend_from_slice(&procedure.owner.bits().to_le_bytes());
                bytes.extend_from_slice(&procedure.name.bits().to_le_bytes());
                bytes.push(u8::from(procedure.verb));
                bytes.extend_from_slice(&procedure.occurrence.to_le_bytes());
            }
            Self::ModifiedInstance(instance) => {
                bytes.push(7);
                let data = instance.old_bytes();
                bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                bytes.extend_from_slice(&data);
            }
            Self::Resource(path) => {
                bytes.push(4);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
            Self::List(entries) => {
                bytes.push(5);
                bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
                for (key, value) in entries.iter() {
                    bytes.push(u8::from(key.is_some()));
                    if let Some(key) = key {
                        let data = key.old_bytes();
                        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                        bytes.extend_from_slice(&data);
                    }
                    let data = value.old_bytes();
                    bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                    bytes.extend_from_slice(&data);
                }
            }
        }
        bytes
    }}
impl FrozenOldBytes for OpaqueFieldBase{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = b"dm-opaque-intrinsic-field-v1\0".to_vec();
        bytes.extend_from_slice(&self.owner.bits().to_le_bytes());
        bytes.extend_from_slice(&self.name.bits().to_le_bytes());
        match self.declared_type {
            DeclaredTypeKnowledge::Known(path) => {
                bytes.push(1);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
            DeclaredTypeKnowledge::Unsupported => bytes.push(0),
            DeclaredTypeKnowledge::KnownUntyped => bytes.push(2),
        }
        bytes
    }}
impl FrozenOldBytes for DeclarationMeaning{fn old_bytes(&self)->Vec<u8>{
        fn part(out: &mut Vec<u8>, bytes: &[u8]) {
            out.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            out.extend_from_slice(bytes);
        }
        fn optional(out: &mut Vec<u8>, bytes: Option<Vec<u8>>) {
            out.push(u8::from(bytes.is_some()));
            if let Some(bytes) = bytes {
                part(out, &bytes);
            }
        }
        let mut out = b"dm-declaration-meaning-v1\0".to_vec();
        optional(
            &mut out,
            self.inherited_opaque.as_ref().map(|v| v.old_bytes()),
        );
        for value in [
            self.declared_type,
            self.list_element_type,
            self.display_name(),
        ] {
            optional(&mut out, value.map(|v| v.bits().to_le_bytes().to_vec()));
        }
        out.extend_from_slice(&self.flags.to_le_bytes());
        optional(
            &mut out,
            self.procedure.as_ref().map(|v| v.old_bytes()),
        );
        optional(&mut out, self.array.as_ref().map(|v| v.old_bytes()));
        optional(
            &mut out,
            self.initializer.as_ref().map(|v| v.old_bytes()),
        );
        optional(
            &mut out,
            self.declared_initializer
                .as_ref()
                .map(|v| v.old_bytes()),
        );
        optional(
            &mut out,
            self.resolved_constant.as_ref().map(|v| v.old_bytes()),
        );
        part(&mut out, &self.canonical.to_vec());
        out
    }}
fn append_expression(bytes: &mut Vec<u8>, value: Option<&SymbolicExpression>) {
    bytes.push(u8::from(value.is_some()));
    if let Some(value) = value {
        let data = value.old_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
}
fn append_settings(bytes: &mut Vec<u8>, nodes: &[ProcedureSettingNode]) {
    bytes.extend_from_slice(&(nodes.len() as u64).to_le_bytes());
    for node in nodes {
        match node {
            ProcedureSettingNode::Setting(setting) => {
                bytes.push(0);
                bytes.extend_from_slice(&setting.name.bits().to_le_bytes());
                bytes.push(setting.operation as u8);
                append_expression(bytes, Some(&setting.value));
            }
            ProcedureSettingNode::Conditional {
                condition,
                then_branch,
                else_branch,
            } => {
                bytes.push(1);
                append_expression(bytes, Some(condition));
                append_settings(bytes, then_branch);
                append_settings(bytes, else_branch);
            }
            ProcedureSettingNode::UnsupportedContext {
                canonical_header,
                children,
            } => {
                bytes.push(2);
                append_expression(bytes, Some(canonical_header));
                append_settings(bytes, children);
            }
        }
    }
}
impl FrozenOldBytes for ProcedureStaticDeclaration{fn old_bytes(&self)->Vec<u8>{
        let mut bytes = b"dm-procedure-static-declaration-v2-lexical-locals\0".to_vec();
        bytes.extend_from_slice(&self.identity.old_bytes());
        bytes.extend_from_slice(&self.modifiers.to_le_bytes());
        match self.declared_type {
            None => bytes.push(0),
            Some(path) => {
                bytes.push(1);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
        }
        fn part(bytes: &mut Vec<u8>, value: &[u8]) {
            bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
            bytes.extend_from_slice(value);
        }
        match &self.declared_array {
            None => bytes.push(0),
            Some(array) => {
                bytes.push(1);
                part(&mut bytes, &array.old_bytes());
            }
        }
        bytes.extend_from_slice(&(self.lexical_locals.len() as u64).to_le_bytes());
        for (name, declared_type) in self.lexical_locals.iter() {
            bytes.extend_from_slice(&name.bits().to_le_bytes());
            bytes.push(u8::from(declared_type.is_some()));
            if let Some(path) = declared_type {
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
        }
        match &self.initializer {
            InitializerValue::NoAuthoredValue => bytes.push(0),
            InitializerValue::Expression(value) => {
                bytes.push(1);
                part(&mut bytes, &value.old_bytes());
            }
            InitializerValue::ArrayAllocation(value) => {
                bytes.push(2);
                part(&mut bytes, &value.old_bytes());
            }
        }
        bytes
    }}
impl FrozenOldBytes for ProcedureStaticIdentity{fn old_bytes(&self)->Vec<u8>{self.canonical_bytes()}}
impl FrozenOldBytes for ModifiedInstance{fn old_bytes(&self)->Vec<u8>{self.canonical_bytes().to_vec()}}
impl FrozenOldBytes for ResolvedMeaning{fn old_bytes(&self)->Vec<u8>{
        // The source hierarchy endpoint streams this SAME encoding without
        // allocating ancestry/canonical output; other meaning families retain
        // their existing encoding below.
        if matches!(self, Self::Missing | Self::Symbol(_) | Self::Symbols(_)) {
            let mut out = Vec::new();
            let mut writer = crate::hierarchy_canonical::Writer::new(|bytes: &[u8]| {
                out.extend_from_slice(bytes);
                Ok(())
            });
            match self {
                Self::Missing => writer.missing(),
                Self::Symbol(symbol) => writer.symbol(*symbol),
                Self::Symbols(symbols) => writer.symbols_start(symbols.len()).and_then(|()| {
                    for symbol in symbols.iter() {
                        writer.symbol_item(*symbol)?;
                    }
                    Ok(())
                }),
                _ => unreachable!(),
            }
            .expect("Vec canonical sink cannot return an IO error");
            return out;
        }
        fn frame(out: &mut Vec<u8>, bytes: &[u8]) {
            out.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            out.extend_from_slice(bytes);
        }
        fn symbol(out: &mut Vec<u8>, value: SymbolId) {
            out.extend_from_slice(&value.bits().to_le_bytes());
        }
        let mut out = b"dm-resolved-meaning-v1\0".to_vec();
        match self {
            Self::Missing => out.push(0),
            Self::Unsupported(query) => {
                out.push(1);
                frame(
                    &mut out,
                    &serde_json::to_vec(query).expect("query serialization is infallible"),
                );
            }
            Self::Presence(value) => {
                out.extend_from_slice(&[2, u8::from(*value)]);
            }
            Self::DeclaredType(value) => {
                out.extend_from_slice(&[3, u8::from(value.is_some())]);
                if let Some(value) = value {
                    symbol(&mut out, *value);
                }
            }
            Self::InstanceField {
                declaring_owner,
                name,
            } => {
                out.push(4);
                symbol(&mut out, *declaring_owner);
                symbol(&mut out, *name);
            }
            Self::Value(value) => {
                out.push(5);
                frame(&mut out, &value.old_bytes());
            }
            Self::Slot {
                symbol: slot,
                owner,
                name,
            } => {
                out.push(6);
                symbol(&mut out, *slot);
                symbol(&mut out, *owner);
                symbol(&mut out, *name);
            }
            Self::Symbol(value) => {
                out.push(7);
                symbol(&mut out, *value);
            }
            Self::Symbols(values) => {
                out.push(8);
                out.extend_from_slice(&(values.len() as u64).to_le_bytes());
                for value in values.iter() {
                    symbol(&mut out, *value);
                }
            }
            Self::Members(values) => {
                out.push(9);
                out.extend_from_slice(&(values.len() as u64).to_le_bytes());
                for value in values.iter() {
                    frame(&mut out, &value.old_bytes());
                }
            }
            Self::IntrinsicProc {
                declaring_owner,
                name,
            } => {
                out.push(10);
                symbol(&mut out, *declaring_owner);
                symbol(&mut out, *name);
            }
            Self::RetainedProc {
                declaring_owner,
                name,
                verb,
                engine_identity,
                ..
            } => {
                out.push(11);
                symbol(&mut out, *declaring_owner);
                symbol(&mut out, *name);
                out.push(u8::from(*verb));
                out.extend_from_slice(&engine_identity.to_le_bytes());
                // The immutable engine identity qualifies its named callable;
                // its physical procedure-table index is not semantic evidence.
            }
            Self::Member {
                owner, name, data, ..
            } => {
                out.push(12);
                symbol(&mut out, *owner);
                symbol(&mut out, *name);
                frame(&mut out, &data.old_bytes());
            }
            Self::Resource { path, content } => {
                out.push(13);
                symbol(&mut out, *path);
                out.extend_from_slice(&content.to_le_bytes());
            }
            Self::Declaration {
                identity,
                definition,
                previous,
                data,
            } => {
                out.push(15);
                out.push(u8::from(previous.is_some()));
                let mut declaration = |identity: &crate::ProcedureIdentity| {
                    symbol(&mut out, identity.owner);
                    symbol(&mut out, identity.name);
                    out.push(u8::from(identity.verb));
                    out.extend_from_slice(&identity.occurrence.to_le_bytes());
                };
                declaration(identity);
                if let Some(previous) = previous {
                    declaration(previous);
                }
                out.push(match definition {
                    ProcedureDefinition::Declare => 0,
                    ProcedureDefinition::Override => 1,
                    ProcedureDefinition::Reopen => 2,
                    ProcedureDefinition::Implicit => 3,
                });
                frame(&mut out, &data.old_bytes());
            }
            Self::ProcedureStatic(value) => {
                out.push(14);
                frame(&mut out, &value.old_bytes());
            }
        }
        out
    }}

#[test]
fn compact_declaration_display_name_preserves_zero_presence_and_wire_bytes() {
    use crate::portable_meaning::{Names, PortableMeaning};

    #[cfg(target_pointer_width = "64")]
    assert_eq!(std::mem::size_of::<DeclarationMeaning>(), 48);

    let mut declaration = DeclarationMeaning::default();
    let missing = declaration.clone();
    assert_eq!(declaration.display_name(), None);
    declaration.set_display_name(Some(SymbolId::ZERO));
    assert_eq!(declaration.display_name(), Some(SymbolId::ZERO));
    assert_ne!(declaration, missing);
    assert_ne!(declaration.canonical_bytes(), missing.canonical_bytes());
    assert_eq!(declaration.canonical_bytes(), declaration.old_bytes());
    let wire = PortableMeaning::capture(&declaration, true).unwrap();
    let restored = wire.restore(Names::unchecked()).unwrap();
    assert_eq!(restored.display_name(), Some(SymbolId::ZERO));
    assert_eq!(restored, declaration);
    declaration.set_display_name(None);
    assert_eq!(declaration, missing);
    assert_eq!(declaration.canonical_bytes(), missing.canonical_bytes());
}
