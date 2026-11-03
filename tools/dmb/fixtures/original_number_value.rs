//! Frozen independent SpacemanDMM0290 lexer::read_number body (GPL-3.0).
//! Only its existing normalized input/context interfaces are adapted for unit
//! observation. No current native conversion/classifier is called here.
use std::{borrow::Cow,str::FromStr,cell::RefCell,rc::Rc};
#[derive(Clone,Copy)]enum Severity{Warning}
struct Diagnostic{message:String,warning:bool,error_type:Option<String>}
impl Diagnostic{fn set_severity(mut self,_:Severity)->Self{self.warning=true;self}fn with_errortype(mut self,text:&str)->Self{self.error_type=Some(text.into());self}fn register(self,context:&Context){context.register_error(self)}}
struct Context{notices:Rc<RefCell<Vec<Diagnostic>>>}impl Context{fn register_error(&self,diagnostic:Diagnostic){self.notices.borrow_mut().push(diagnostic);}}
enum Token{Int(i32),Float(f32)}
struct Lexer<'a>{integer:bool,radix:u32,buffer:&'a str,context:&'a Context}
impl Lexer<'_>{fn read_number_inner(&mut self,_:u8)->(bool,u32,Cow<'static,str>){(self.integer,self.radix,Cow::Owned(self.buffer.to_owned()))}fn error(&self,message:String)->Diagnostic{Diagnostic{message,warning:false,error_type:None}}
    fn read_number(&mut self, first: u8) -> Token {
        let (integer, radix, buf) = self.read_number_inner(first);
        if integer {
            let original_error = match i32::from_str_radix(&buf, radix) {
                Ok(val) => return Token::Int(val),
                Err(e) => e,
            };
            // Try to parse it as a float instead - this will catch numbers
            // that are formatted like integers but are out of the range of our
            // integer type.
            if radix == 10 {
                if let Ok(val) = f32::from_str(&buf) {
                    let val_str = val.to_string();
                    if val_str != buf {
                        self.error(format!("precision loss of integer constant: \"{buf}\" to {val}"))
                            .set_severity(Severity::Warning)
                            .with_errortype("integer_precision_loss")
                            .register(self.context);
                    }
                    return Token::Float(val)
                }
            }
            self.context.register_error(self.error(
                format!("bad base-{radix} integer \"{buf}\": {original_error}")));
            Token::Int(0)  // fallback
        } else {
            // ignore radix
            match f32::from_str(&buf) {
                Ok(val) => Token::Float(val),
                Err(e) => {
                    self.context.register_error(self.error(
                        format!("bad float \"{buf}\": {e}")));
                    Token::Float(0.0)  // fallback
                }
            }
        }
    }

}
pub(super) struct Observed{pub value:(bool,u32),pub notice:Option<(String,bool,Option<String>)>}
pub(super) fn observe(integer:bool,radix:u32,buffer:&str)->Observed{let notices=Rc::new(RefCell::new(Vec::new()));let context=Context{notices:notices.clone()};let mut lexer=Lexer{integer,radix,buffer,context:&context};let token=lexer.read_number(b'0');let value=match token{Token::Int(n)=>(true,n as u32),Token::Float(n)=>(false,n.to_bits())};let mut rows=notices.borrow_mut();assert!(rows.len()<=1);let notice=rows.pop().map(|d|(d.message,d.warning,d.error_type));Observed{value,notice}}
