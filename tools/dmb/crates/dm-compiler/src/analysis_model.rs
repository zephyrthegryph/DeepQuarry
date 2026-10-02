//! Native semantic query adapter; evaluation reuses recorded compiler reads.
use super::*;
impl dm_analysis::ResolvedModel for SemanticDeclarations {
    fn owners(&self)->Vec<dm_analysis::ResolvedOwner> {
        let mut owners:Vec<_>=self.owners.iter().map(|(path,owner)|dm_analysis::ResolvedOwner {owner:path.clone(),parent:owner.parent.clone()}).collect();
        owners.sort_by(|left,right|left.owner.cmp(&right.owner));owners
    }
    fn fields(&self,owner:&str)->Vec<dm_analysis::ResolvedField> {
        let fields:Box<dyn Iterator<Item=(&String,&Field)>+'_>=if owner.is_empty() {Box::new(self.globals.iter())}
            else if let Some(scope)=self.owners.get(owner) {Box::new(scope.fields.iter())} else {Box::new(std::iter::empty())};
        let mut output:Vec<_>=fields.map(|(name,field)|dm_analysis::ResolvedField {owner:owner.to_owned(),name:name.clone(),constant:field.constant,override_only:field.override_only,expression:field.expression.clone()}).collect();
        output.sort_by(|left,right|left.name.cmp(&right.name));output
    }
    fn resolve_value(&self,owner:&str,name:&str)->dm_analysis::ResolvedValue {
        let reads=RefCell::new(BTreeMap::new());
        let value=self.field(owner,name,true,&mut HashSet::new(),&reads)
            .or_else(|| if owner.is_empty() {self.globals.get(name).and_then(|field|self.value("",name,field,&mut HashSet::new(),&reads))}else{None});
        dm_analysis::ResolvedValue {value:value.and_then(|value|serde_json::to_value(value).ok()),witnesses:reads.into_inner().into_iter().map(|(key,identity)|(serde_json::to_string(&key).unwrap_or_default(),identity)).collect()}
    }
}


pub(crate) fn build_fragments(fragments:&[dm_analysis::FrontendFragment],modified:&[Item],builtin:&Dmb,builtin_image:&[u8],previous:Option<&Arc<SemanticDeclarations>>,workers:usize)->Arc<SemanticDeclarations> {
    owner_dag::build_fragments(fragments,modified,builtin,builtin_image,previous,workers)
}
