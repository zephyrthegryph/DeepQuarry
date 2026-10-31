pub fn visit_defines(text: &str, mut take: impl FnMut(&str)) {
    if !text.contains("#define") {
        return;
    }
    for line in text.lines() {
        let t = line.trim_start();
        if let Some(rest) = t.strip_prefix('#') {
            let rest = rest.trim_start();
            if let Some(rest) = rest.strip_prefix("define") {
                let rest = rest.trim_start();
                let end = rest
                    .char_indices()
                    .take_while(|(_, c)| c.is_alphanumeric() || *c == '_')
                    .map(|(i, c)| i + c.len_utf8())
                    .last()
                    .unwrap_or(0);
                if end > 0 {
                    take(&rest[..end]);
                }
            }
        }
    }
}
