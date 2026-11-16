///|
/// XML Formatter — MoonBit port of python xmlformatter

// ===== Token Types =====

///|
priv enum XmlToken {
  XmlDecl(String, String?, Bool?) // version, encoding, standalone
  StartElement(String, Array[(String, String)]) // name, attrs
  EndElement(String) // name
  CharacterData(String) // text
  Comment(String) // text
  ProcessingInstruction(String, String) // target, data
  StartCdataSection
  EndCdataSection
  // Verbatim `<!...>` declaration (DOCTYPE, ELEMENT, ENTITY, ATTLIST, ...).
  // Kept byte-for-byte so nothing the author wrote is lost or rewritten.
  Declaration(String)
}

// ===== Options =====

///|
pub(all) struct XmlOptions {
  indent : Int32
  indent_char : String
  compress : Bool
  selfclose : Bool
  selfclose_space : Bool
  inline : Bool
  correct : Bool
  blanks : Bool
  eof_newline : Bool
  preserve : Array[String]
  preserve_attributes : Bool
  encode_attributes : Bool
}

///|
pub fn default_options() -> XmlOptions {
  {
    indent: 2,
    indent_char: " ",
    compress: false,
    selfclose: false,
    selfclose_space: false,
    inline: true,
    correct: true,
    blanks: false,
    eof_newline: false,
    preserve: [],
    preserve_attributes: false,
    encode_attributes: false,
  }
}

// ===== Helper Functions =====

///|
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_empty_str(s : String) -> Bool {
  let chars = s.to_array()
  for c in chars {
    if !is_whitespace(c) {
      return false
    }
  }
  true
}

///|
fn str_contains(arr : Array[String], val : String) -> Bool {
  for v in arr {
    if v == val {
      return true
    }
  }
  false
}

///|
fn trim_quotes(s : String) -> String {
  if s.length() > 1 && s.has_prefix("\"") && s.has_suffix("\"") {
    s.unsafe_substring(start=1, end=s.length() - 1)
  } else if s.length() > 1 && s.has_prefix("'") && s.has_suffix("'") {
    s.unsafe_substring(start=1, end=s.length() - 1)
  } else {
    s
  }
}

///|
fn encode_attribute(val : String, encode : Bool) -> String {
  let mut v = val
  v = v.replace_all(old="&", new="&amp;")
  v = v.replace_all(old="<", new="&lt;")
  v = v.replace_all(old="\"", new="&quot;")
  if encode {
    v = v.replace_all(old=">", new="&gt;")
    v = v.replace_all(old="'", new="&apos;")
  }
  v
}

///|
fn indent_prefix(level : Int32, options : XmlOptions) -> String {
  if options.compress || options.indent == 0 || level < 0 {
    ""
  } else {
    let n = level * options.indent
    let c = if options.indent_char.length() > 0 {
      options.indent_char.to_array()[0]
    } else {
      ' '
    }
    "\n" + String::make(n, c)
  }
}

///|
fn trim_str(s : String) -> String {
  s.trim().to_owned()
}

// ===== Parser =====

///|
fn parse_xml(input : String) -> Array[XmlToken] {
  let tokens = []
  let chars = input.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    if chars[i] == '<' {
      if i + 1 < n && chars[i + 1] == '?' {
        // PI or XmlDecl
        i = i + 2
        let target = StringBuilder()
        while i < n && chars[i] != ' ' && chars[i] != '?' && chars[i] != '>' {
          target.write_char(chars[i])
          i = i + 1
        }
        // Skip space
        while i < n && chars[i] == ' ' {
          i = i + 1
        }
        let data = StringBuilder()
        while i < n && chars[i] != '?' && chars[i] != '>' {
          data.write_char(chars[i])
          i = i + 1
        }
        if i < n && chars[i] == '?' {
          i = i + 1
        }
        if i < n && chars[i] == '>' {
          i = i + 1
        }
        if target.to_string() == "xml" {
          let attrs = parse_attrs(data.to_string())
          let version = get_attr(attrs, "version").unwrap_or("1.0")
          let encoding = get_attr(attrs, "encoding")
          let standalone = match get_attr(attrs, "standalone") {
            Some(v) => Some(v == "yes")
            None => None
          }
          tokens.push(XmlToken::XmlDecl(version, encoding, standalone))
        } else {
          tokens.push(
            XmlToken::ProcessingInstruction(
              target.to_string(),
              trim_str(data.to_string()),
            ),
          )
        }
      } else if i + 3 < n &&
        chars[i + 1] == '!' &&
        chars[i + 2] == '-' &&
        chars[i + 3] == '-' {
        // Comment
        i = i + 4
        let text = StringBuilder()
        while i + 2 < n &&
              !(chars[i] == '-' && chars[i + 1] == '-' && chars[i + 2] == '>') {
          text.write_char(chars[i])
          i = i + 1
        }
        if i + 2 < n {
          i = i + 3
        }
        tokens.push(XmlToken::Comment(text.to_string()))
      } else if i + 1 < n && chars[i + 1] == '!' {
        // CDATA or another `<!...>` declaration
        let is_cdata = i + 8 < n &&
          chars[i + 2] == '[' &&
          chars[i + 3] == 'C' &&
          chars[i + 4] == 'D' &&
          chars[i + 5] == 'A' &&
          chars[i + 6] == 'T' &&
          chars[i + 7] == 'A' &&
          chars[i + 8] == '['
        if is_cdata {
          i = i + 9
          let text = StringBuilder()
          while i + 2 < n &&
                !(chars[i] == ']' && chars[i + 1] == ']' && chars[i + 2] == '>') {
            text.write_char(chars[i])
            i = i + 1
          }
          if i + 2 < n {
            i = i + 3
          }
          tokens.push(XmlToken::StartCdataSection)
          tokens.push(XmlToken::CharacterData(text.to_string()))
          tokens.push(XmlToken::EndCdataSection)
        } else {
          // Any other `<!...>` declaration (DOCTYPE, ELEMENT, ENTITY, ...):
          // keep it verbatim, including an internal subset `[...]`, whose
          // contents may themselves contain `>` and nested declarations.
          let start = i
          i = i + 2
          let mut depth = 0
          while i < n {
            if chars[i] == '[' {
              depth = depth + 1
            } else if chars[i] == ']' {
              depth = depth - 1
            } else if chars[i] == '>' && depth == 0 {
              break
            }
            i = i + 1
          }
          let raw = if i < n {
            // chars[i] is the closing '>' of the declaration
            let raw = input.unsafe_substring(start~, end=i + 1)
            i = i + 1
            raw
          } else {
            // Unterminated declaration: keep whatever input remains.
            input.unsafe_substring(start~, end=n)
          }
          tokens.push(XmlToken::Declaration(raw))
        }
      } else {
        // Element start or end
        i = i + 1
        let is_end = if i < n && chars[i] == '/' {
          i = i + 1
          true
        } else {
          false
        }
        let name = StringBuilder()
        while i < n && chars[i] != '>' && chars[i] != ' ' && chars[i] != '/' {
          name.write_char(chars[i])
          i = i + 1
        }
        if is_end {
          if i < n && chars[i] == '>' {
            i = i + 1
          }
          tokens.push(XmlToken::EndElement(name.to_string()))
        } else {
          // Parse attributes
          let attrs = []
          while i < n && chars[i] != '>' && chars[i] != '/' {
            if chars[i] == ' ' {
              i = i + 1
              continue
            }
            let aname = StringBuilder()
            while i < n &&
                  chars[i] != '=' &&
                  chars[i] != '>' &&
                  chars[i] != '/' &&
                  chars[i] != ' ' {
              aname.write_char(chars[i])
              i = i + 1
            }
            if i < n && chars[i] == '=' {
              i = i + 1
              if i < n && (chars[i] == '"' || chars[i] == '\'') {
                let quote = chars[i]
                i = i + 1
                let aval = StringBuilder()
                while i < n && chars[i] != quote {
                  aval.write_char(chars[i])
                  i = i + 1
                }
                if i < n && chars[i] == quote {
                  i = i + 1
                }
                attrs.push((aname.to_string(), aval.to_string()))
              } else {
                attrs.push((aname.to_string(), ""))
              }
            } else if !aname.is_empty() {
              attrs.push((aname.to_string(), ""))
            }
          }
          let selfclose = if i < n && chars[i] == '/' {
            i = i + 1
            true
          } else {
            false
          }
          if i < n && chars[i] == '>' {
            i = i + 1
          }
          if selfclose {
            tokens.push(XmlToken::StartElement(name.to_string(), attrs))
            tokens.push(XmlToken::EndElement(name.to_string()))
          } else {
            tokens.push(XmlToken::StartElement(name.to_string(), attrs))
          }
        }
      }
    } else {
      // Character data
      let text = StringBuilder()
      while i < n && chars[i] != '<' {
        text.write_char(chars[i])
        i = i + 1
      }
      tokens.push(XmlToken::CharacterData(text.to_string()))
    }
  }
  tokens
}

///|
fn collect_iter(iter : Iter[StringView]) -> Array[String] {
  let arr = []
  for v in iter {
    arr.push(v.to_owned())
  }
  arr
}

///|
fn parse_attrs(s : String) -> Array[(String, String)] {
  let attrs = []
  let parts = collect_iter(s.trim().to_owned().split(" "))
  for part in parts {
    let kv = part.split_once("=")
    match kv {
      Some((k, v)) => {
        let key = trim_str(k.to_owned())
        let val = trim_quotes(trim_str(v.to_owned()))
        attrs.push((key, val))
      }
      None => ()
    }
  }
  attrs
}

///|
fn get_attr(attrs : Array[(String, String)], key : String) -> String? {
  for (k, v) in attrs {
    if k == key {
      return Some(v)
    }
  }
  None
}

// ===== Level Computation =====

///|
fn compute_levels(tokens : Array[XmlToken]) -> Array[Int32] {
  let n = tokens.length()
  let levels = Array::make(n, 0)
  let mut lvl = 0
  for i in 0..<n {
    match tokens[i] {
      XmlToken::StartElement(_, _) => {
        levels[i] = lvl
        lvl = lvl + 1
      }
      XmlToken::EndElement(_) => {
        // A stray closing tag can drive the running level below zero; clamp it
        // so a negative indent width never reaches `String::make` (which aborts).
        if lvl > 0 {
          lvl = lvl - 1
        }
        levels[i] = lvl
      }
      _ => levels[i] = lvl
    }
  }
  levels
}

// ===== Content Model Computation =====

///|
fn compute_content_models(
  tokens : Array[XmlToken],
  levels : Array[Int32],
) -> Array[Int32] {
  let n = tokens.length()
  let models = Array::make(n, 0)
  for i in 0..<n {
    match tokens[i] {
      XmlToken::StartElement(_, _) => {
        let level_i = levels[i]
        let mut eflag = 0
        let mut tflag = 0
        for j in (i + 1)..<n {
          if levels[j] <= level_i {
            break
          }
          if levels[j] == level_i + 1 {
            match tokens[j] {
              XmlToken::StartElement(_, _) => eflag = 1
              XmlToken::CharacterData(text) =>
                if !is_empty_str(text) {
                  tflag = 2
                }
              _ => ()
            }
          }
        }
        models[i] = eflag + tflag
      }
      _ => ()
    }
  }
  models
}

// ===== Render =====

///|
fn render_attrs(
  attrs : Array[(String, String)],
  options : XmlOptions,
) -> String {
  let mut result = ""
  // Collect names
  let names = []
  for (name, _) in attrs {
    if !str_contains(names, name) {
      names.push(name)
    }
  }
  // Sort if not preserving
  if !options.preserve_attributes {
    let mut changed = true
    while changed {
      changed = false
      for i in 0..<(names.length() - 1) {
        if names[i] > names[i + 1] {
          let tmp = names[i]
          names[i] = names[i + 1]
          names[i + 1] = tmp
          changed = true
        }
      }
    }
  }
  // Render each attribute
  for name in names {
    // Find value
    let mut val = ""
    let mut found = false
    for (n, v) in attrs {
      if n == name {
        val = v
        found = true
        break
      }
    }
    if found {
      let encoded_val = encode_attribute(val, options.encode_attributes)
      result = result + " " + name + "=\"" + encoded_val + "\""
    }
  }
  result
}

///|
pub fn format(xml : String, options : XmlOptions) -> String {
  let tokens = parse_xml(xml)
  let n = tokens.length()
  let levels = compute_levels(tokens)
  let content_models = compute_content_models(tokens, levels)

  // Most recent start-element index seen at each level; used by the inline
  // indent rule instead of an O(n) backward scan per token.
  let mut max_level = 0
  for lvl in levels {
    if lvl > max_level {
      max_level = lvl
    }
  }
  let last_start : Array[Int32] = Array::make(max_level + 1, -1)

  let out = []

  // State
  let mut preserve_level : Int32? = None
  let mut desc_mixed_level : Int32? = None
  let mut indent_level : Int32? = None
  let mut cdata_section = false

  for i in 0..<n {
    let token = tokens[i]
    let level_i = levels[i]
    let cm = content_models[i]

    // --- Configure phase ---

    // descendant_mixed (track state for potential use)
    match token {
      XmlToken::StartElement(_, _) =>
        if (cm == 2 || cm == 3) && desc_mixed_level is None {
          desc_mixed_level = Some(level_i)
        }
      XmlToken::EndElement(_) =>
        if desc_mixed_level is Some(v) && v == level_i {
          desc_mixed_level = None
        }
      _ => ()
    }

    // preserve
    let preserve_val = match token {
      XmlToken::StartElement(name, _) =>
        if preserve_level is Some(_) {
          2
        } else if str_contains(options.preserve, name) {
          preserve_level = Some(level_i)
          1
        } else {
          0
        }
      XmlToken::EndElement(name) =>
        if str_contains(options.preserve, name) &&
          level_i == preserve_level.unwrap_or(-1) {
          preserve_level = None
          1
        } else if preserve_level is None {
          0
        } else {
          2
        }
      _ => if preserve_level is Some(_) { 2 } else { 0 }
    }

    // cdata_section tracking
    let cdata_before = cdata_section
    match token {
      XmlToken::StartCdataSection => cdata_section = true
      XmlToken::EndCdataSection => cdata_section = false
      _ => ()
    }

    // indent determination
    let indent_val = if options.inline {
      // token_indent_inline: the original implementation scanned backward for
      // the nearest previous start element, which is O(n) per token and made
      // flat documents quadratic. The scan accepts the nearest start element
      // with a level below `level_i` (and, for end tags, one at the same
      // level), so it is equivalent to a max-index lookup over
      // `last_start[0..bound]`, done here in O(depth).
      let bound = match token {
        XmlToken::EndElement(_) => level_i
        _ => level_i - 1
      }
      let mut best = -1
      let mut l = 0
      while l <= bound && l <= max_level {
        let c = last_start[l]
        if c > best {
          best = c
        }
        l = l + 1
      }
      if best < 0 {
        true
      } else {
        content_models[best] == 1
      }
    } else {
      match token {
        XmlToken::StartElement(_, _) =>
          if cm == 2 || cm == 3 {
            if indent_level is None {
              indent_level = Some(level_i)
            }
            true
          } else if indent_level is Some(_) {
            false
          } else {
            true
          }
        XmlToken::EndElement(_) =>
          if indent_level is Some(v) && v == level_i {
            indent_level = None
            false
          } else if indent_level is None {
            true
          } else {
            false
          }
        _ => indent_level is None
      }
    }

    // --- Render phase ---

    match token {
      XmlToken::XmlDecl(version, encoding, standalone) => {
        let mut s = "<?xml version=\"" + version + "\""
        let enc = match encoding {
          Some(e) => e
          None => "UTF-8"
        }
        s = s + " encoding=\"" + enc + "\""
        match standalone {
          Some(true) => s = s + " standalone=\"yes\""
          _ => ()
        }
        s = s + "?>"
        out.push(s)
        out.push("\n")
      }
      XmlToken::StartElement(name, attrs) => {
        // Record after the indent lookup above so the element does not match
        // itself (the original backward scan started at i - 1).
        last_start[level_i] = i
        let mut s = ""
        if preserve_val != 2 && indent_val && level_i > 0 {
          s = s + indent_prefix(level_i, options)
        }
        s = s + "<" + name
        s = s + render_attrs(attrs, options)
        // Check if next token is matching EndElement
        let next_end = if i + 1 < n {
          match tokens[i + 1] {
            XmlToken::EndElement(nxt_name) =>
              nxt_name == name && level_i == levels[i + 1]
            _ => false
          }
        } else {
          false
        }
        if (options.compress || options.selfclose) && next_end {
          s = s + (if options.selfclose_space { " />" } else { "/>" })
        } else {
          s = s + ">"
        }
        out.push(s)
      }
      XmlToken::EndElement(name) => {
        // Don't close empty nodes on compression/selfclose
        let prev_is_start = if i > 0 {
          match tokens[i - 1] {
            XmlToken::StartElement(_, _) => true
            _ => false
          }
        } else {
          false
        }
        if (options.compress || options.selfclose) && prev_is_start {
          // Skip - already self-closed
        } else {
          let mut s = ""
          if preserve_val == 0 && indent_val && !prev_is_start {
            s = s + indent_prefix(level_i, options)
          }
          s = s + "</" + name + ">"
          out.push(s)
        }
      }
      XmlToken::CharacterData(text) => {
        let preserve_i = preserve_val == 2
        if !preserve_i && !cdata_before {
          if is_empty_str(text) {
            if options.blanks && !options.compress && text.contains("\n") {
              out.push("\n")
            }
          } else if options.correct {
            let mut s = text
            s = s.replace_all(old="\r\n", new="\n")
            s = s.replace_all(old="\r", new=" ")
            s = s.replace_all(old="\n", new=" ")
            s = s.replace_all(old="\t", new=" ")
            while s.contains("  ") {
              s = s.replace_all(old="  ", new=" ")
            }
            // delete leading whitespace if adjacent to StartElement
            let prev_is_start = if i > 0 {
              match tokens[i - 1] {
                XmlToken::StartElement(_, _) => true
                _ => false
              }
            } else {
              false
            }
            // Check if all tokens between prev StartElement and this are whitespace
            let mut can_delete_leading = prev_is_start
            if !can_delete_leading && i > 0 {
              // Check if previous tokens are all whitespace CharacterData
              let mut j = i - 1
              let mut all_ws = true
              while j >= 0 {
                match tokens[j] {
                  XmlToken::StartElement(_, _) => break
                  XmlToken::CharacterData(t) =>
                    if !is_empty_str(t) {
                      all_ws = false
                      break
                    }
                  _ => {
                    all_ws = false
                    break
                  }
                }
                j = j - 1
              }
              if all_ws && j >= 0 {
                can_delete_leading = true
              }
            }
            if can_delete_leading && s.has_prefix(" ") {
              s = s.unsafe_substring(start=1, end=s.length())
            }
            // delete trailing whitespace if adjacent to EndElement
            let next_is_end = if i + 1 < n {
              match tokens[i + 1] {
                XmlToken::EndElement(_) => true
                _ => false
              }
            } else {
              false
            }
            let mut can_delete_trailing = next_is_end
            if !can_delete_trailing && i + 1 < n {
              let mut j = i + 1
              let mut all_ws = true
              while j < n {
                match tokens[j] {
                  XmlToken::EndElement(_) => break
                  XmlToken::CharacterData(t) =>
                    if !is_empty_str(t) {
                      all_ws = false
                      break
                    }
                  _ => {
                    all_ws = false
                    break
                  }
                }
                j = j + 1
              }
              if all_ws && j < n {
                can_delete_trailing = true
              }
            }
            if can_delete_trailing && s.has_suffix(" ") && s.length() > 0 {
              s = s.unsafe_substring(start=0, end=s.length() - 1)
            }
            out.push(s)
          } else {
            out.push(text)
          }
        } else {
          out.push(text)
        }
      }
      XmlToken::Comment(text) => {
        let mut s = ""
        if preserve_val == 0 || preserve_val == 1 {
          if indent_val && level_i > 0 {
            s = s + indent_prefix(level_i, options)
          }
        }
        let cleaned = trim_str(text).replace_all(old="\r\n", new="\n")
        s = s + "<!--" + cleaned + "-->"
        out.push(s)
      }
      XmlToken::ProcessingInstruction(target, data) => {
        let mut s = ""
        if preserve_val == 0 || preserve_val == 1 {
          if indent_val && level_i > 0 {
            s = s + indent_prefix(level_i, options)
          }
        }
        s = s + "<?" + target + " " + data + "?>"
        out.push(s)
      }
      XmlToken::StartCdataSection => out.push("<![CDATA[")
      XmlToken::EndCdataSection => out.push("]]>")
      XmlToken::Declaration(raw) => out.push(raw)
    }
  }

  let result = out.join("")
  if options.eof_newline && !result.has_suffix("\n") {
    result + "\n"
  } else {
    result
  }
}

///|
pub fn format_default(xml : String) -> String {
  format(xml, default_options())
}
