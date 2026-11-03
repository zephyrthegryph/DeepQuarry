//! SAME native source decoder with explicit raw/decoded geometry.
//! Pieces are borrowed DATA from the real decoder, never acquisition authority.
use dm_syntax::Span;
#[derive(Clone,Copy,Debug)]
pub enum DecodedSourcePiece<'a>{
    Bom{raw:Span},
    Utf8{raw:Span,decoded:Span,text:&'a str},
    LegacyByte{raw:Span,decoded:Span,value:char},
}
/// Visit the actual decoder once without allocating a second source/map. The
/// sink may stop with its exact error; no later piece or source work is visited.
pub fn visit_decoded_source<E>(original:&[u8],mut emit:impl FnMut(DecodedSourcePiece<'_>)->Result<(),E>)->Result<(),E>{
    let mut raw_offset=0usize;let mut decoded_offset=0usize;
    if original.starts_with(&[0xef,0xbb,0xbf]){emit(DecodedSourcePiece::Bom{raw:Span::new(0,3)})?;raw_offset=3;}
    let mut bytes=&original[raw_offset..];
    const C1: [char; 32] = [
        '\u{20ac}', '\u{81}', '\u{201a}', '\u{192}', '\u{201e}', '\u{2026}', '\u{2020}',
        '\u{2021}', '\u{2c6}', '\u{2030}', '\u{160}', '\u{2039}', '\u{152}', '\u{8d}', '\u{17d}',
        '\u{8f}', '\u{90}', '\u{2018}', '\u{2019}', '\u{201c}', '\u{201d}', '\u{2022}', '\u{2013}',
        '\u{2014}', '\u{2dc}', '\u{2122}', '\u{161}', '\u{203a}', '\u{153}', '\u{9d}', '\u{17e}',
        '\u{178}',
    ];
    while !bytes.is_empty(){
        match std::str::from_utf8(bytes){
            Ok(value)=>{emit(DecodedSourcePiece::Utf8{raw:Span::new(raw_offset,raw_offset+bytes.len()),decoded:Span::new(decoded_offset,decoded_offset+value.len()),text:value})?;break;},
            Err(error)=>{
                let valid=error.valid_up_to();
                if valid!=0{let value=std::str::from_utf8(&bytes[..valid]).expect("validated UTF8 prefix");emit(DecodedSourcePiece::Utf8{raw:Span::new(raw_offset,raw_offset+valid),decoded:Span::new(decoded_offset,decoded_offset+valid),text:value})?;raw_offset+=valid;decoded_offset+=valid;}
                let invalid=error.error_len().unwrap_or(bytes.len()-valid);
                for &byte in &bytes[valid..valid+invalid]{let value=if(0x80..=0x9f).contains(&byte){C1[(byte-0x80)as usize]}else{char::from(byte)};let width=value.len_utf8();emit(DecodedSourcePiece::LegacyByte{raw:Span::new(raw_offset,raw_offset+1),decoded:Span::new(decoded_offset,decoded_offset+width),value})?;raw_offset+=1;decoded_offset+=width;}
                bytes=&bytes[valid+invalid..];
            }
        }
    }Ok(())
}
pub fn decode_source_bytes(bytes:&[u8])->String{
    let mut output=String::new();let result:Result<(),std::convert::Infallible>=visit_decoded_source(bytes,|piece|{match piece{DecodedSourcePiece::Bom{..}=>{},DecodedSourcePiece::Utf8{text,..}=>output.push_str(text),DecodedSourcePiece::LegacyByte{value,..}=>output.push(value)}Ok(())});match result{Ok(())=>output,Err(impossible)=>match impossible{}}
}
#[cfg(test)]mod tests;

/// Exact-capacity admitted facade of the SAME decoder. The caller pays the
/// actual layout before allocation, and retains its raw input during this copy.
/// No decoded/source role is certified by resource geometry alone.
pub fn decode_source_bytes_admitted(bytes:&[u8],before_allocate:&mut dyn FnMut(usize)->std::io::Result<()>,checkpoint:&mut dyn FnMut()->std::io::Result<()>)->std::io::Result<String>{
 let mut length=0usize;visit_decoded_source(bytes,|piece|{checkpoint()?;match piece{DecodedSourcePiece::Bom{..}=>(),DecodedSourcePiece::Utf8{decoded,..}|DecodedSourcePiece::LegacyByte{decoded,..}=>length=decoded.end}Ok::<_,std::io::Error>(())})?;
 before_allocate(length)?;checkpoint()?;if length==0{return Ok(String::new())}
 let layout=std::alloc::Layout::array::<u8>(length).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;
 // SAFETY: exact Global u8 allocation matches Vec. Null is handled before
 // owner construction. The SAME decoder writes exactly the admitted UTF8 size.
 let pointer=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)}).ok_or(std::io::ErrorKind::OutOfMemory)?;
 let buffer=unsafe{Vec::from_raw_parts(pointer.as_ptr(),0,length)};let mut output=unsafe{String::from_utf8_unchecked(buffer)};
 visit_decoded_source(bytes,|piece|{checkpoint()?;match piece{DecodedSourcePiece::Bom{..}=>(),DecodedSourcePiece::Utf8{text,..}=>output.push_str(text),DecodedSourcePiece::LegacyByte{value,..}=>output.push(value)}Ok::<_,std::io::Error>(())})?;
 if output.len()!=length||output.capacity()!=length{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual decoder output differs from its admitted SAME-visitor geometry"))}Ok(output)
}

#[cfg(test)]mod admitted_decode_tests{
 use super::*;use std::io;
 #[test]fn admitted_exact_allocation_uses_same_decoder_values_including_bom_c1_mixed_utf8_and_empty(){
  for raw in [&b""[..],&b"plain"[..],&b"\xef\xbb\xbfplain"[..],&b"\xef\xbb\xbfA\x80\xc3\xa9\xffZ"[..],&b"\xf0\x9f"[..]]{
   let mut paid=None;let actual=decode_source_bytes_admitted(raw,&mut|n|{assert!(paid.replace(n).is_none());Ok(())},&mut||Ok(())).unwrap();assert_eq!(actual,decode_source_bytes(raw));assert_eq!(paid,Some(actual.len()));assert_eq!(actual.capacity(),actual.len());
  }
 }
 #[test]fn actual_first_allocation_or_piece_error_is_not_source_absence_and_fresh_decode_recovers(){
  let error=decode_source_bytes_admitted(b"\x80X",&mut|_|Err(io::Error::from_raw_os_error(1450)),&mut||Ok(())).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));let calls=std::cell::Cell::new(0);let error=decode_source_bytes_admitted(b"\x80X",&mut|_|Ok(()),&mut||{calls.set(calls.get()+1);if calls.get()==3{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(calls.get(),3);assert_eq!(decode_source_bytes_admitted(b"good",&mut|_|Ok(()),&mut||Ok(())).unwrap(),"good");
 }
}

#[path="source_decode/point_geometry.rs"]
mod point_geometry;
pub(crate) use point_geometry::{DecodedPointException, DecodedPointGeometry, visit_decoded_point_exceptions};
