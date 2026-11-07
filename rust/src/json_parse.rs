use super::V;
// Borrow raw values so number spelling and duplicate-key order survive parsing.
// serde_json performs syntax validation; retain the existing 96-level limit.
use serde::de::{Deserialize, Deserializer, MapAccess, Visitor};
use serde_json::value::RawValue;
use std::fmt;
pub(super) fn parse(s: &str) -> Result<V, String> {
    parse_depth(s, 0)
}
struct Pairs<'a>(Vec<(String, &'a RawValue)>);
impl<'de> Deserialize<'de> for Pairs<'de> {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct P;
        impl<'de> Visitor<'de> for P {
            type Value = Pairs<'de>;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("object")
            }
            fn visit_map<M: MapAccess<'de>>(self, mut m: M) -> Result<Self::Value, M::Error> {
                let mut rows = Vec::new();
                while let Some(row) = m.next_entry()? {
                    rows.push(row);
                }
                Ok(Pairs(rows))
            }
        }
        d.deserialize_map(P)
    }
}
fn parse_depth(s: &str, depth: usize) -> Result<V, String> {
    if depth > 96 {
        return Err("depth".into());
    }
    let s = s.trim_matches([' ', '\t', '\r', '\n']);
    let first = *s.as_bytes().first().ok_or("empty")?;
    Ok(match first {
        b'{' => {
            let pairs: Pairs = serde_json::from_str(s).map_err(|e| e.to_string())?;
            let mut rows = Vec::<(String, V)>::new();
            let mut indices = std::collections::HashMap::new();
            for (k, r) in pairs.0 {
                let v = parse_depth(r.get(), depth + 1)?;
                if let Some(&i) = indices.get(&k) {
                    rows[i] = (k, v);
                } else {
                    indices.insert(k.clone(), rows.len());
                    rows.push((k, v));
                }
            }
            V::Object(rows)
        }
        b'[' => {
            let rows: Vec<&RawValue> = serde_json::from_str(s).map_err(|e| e.to_string())?;
            V::Array(
                rows.into_iter()
                    .map(|r| parse_depth(r.get(), depth + 1))
                    .collect::<Result<_, _>>()?,
            )
        }
        b'"' => V::String(serde_json::from_str(s).map_err(|e| e.to_string())?),
        _ => {
            let r: &RawValue = serde_json::from_str(s).map_err(|e| e.to_string())?;
            V::Atom(r.get().to_owned())
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn numbers_preserve_spelling_without_float_conversion() {
        let input = "[1E+09,1e-0009,-0,1.2300,123456789012345678901234567890,1e9999]";
        assert_eq!(parse(input).unwrap().emit(false, 0), input);
    }
    #[test]
    fn duplicate_keys_keep_first_position_and_last_value() {
        assert_eq!(
            parse(r#"{"a":1,"b":2,"a":3,"\u0062":4}"#)
                .unwrap()
                .emit(false, 0),
            r#"{"a":3,"b":4}"#
        );
    }
    #[test]
    fn null_false_unicode_and_special_keys_are_not_sentinels() {
        let s = r#"{"$serde_json::private::Number":"1E9","x":null,"b":false,"emoji":"\ud83d\ude00","nul":"\u0000"}"#;
        let v = parse(s).unwrap();
        assert_eq!(v.get("emoji").unwrap().text(), Some("😀"));
        assert_eq!(v.get("nul").unwrap().text(), Some("\0"));
        assert!(!v.get("b").unwrap().truth());
        assert_eq!(
            v.get("$serde_json::private::Number").unwrap().text(),
            Some("1E9")
        );
    }
    #[test]
    fn rejects_invalid_syntax_and_non_json_whitespace() {
        for s in [
            "",
            "{}x",
            "[1,]",
            "01",
            "NaN",
            "\u{a0}{}",
            r#""\ud800""#,
            r#""\udc00""#,
            r#"{"a":"\q"}"#,
        ] {
            assert!(parse(s).is_err(), "{s:?}");
        }
    }
    #[test]
    fn depth_limit_matches_existing_contract() {
        assert!(parse(&("[".repeat(96) + "0" + &"]".repeat(96))).is_ok());
        for n in [97, 128, 1000, 10000] {
            assert!(parse(&("[".repeat(n) + "0" + &"]".repeat(n))).is_err());
        }
    }
}
