//! Current-DME read-only schema evidence. No parser, value inference, source
//! acquisition, report completion flag or authored-file writer lives here.
use super::*;

#[derive(Default, Debug)]
pub struct SchemaLiteralEvidence {
    paths: Vec<String>,
    texts: usize,
    nums: usize,
    other: usize,
}
impl SchemaLiteralEvidence {
    pub fn paths(&self) -> &[String] { &self.paths }
    pub fn texts(&self) -> usize { self.texts }
    pub fn nums(&self) -> usize { self.nums }
    pub fn other(&self) -> usize { self.other }
}
#[derive(Debug)]
pub struct SchemaProposalRow {
    declaration: dm_tree::MemberId,
    owner: SymbolId,
    name: SymbolId,
    file: String,
    line: usize,
    owner_text: String,
    name_text: String,
    evidence: SchemaLiteralEvidence,
    repeated_literal_parent: Option<String>,
}
impl SchemaProposalRow {
    pub fn declaration(&self) -> dm_tree::MemberId { self.declaration }
    pub fn owner(&self) -> SymbolId { self.owner }
    pub fn name(&self) -> SymbolId { self.name }
    pub fn file(&self) -> &str { &self.file }
    pub fn line(&self) -> usize { self.line }
    pub fn owner_text(&self) -> &str { &self.owner_text }
    pub fn name_text(&self) -> &str { &self.name_text }
    pub fn evidence(&self) -> &SchemaLiteralEvidence { &self.evidence }
    pub fn repeated_literal_parent(&self) -> Option<&str> { self.repeated_literal_parent.as_deref() }
}
pub struct SchemaProposalData { rows: Vec<SchemaProposalRow> }
impl SchemaProposalData {
    pub fn rows(&self) -> &[SchemaProposalRow] { &self.rows }
    /// Read-only report encoding over owned facts. The host MUST preserve its
    /// original request deadline and exact source/config barriers around this.
    /// No formatting allocation or source/parent lookup occurs during output.
    pub fn write_text(&self, poll: &dyn Fn() -> std::io::Result<()>, out: &mut dyn std::io::Write) -> std::io::Result<()> {
        use std::io::Write;
        for row in &self.rows {
            poll()?;
            write!(out,"{}:{}: PROPOSED (not applied; a person reviews the base): SCHEMA({}, {}, ",row.file,row.line,row.owner_text,row.name_text)?;
            let e=&row.evidence;
            if !e.paths.is_empty()&&e.texts==0&&e.nums==0 {
                let first=&e.paths[0];let mut equal=true;
                for path in &e.paths { poll()?;equal&=path==first; }
                if equal {
                    if let Some(parent)=row.repeated_literal_parent.as_deref().filter(|p|*p!="/") {
                        write!(out,"schema_path({parent})")?;
                    } else { out.write_all(b"schema_path(/*base: review*/)")?; }
                } else {
                    let mut keep=first.split('/').filter(|part|!part.is_empty()).count();
                    for path in &e.paths[1..] {
                        poll()?;let mut n=0;
                        for (a,b) in first.split('/').filter(|p|!p.is_empty()).zip(path.split('/').filter(|p|!p.is_empty())) {
                            poll()?;if a!=b {break} n+=1;
                        }
                        keep=keep.min(n);
                    }
                    if keep==0 {out.write_all(b"schema_path(/*base: review*/)")?;} else {
                        out.write_all(b"schema_path(")?;
                        for part in first.split('/').filter(|p|!p.is_empty()).take(keep) {poll()?;out.write_all(b"/")?;out.write_all(part.as_bytes())?;}
                        out.write_all(b")")?;
                    }
                }
            } else if e.texts>0&&e.paths.is_empty()&&e.nums==0 {out.write_all(b"schema_text()")?;}
            else if e.nums>0&&e.paths.is_empty()&&e.texts==0 {out.write_all(b"num()")?;}
            else {out.write_all(b"/*kind: review*/")?;}
            out.write_all(b")\n")?;
        }
        poll()?;
        writeln!(out,"{} proposal(s); nothing was written (--apply does not apply a schema_path base).",self.rows.len())
    }
}

#[derive(Default)]
pub(super) struct Accumulator { fields: BTreeMap<(SymbolId, SymbolId), SchemaLiteralEvidence> }
fn owned<W: crate::policy_body_demand::WorkspaceWork>(text: &str, work: &mut W) -> Result<String, W::Error> {
    work.checkpoint()?;
    let retention_bytes = text.len().checked_add(128).ok_or_else(|| work.overflow())?;
    work.retain(retention_bytes)?;
    let mut out = String::new();
    out.try_reserve_exact(text.len()).map_err(|_| work.allocation_failed())?;
    if out.capacity() > text.len().checked_add(128).ok_or_else(|| work.overflow())? { return Err(work.allocation_failed()); }
    out.push_str(text);
    Ok(out)
}
fn row<T, W: crate::policy_body_demand::WorkspaceWork>(rows: &mut Vec<T>, work: &mut W) -> Result<(), W::Error> {
    work.checkpoint()?;
    if rows.len() == rows.capacity() {
        let next = rows.capacity().checked_mul(2).map(|v| v.max(4)).ok_or_else(|| work.overflow())?;
        let retention_bytes = next.checked_mul(std::mem::size_of::<T>()).and_then(|n| n.checked_add(128)).ok_or_else(|| work.overflow())?;
        work.retain(retention_bytes)?;
        rows.try_reserve_exact(next - rows.len()).map_err(|_| work.allocation_failed())?;
        if rows.capacity() > next { return Err(work.allocation_failed()); }
    }
    Ok(())
}
impl Accumulator {
    pub(super) fn observe<W: crate::policy_body_demand::WorkspaceWork>(
        &mut self, owner: SymbolId, name: SymbolId, rhs: &Expr, work: &mut W,
    ) -> Result<(), W::Error> {
        work.checkpoint()?;
        if !self.fields.contains_key(&(owner, name)) {
            // Same conservative BTree-node allowance as the existing untyped
            // groups. Variable-width path/String buffers are charged separately.
            work.retain(2048)?;
            self.fields.insert((owner, name), SchemaLiteralEvidence::default());
        }
        let evidence = self.fields.get_mut(&(owner, name)).expect("inserted native field");
        let mut paths = Vec::new();
        super::path_literals_using(rhs, &mut paths, work)?;
        if !paths.is_empty() {
            for path in paths { row(&mut evidence.paths, work)?; evidence.paths.push(path); }
            return work.checkpoint();
        }
        let slot = match &rhs.kind {
            ExprKind::Literal(value) => match value.original_value() {
                Some(dm_syntax::OriginalTokenValue::Int(_) | dm_syntax::OriginalTokenValue::Float(_)) => &mut evidence.nums,
                Some(dm_syntax::OriginalTokenValue::String(_)) => &mut evidence.texts,
                Some(_) => &mut evidence.other,
                None if value.owns_template_syntax() => {
                    // Borrow only already-admitted native syntax. Never call a
                    // runtime decoder or parse a string on demand for evidence.
                    let parts = value.prepared_syntax_parts().ok_or("schema proposal interpolation cache is not admitted")?
                        .map_err(|_| "schema proposal interpolation syntax is invalid")?
                        .ok_or("schema proposal template has no native syntax parts")?;
                    parts.lexical.as_ref().map_err(|_| "schema proposal interpolation lexical data is invalid")?;
                    &mut evidence.texts
                }
                None => return Err("schema proposal literal lacks its actual Original value role".into()),
            },
            _ => &mut evidence.other,
        };
        *slot = slot.checked_add(1).ok_or_else(|| work.overflow())?;
        work.checkpoint()
    }
}

pub(super) fn finish<W: crate::policy_body_demand::WorkspaceWork>(
    archive: &BodyArchive, findings: Vec<Finding>, mut collected: Accumulator, root: &std::path::Path,
    project: &dyn Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>, work: &mut W,
) -> Result<SchemaProposalData, W::Error> {
    work.checkpoint()?;
    let tree = archive.tree(); let symbols = tree.symbols();
    // Join by the exact existing display identity, but NEVER parse that identity
    // or a finding message into fields or use it to derive a schema. Typed keys
    // below came only from the same current native scope/place observer.
    let mut keys = BTreeMap::new();
    for &(owner, name) in collected.fields.keys() {
        work.checkpoint()?;
        let owner_text = symbols.text(owner).ok_or("schema owner spelling missing")?;
        let name_text = symbols.text(name).ok_or("schema field spelling missing")?;
        let width = owner_text.len().checked_add(name_text.len()).and_then(|n| n.checked_add(2)).ok_or_else(|| work.overflow())?;
        let retention_bytes = width.checked_add(2048).ok_or_else(|| work.overflow())?;
        work.retain(retention_bytes)?;
        let mut identity = String::new(); identity.try_reserve_exact(width).map_err(|_| work.allocation_failed())?;
        if identity.capacity() > width { return Err(work.allocation_failed()); }
        identity.push_str(owner_text); identity.push_str("::"); identity.push_str(name_text);
        if keys.insert(identity, (owner, name)).is_some() { return Err("native schema field identity collision".into()); }
    }
    let mut output = SchemaProposalData { rows: Vec::new() };
    // Existing native findings already have the exact legacy declaration sort,
    // final Typed-over-Call precedence, CODE and declaration-exemption filters.
    for finding in findings {
        work.checkpoint()?;
        if finding.rule != Rule::Call { continue; }
        let &(owner, name) = keys.get(&finding.identity).ok_or("native Call finding lacks its same-pass schema evidence")?;
        let evidence = collected.fields.remove(&(owner, name)).ok_or("native schema candidate was emitted twice")?;
        let ty = tree.lookup_type(owner).ok_or("native schema owner missing")?;
        let selected = tree.resolve(ty, name, dm_tree::MemberKind::Var).ok_or("native schema field missing")?;
        let mut declaration = selected;
        for id in tree.override_chain_iter(selected) {
            work.checkpoint()?;
            if tree.member(id).is_some_and(|node| node.definition == dm_tree::DefinitionMode::Declare
                && tree.type_node(node.owner).is_some_and(|ty| ty.path == owner)) {
                declaration = id; break;
            }
        }
        let source = archive.member_location(declaration).ok_or("native schema declaration source missing")?;
        let source = project(PolicyAnchor::Declaration(declaration), source)?;
        let retention_bytes = source.path.as_os_str().len().checked_add(root.as_os_str().len())
            .and_then(|n| n.checked_mul(8)).and_then(|n| n.checked_add(2048)).ok_or_else(|| work.overflow())?;
        work.retain(retention_bytes)?;
        if super::relative(root, &source.path) != finding.file || source.line != finding.line {
            return Err("native schema candidate declaration differs from its actual untyped finding".into());
        }
        let mut repeated_literal_parent = None;
        if let Some(first) = evidence.paths.first() {
            let mut equal = true;
            for path in &evidence.paths { work.checkpoint()?; equal &= path == first; }
            if equal {
                if let Some(parent) = tree.lookup_type(SymbolId::of(first)).and_then(|ty| tree.parent(ty)) {
                    let parent = tree.type_node(parent).ok_or("native schema literal parent missing")?;
                    repeated_literal_parent = Some(owned(symbols.text(parent.path).ok_or("native schema parent spelling missing")?, work)?);
                }
            }
        }
        row(&mut output.rows, work)?;
        output.rows.push(SchemaProposalRow { declaration, owner, name,
            file: owned(&finding.file, work)?, line: finding.line,
            owner_text: owned(symbols.text(owner).ok_or("native schema owner spelling missing")?, work)?,
            name_text: owned(symbols.text(name).ok_or("native schema field spelling missing")?, work)?,
            evidence, repeated_literal_parent });
    }
    work.checkpoint()?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::policy_body_demand::{PolicyFailure, WorkspaceWork};
    use std::sync::atomic::Ordering;
    struct Work<'a> {
        admission: &'a dm_syntax::SettingAdmission<'a>,
        leases: Vec<dm_syntax::SettingRootLease>,
        polls: usize,
        stop: Option<usize>,
    }
    impl WorkspaceWork for Work<'_> {
        type Error = PolicyFailure;
        const CHECKED: bool = true;
        fn checkpoint(&mut self) -> Result<(), Self::Error> {
            self.polls += 1;
            if self.stop == Some(self.polls) { return Err(PolicyFailure::Operational(std::io::Error::from_raw_os_error(1450))); }
            Ok(())
        }
        fn retain(&mut self, bytes: usize) -> Result<(), Self::Error> {
            self.leases.push(self.admission.reserve(bytes).map_err(PolicyFailure::Operational)?); Ok(())
        }
        fn temporary(&mut self, bytes: usize) -> Result<(), Self::Error> { self.retain(bytes) }
        fn overflow(&mut self) -> Self::Error { PolicyFailure::Operational(std::io::ErrorKind::OutOfMemory.into()) }
        fn allocation_failed(&mut self) -> Self::Error { self.overflow() }
        fn body<'a>(&mut self, _: &'a BodyArchive, _: usize) -> Result<ArchivedBody<'a>, Self::Error> {
            panic!("DATA-only evidence controls cannot manufacture a native BODY loan")
        }
    }
    fn report_data(paths: &[&str], texts: usize, nums: usize, other: usize, parent: Option<&str>) -> SchemaProposalData {
        // Formatter DATA only; this does not execute/claim a current query or
        // construct its private CurrentArchivedBody/source-completion receipt.
        SchemaProposalData { rows: vec![SchemaProposalRow { declaration: dm_tree::MemberId(0),
            owner: SymbolId::of("/datum/base"), name: SymbolId::of("value"),
            owner_text: "/datum/base".into(), name_text: "value".into(), file: "code/example.dm".into(), line: 7,
            evidence: SchemaLiteralEvidence { paths: paths.iter().map(|v| (*v).into()).collect(), texts, nums, other },
            repeated_literal_parent: parent.map(str::to_owned) }] }
    }
    fn rendered(data: &SchemaProposalData) -> String {
        let mut text=Vec::new();data.write_text(&||Ok(()),&mut text).unwrap();String::from_utf8(text).unwrap()
    }
    #[test]
    fn native_schema_owned_report_keeps_effective_parent_and_lexical_prefix_distinct() {
        assert!(rendered(&report_data(&["/datum/nest/leaf","/datum/nest/leaf"],0,0,99,Some("/datum/override")))
            .contains("SCHEMA(/datum/base, value, schema_path(/datum/override))\n"));
        assert!(rendered(&report_data(&["/datum/nest/a","/datum/nest/b"],0,0,99,Some("/ignored")))
            .contains("schema_path(/datum/nest)"));
        assert!(rendered(&report_data(&["/datum"],0,0,99,Some("/"))).contains("schema_path(/*base: review*/)"));
        assert!(rendered(&report_data(&["/a","/b"],0,0,99,None)).contains("schema_path(/*base: review*/)"));
    }
    #[test]
    fn native_schema_owned_report_keeps_other_counts_and_exact_zero_footer() {
        assert!(rendered(&report_data(&[],1,0,99,None)).contains("schema_text()"));
        assert!(rendered(&report_data(&[],0,1,99,None)).contains("num()"));
        assert!(rendered(&report_data(&[],1,1,99,None)).contains("/*kind: review*/"));
        assert_eq!(rendered(&SchemaProposalData{rows:Vec::new()}),
            "0 proposal(s); nothing was written (--apply does not apply a schema_path base).\n");
    }
    #[test]
    fn native_schema_evidence_uses_typed_scalar_data_and_path_first_ternary_policy() {
        let base=dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let counter=dm_syntax::SettingChargeCounter::try_new(base).unwrap();
        let admission=dm_syntax::SettingAdmission::new(&counter,8<<20,&||Ok(()));
        let mut work=Work{admission:&admission,leases:Vec::new(),polls:0,stop:None};let mut data=Accumulator::default();
        let owner=SymbolId::of("/datum/base");let name=SymbolId::of("value");
        // Typed literal DATA uses its real existing admission. It confers no
        // Original expression/body/source authority by itself.
        for (raw,value) in [("1",dm_syntax::OriginalTokenValue::Int(1)),("\"text\"",dm_syntax::OriginalTokenValue::String("text"))] {
            let literal=dm_syntax::LiteralText::from_original_value_data(raw.into(),0,value,&admission).unwrap();
            data.observe(owner,name,&Expr{span:Span::new(0,raw.len()),kind:ExprKind::Literal(literal)},&mut work).unwrap();
        }
        let conditional=dm_syntax::parse_expression("flag ? /datum/a : \"text\"").expr.unwrap();
        data.observe(owner,name,&conditional,&mut work).unwrap();
        let evidence=&data.fields[&(owner,name)];assert_eq!((evidence.paths.as_slice(),evidence.texts,evidence.nums,evidence.other),(&["/datum/a".to_string()][..],1,1,0));
        drop(data);drop(work);assert_eq!(counter.load(Ordering::Acquire),base);
    }
    #[test]
    fn native_schema_evidence_denies_before_new_storage_and_refunds_actual_credit() {
        let base=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(base).unwrap();
        let admission=dm_syntax::SettingAdmission::new(&counter,base,&||Ok(()));
        let mut work=Work{admission:&admission,leases:Vec::new(),polls:0,stop:None};let mut data=Accumulator::default();
        let value=dm_syntax::parse_expression("/datum/a").expr.unwrap();
        let error=data.observe(SymbolId::of("/datum/base"),SymbolId::of("value"),&value,&mut work).unwrap_err();
        assert!(matches!(error,PolicyFailure::Operational(error)if error.kind()==std::io::ErrorKind::OutOfMemory));
        assert!(data.fields.is_empty());drop(work);assert_eq!(counter.load(Ordering::Acquire),base);
    }
    #[test]
    fn native_schema_evidence_keeps_first_actual_poll_error_before_any_accumulation() {
        let base=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(base).unwrap();
        let admission=dm_syntax::SettingAdmission::new(&counter,8<<20,&||Ok(()));
        let mut work=Work{admission:&admission,leases:Vec::new(),polls:0,stop:Some(1)};let mut data=Accumulator::default();
        let value=dm_syntax::parse_expression("/datum/a").expr.unwrap();
        let error=data.observe(SymbolId::of("/datum/base"),SymbolId::of("value"),&value,&mut work).unwrap_err();
        assert!(matches!(error,PolicyFailure::Operational(error)if error.raw_os_error()==Some(1450)));assert_eq!(work.polls,1);assert!(data.fields.is_empty());
        drop(work);assert_eq!(counter.load(Ordering::Acquire),base);
    }
    #[test]
    fn native_schema_owned_report_stops_on_first_actual_poll_or_output_error() {
        let data=report_data(&[],0,0,1,None);let mut bytes=Vec::new();
        let error=data.write_text(&||Err(std::io::Error::from_raw_os_error(1450)),&mut bytes).unwrap_err();
        assert_eq!(error.raw_os_error(),Some(1450));assert!(bytes.is_empty());
        struct Stop(usize);impl std::io::Write for Stop {
            fn write(&mut self,_:&[u8])->std::io::Result<usize>{self.0+=1;Err(std::io::Error::from_raw_os_error(1450))}
            fn flush(&mut self)->std::io::Result<()>{panic!("no flush after first actual error")}
        }
        let mut output=Stop(0);assert_eq!(data.write_text(&||Ok(()),&mut output).unwrap_err().raw_os_error(),Some(1450));assert_eq!(output.0,1);
    }
}
