use super::*;
fn frozen_original_decode(mut bytes: &[u8]) -> String {
    if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
        bytes = &bytes[3..];
    }
    let mut output = String::new();
    const C1: [char; 32] = [
        '\u{20ac}', '\u{81}', '\u{201a}', '\u{192}', '\u{201e}', '\u{2026}', '\u{2020}',
        '\u{2021}', '\u{2c6}', '\u{2030}', '\u{160}', '\u{2039}', '\u{152}', '\u{8d}', '\u{17d}',
        '\u{8f}', '\u{90}', '\u{2018}', '\u{2019}', '\u{201c}', '\u{201d}', '\u{2022}', '\u{2013}',
        '\u{2014}', '\u{2dc}', '\u{2122}', '\u{161}', '\u{203a}', '\u{153}', '\u{9d}', '\u{17e}',
        '\u{178}',
    ];
    while !bytes.is_empty() {
        match std::str::from_utf8(bytes) {
            Ok(text) => {
                output.push_str(text);
                break;
            }
            Err(error) => {
                let valid = error.valid_up_to();
                output.push_str(std::str::from_utf8(&bytes[..valid]).unwrap());
                let invalid = error.error_len().unwrap_or(bytes.len() - valid);
                for &byte in &bytes[valid..valid + invalid] {
                    output.push(if (0x80..=0x9f).contains(&byte) {
                        C1[(byte - 0x80) as usize]
                    } else {
                        char::from(byte)
                    });
                }
                bytes = &bytes[valid + invalid..];
            }
        }
    }
    output
}

#[test]fn all_single_byte_and_mixed_utf8_encodings_match_actual_old_decoder(){
 for n in 0..=255u8{for prefix in [&b""[..],&b"\xef\xbb\xbf"[..],"α".as_bytes()]{let mut bytes=prefix.to_vec();bytes.extend_from_slice(&[n,b'X']);bytes.extend_from_slice("漢".as_bytes());assert_eq!(decode_source_bytes(&bytes),frozen_original_decode(&bytes),"byte{n}");}}
 for bytes in [&b"\xf0\x9f"[..],&b"\xe2\x82X\xff"[..],&b"\xef\xbb\xbf"[..],&b""[..]]{assert_eq!(decode_source_bytes(bytes),frozen_original_decode(bytes));}
}
#[test]fn pieces_lend_actual_raw_ranges_and_exact_decoded_byte_geometry(){
 let bytes=b"\xef\xbb\xbfA\x80\xc3\xa9\xffZ";let decoded=decode_source_bytes(bytes);let mut output=String::new();let mut raw_end=0;let mut decoded_end=0;
 visit_decoded_source(bytes,|piece|->Result<(),()>{match piece{DecodedSourcePiece::Bom{raw}=>{assert_eq!(raw,Span::new(0,3));raw_end=raw.end;},DecodedSourcePiece::Utf8{raw,decoded:span,text}=>{assert_eq!(raw.start,raw_end);assert_eq!(span.start,decoded_end);assert_eq!(text.as_bytes(),&bytes[raw.range()]);assert_eq!(text,&decoded[span.range()]);output.push_str(text);raw_end=raw.end;decoded_end=span.end;},DecodedSourcePiece::LegacyByte{raw,decoded:span,value}=>{assert_eq!(raw.start,raw_end);assert_eq!((raw.end-raw.start),1);assert_eq!(span.start,decoded_end);assert_eq!((span.end-span.start),value.len_utf8());output.push(value);raw_end=raw.end;decoded_end=span.end;}}Ok(())}).unwrap();assert_eq!(raw_end,bytes.len());assert_eq!(decoded_end,decoded.len());assert_eq!(output,decoded);
}
#[test]fn sink_first_actual_io_stops_decoder_before_any_later_piece(){
 let mut visited=0;let error=visit_decoded_source(b"A\xffB\x80C",|_|{visited+=1;if visited==2{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(visited,2);
}
