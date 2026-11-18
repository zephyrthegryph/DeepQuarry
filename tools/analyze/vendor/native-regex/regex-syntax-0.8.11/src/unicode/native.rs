//! Checked construction from the SAME canonical Unicode tables and queries.
use super::*;
use crate::native_admission::{Hook,Refused};

#[derive(Debug)]
pub(crate) enum Failure{Refused(Refused),Semantic(Error)}
impl From<Refused> for Failure{fn from(value:Refused)->Self{Self::Refused(value)}}
impl From<Error> for Failure{fn from(value:Error)->Self{Self::Semantic(value)}}
type Result<T>=core::result::Result<T,Failure>;

fn normalize(value:&str,hook:&Hook<'_>)->Result<String>{
    let mut bytes=Vec::new();hook.room(&mut bytes,value.len())?;
    bytes.extend_from_slice(value.as_bytes());
    let len=symbolic_name_normalize_bytes(&mut bytes).len();bytes.truncate(len);
    // Same normalization and checked UTF8 conversion as the pinned helper.
    Ok(String::from_utf8(bytes).unwrap())
}
fn binary(name:&str,hook:&Hook<'_>)->Result<CanonicalClassQuery>{
    let norm=normalize(name,hook)?;
    if norm!="cf"&&norm!="sc"&&norm!="lc"{
        if let Some(canon)=canonical_prop(&norm)?{return Ok(CanonicalClassQuery::Binary(canon))}
    }
    if let Some(canon)=canonical_gencat(&norm)?{return Ok(CanonicalClassQuery::GeneralCategory(canon))}
    if let Some(canon)=canonical_script(&norm)?{return Ok(CanonicalClassQuery::Script(canon))}
    Err(Error::PropertyNotFound.into())
}
fn canonicalize(query:ClassQuery<'_>,hook:&Hook<'_>)->Result<CanonicalClassQuery>{
    match query{
        ClassQuery::OneLetter(c)=>{let mut bytes=[0;4];binary(c.encode_utf8(&mut bytes),hook)},
        ClassQuery::Binary(name)=>binary(name,hook),
        ClassQuery::ByValue{property_name,property_value}=>{
            let name=normalize(property_name,hook)?;let value=normalize(property_value,hook)?;
            let canon=canonical_prop(&name)?.ok_or(Error::PropertyNotFound)?;
            Ok(match canon{
                "General_Category"=>CanonicalClassQuery::GeneralCategory(canonical_gencat(&value)?.ok_or(Error::PropertyValueNotFound)?),
                "Script"=>CanonicalClassQuery::Script(canonical_script(&value)?.ok_or(Error::PropertyValueNotFound)?),
                _=>{
                    let values=property_values(canon)?.ok_or(Error::PropertyValueNotFound)?;
                    let canonical_value=canonical_value(values,&value).ok_or(Error::PropertyValueNotFound)?;
                    CanonicalClassQuery::ByValue{property_name:canon,property_value:canonical_value}
                }
            })
        }
    }
}
pub(crate) fn hir_class(ranges:&[(char,char)],hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    Ok(hir::ClassUnicode::new_admitted(ranges.iter().map(|&(start,end)|hir::ClassUnicodeRange::new(start,end)),hook)?)
}
fn table(tables:&'static[(&'static str,Range)],name:&'static str,missing:Error,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    let actual=property_set(tables,name).ok_or(missing)?;hir_class(actual,hook)
}
pub(crate) fn class(query:ClassQuery<'_>,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;use CanonicalClassQuery::*;
    match canonicalize(query,hook)?{
        Binary(name)=>bool_property(name,hook),GeneralCategory(name)=>gencat(name,hook),Script(name)=>script(name,hook),
        ByValue{property_name:"Age",property_value}=>{
            let mut out=hir::ClassUnicode::empty();for ranges in ages(property_value)?{
                let actual=hir_class(ranges,hook)?;out.union_admitted(&actual,hook)?;
            }Ok(out)
        },
        ByValue{property_name:"Script_Extensions",property_value}=>script_extension(property_value,hook),
        ByValue{property_name:"Grapheme_Cluster_Break",property_value}=>gcb(property_value,hook),
        ByValue{property_name:"Sentence_Break",property_value}=>sb(property_value,hook),
        ByValue{property_name:"Word_Break",property_value}=>wb(property_value,hook),
        _=>Err(Error::PropertyNotFound.into()),
    }
}
pub(crate) fn perl_word(hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-perl")]
    {return hir_class(crate::unicode_tables::perl_word::PERL_WORD,hook)}
    #[cfg(not(feature="unicode-perl"))]
    {Err(Error::PerlClassNotFound.into())}
}
pub(crate) fn perl_space(hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-bool")]
    {return hir_class(crate::unicode_tables::property_bool::WHITE_SPACE,hook)}
    #[cfg(all(feature="unicode-perl",not(feature="unicode-bool")))]
    {return hir_class(crate::unicode_tables::perl_space::WHITE_SPACE,hook)}
    #[cfg(not(any(feature="unicode-perl",feature="unicode-bool")))]
    {Err(Error::PerlClassNotFound.into())}
}
pub(crate) fn perl_digit(hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-gencat")]
    {return hir_class(crate::unicode_tables::general_category::DECIMAL_NUMBER,hook)}
    #[cfg(all(feature="unicode-perl",not(feature="unicode-gencat")))]
    {return hir_class(crate::unicode_tables::perl_decimal::DECIMAL_NUMBER,hook)}
    #[cfg(not(any(feature="unicode-perl",feature="unicode-gencat")))]
    {Err(Error::PerlClassNotFound.into())}
}
fn gencat(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    if name=="Decimal_Number"{return perl_digit(hook)}
    #[cfg(feature="unicode-gencat")]
    {match name{
        "ASCII"=>hir_class(&[('\0','\x7F')],hook),"Any"=>hir_class(&[('\0','\u{10FFFF}')],hook),
        "Assigned"=>{let mut actual=gencat("Unassigned",hook)?;actual.negate_admitted(hook)?;Ok(actual)},
        _=>table(crate::unicode_tables::general_category::BY_NAME,name,Error::PropertyValueNotFound,hook),
    }}
    #[cfg(not(feature="unicode-gencat"))]
    {Err(Error::PropertyNotFound.into())}
}
fn bool_property(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    if name=="Decimal_Number"{return perl_digit(hook)}if name=="White_Space"{return perl_space(hook)}
    #[cfg(feature="unicode-bool")]
    {table(crate::unicode_tables::property_bool::BY_NAME,name,Error::PropertyNotFound,hook)}
    #[cfg(not(feature="unicode-bool"))]
    {Err(Error::PropertyNotFound.into())}
}

fn script(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-script")]
    {table(crate::unicode_tables::script::BY_NAME,name,Error::PropertyValueNotFound,hook)}
    #[cfg(not(feature="unicode-script"))]
    {Err(Error::PropertyNotFound.into())}
}

fn script_extension(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-script")]
    {table(crate::unicode_tables::script_extension::BY_NAME,name,Error::PropertyValueNotFound,hook)}
    #[cfg(not(feature="unicode-script"))]
    {Err(Error::PropertyNotFound.into())}
}

fn gcb(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-segment")]
    {table(crate::unicode_tables::grapheme_cluster_break::BY_NAME,name,Error::PropertyValueNotFound,hook)}
    #[cfg(not(feature="unicode-segment"))]
    {Err(Error::PropertyNotFound.into())}
}

fn wb(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-segment")]
    {table(crate::unicode_tables::word_break::BY_NAME,name,Error::PropertyValueNotFound,hook)}
    #[cfg(not(feature="unicode-segment"))]
    {Err(Error::PropertyNotFound.into())}
}

fn sb(name:&'static str,hook:&Hook<'_>)->Result<hir::ClassUnicode>{
    hook.checkpoint()?;
    #[cfg(feature="unicode-segment")]
    {table(crate::unicode_tables::sentence_break::BY_NAME,name,Error::PropertyValueNotFound,hook)}
    #[cfg(not(feature="unicode-segment"))]
    {Err(Error::PropertyNotFound.into())}
}
