//! Shared /proc/PID/stat framing. Keep caller-specific identity and pidfd policy.
pub fn split(text:&str)->Option<(&str,&str)>{text.rsplit_once(") ")}
pub fn field(text:&str,index:usize)->Option<&str>{split(text)?.1.split_whitespace().nth(index)}
pub fn starttime(text:&str)->Option<&str>{field(text,19)}
#[cfg(test)] mod tests {
 use super::*;
 #[test] fn comm_may_contain_spaces_and_parentheses(){
  let text=format!("42 (name ) with (parens)) S 7 8 {} 987654 0",(0..16).map(|_|"0").collect::<Vec<_>>().join(" "));
  assert_eq!(field(&text,0),Some("S"));assert_eq!(field(&text,1),Some("7"));assert_eq!(field(&text,2),Some("8"));assert_eq!(starttime(&text),Some("987654"));
 }
 #[test] fn truncated_or_missing_frame_never_invents_identity(){assert_eq!(starttime("42 (name) S 1"),None);assert_eq!(field("bad",0),None);assert_eq!(field("42 (name) ",0),None);}
}
