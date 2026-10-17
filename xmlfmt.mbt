///|
/// XML Formatter — MoonBit port of python xmlformatter

// ===== Token Types =====

///|
priv enum XmlToken {
  XmlDecl(String, Option[String], Option[Bool]) // version, encoding, standalone
  StartElement(String, Array[(String, String)]) // name, attrs
  EndElement(String) // name
  CharacterData(String) // text
  Comment(String) // text
  ProcessingInstruction(String, String) // target, data
  StartCdataSection
  EndCdataSection
  StartDoctypeDecl(String, Option[String], Option[String], Bool) // name, system_id, public_id, inline
  EndDoctypeDecl
}

// ===== Options =====

///|
pub(all) struct XmlOptions {
  indent : Int
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
fn indent_prefix(level : Int, options : XmlOptions) -> String {
  if options.compress || options.indent == 0 {
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
        let mut target = ""
        while i < n && chars[i] != ' ' && chars[i] != '?' && chars[i] != '>' {
          target = target + chars[i].to_string()
          i = i + 1
        }
        // Skip space
        while i < n && chars[i] == ' ' {
          i = i + 1
        }
        let mut data = ""
        while i < n && chars[i] != '?' && chars[i] != '>' {
          data = data + chars[i].to_string()
          i = i + 1
        }
        if i < n && chars[i] == '?' {
          i = i + 1
        }
        if i < n && chars[i] == '>' {
          i = i + 1
        }
        if target == "xml" {
          let attrs = parse_attrs(data)
          let version = get_attr(attrs, "version").unwrap_or("1.0")
          let encoding = get_attr(attrs, "encoding")
          let standalone = match get_attr(attrs, "standalone") {
            Some(v) => Some(v == "yes")
            None => None
          }
          tokens.push(XmlToken::XmlDecl(version, encoding, standalone))
        } else {
          tokens.push(
            XmlToken::ProcessingInstruction(target, trim_str(data)),
          )
        }
      } else if i + 2 < n && chars[i + 1] == '!' && chars[i + 2] == '-' {
        // Comment
        i = i + 4
        let mut text = ""
        while i + 2 < n &&
          !(chars[i] == '-' && chars[i + 1] == '-' && chars[i + 2] == '>') {
          text = text + chars[i].to_string()
          i = i + 1
        }
        if i + 2 < n {
          i = i + 3
        }
        tokens.push(XmlToken::Comment(text))
      } else if i + 8 < n && chars[i + 1] == '!' {
        // Check for CDATA
        let is_cdata = chars[i + 2] == '[' &&
          chars[i + 3] == 'C' &&
          chars[i + 4] == 'D' &&
          chars[i + 5] == 'A' &&
          chars[i + 6] == 'T' &&
          chars[i + 7] == 'A' &&
          chars[i + 8] == '['
        if is_cdata {
          i = i + 9
          let mut text = ""
          while i + 2 < n &&
            !(chars[i] == ']' && chars[i + 1] == ']' && chars[i + 2] == '>') {
            text = text + chars[i].to_string()
            i = i + 1
          }
          if i + 2 < n {
            i = i + 3
          }
          tokens.push(XmlToken::StartCdataSection)
          tokens.push(XmlToken::CharacterData(text))
          tokens.push(XmlToken::EndCdataSection)
        } else {
          // DOCTYPE or other declaration
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
          if i < n && chars[i] == '>' {
            i = i + 1
          }
          let content = input.unsafe_substring(start=start + 2, end=i - 2).trim().to_owned()
          let parts = collect_iter(content.split(" "))
          let mut name = ""
          let mut system_id = None
          let mut public_id = None
          let mut inline = false
          if parts.length() > 0 {
            name = parts[0]
          }
          let mut j = 1
          while j < parts.length() {
            if parts[j] == "PUBLIC" {
              if j + 1 < parts.length() {
                public_id = Some(trim_quotes(parts[j + 1]))
              }
              if j + 2 < parts.length() {
                system_id = Some(trim_quotes(parts[j + 2]))
              }
            } else if parts[j] == "SYSTEM" {
              if j + 1 < parts.length() {
                system_id = Some(trim_quotes(parts[j + 1]))
              }
            } else if parts[j] == "[" {
              inline = true
            }
            j = j + 1
          }
          tokens.push(XmlToken::StartDoctypeDecl(name, system_id, public_id, inline))
          tokens.push(XmlToken::EndDoctypeDecl)
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
        let mut name = ""
        while i < n && chars[i] != '>' && chars[i] != ' ' && chars[i] != '/' {
          name = name + chars[i].to_string()
          i = i + 1
        }
        if is_end {
          if i < n && chars[i] == '>' {
            i = i + 1
          }
          tokens.push(XmlToken::EndElement(name))
        } else {
          // Parse attributes
          let attrs = []
          while i < n && chars[i] != '>' && chars[i] != '/' {
            if chars[i] == ' ' {
              i = i + 1
              continue
            }
            let mut aname = ""
            while i < n && chars[i] != '=' && chars[i] != '>' &&
              chars[i] != '/' && chars[i] != ' ' {
              aname = aname + chars[i].to_string()
              i = i + 1
            }
            if i < n && chars[i] == '=' {
              i = i + 1
              if i < n && (chars[i] == '"' || chars[i] == '\'') {
                let quote = chars[i]
                i = i + 1
                let mut aval = ""
                while i < n && chars[i] != quote {
                  aval = aval + chars[i].to_string()
                  i = i + 1
                }
                if i < n && chars[i] == quote {
                  i = i + 1
                }
                attrs.push((aname, aval))
              } else {
                attrs.push((aname, ""))
              }
            } else if !aname.is_empty() {
              attrs.push((aname, ""))
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
            tokens.push(XmlToken::StartElement(name, attrs))
            tokens.push(XmlToken::EndElement(name))
          } else {
            tokens.push(XmlToken::StartElement(name, attrs))
          }
        }
      }
    } else {
      // Character data
      let mut text = ""
      while i < n && chars[i] != '<' {
        text = text + chars[i].to_string()
        i = i + 1
      }
      tokens.push(XmlToken::CharacterData(text))
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
fn get_attr(attrs : Array[(String, String)], key : String) -> Option[String] {
  for (k, v) in attrs {
    if k == key {
      return Some(v)
    }
  }
  None
}

// ===== Level Computation =====

///|
fn compute_levels(tokens : Array[XmlToken]) -> Array[Int] {
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
        lvl = lvl - 1
        levels[i] = lvl
      }
      _ => {
        levels[i] = lvl
      }
    }
  }
  levels
}

// ===== Content Model Computation =====

///|
fn compute_content_models(tokens : Array[XmlToken], levels : Array[Int]) -> Array[Int] {
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
              XmlToken::StartElement(_, _) => {
                eflag = 1
              }
              XmlToken::CharacterData(text) => {
                if !is_empty_str(text) {
                  tflag = 2
                }
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
fn render_attrs(attrs : Array[(String, String)], options : XmlOptions) -> String {
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

  let out = []

  // State
  let mut preserve_level : Option[Int] = None
  let mut desc_mixed_level : Option[Int] = None
  let mut indent_level : Option[Int] = None
  let mut cdata_section = false

  for i in 0..<n {
    let token = tokens[i]
    let level_i = levels[i]
    let cm = content_models[i]

    // --- Configure phase ---

    // descendant_mixed (track state for potential use)
    match token {
      XmlToken::StartElement(_, _) => {
        if (cm == 2 || cm == 3) && desc_mixed_level is None {
          desc_mixed_level = Some(level_i)
        }
      }
      XmlToken::EndElement(_) => {
        if desc_mixed_level is Some(v) && v == level_i {
          desc_mixed_level = None
        }
      }
      _ => ()
    }

    // preserve
    let preserve_val = match token {
      XmlToken::StartElement(name, _) => {
        if preserve_level is Some(_) {
          2
        } else if str_contains(options.preserve, name) {
          preserve_level = Some(level_i)
          1
        } else {
          0
        }
      }
      XmlToken::EndElement(name) => {
        if str_contains(options.preserve, name) &&
          level_i == preserve_level.unwrap_or(-1) {
          preserve_level = None
          1
        } else if preserve_level is None {
          0
        } else {
          2
        }
      }
      _ => {
        if preserve_level is Some(_) {
          2
        } else {
          0
        }
      }
    }

    // cdata_section tracking
    let cdata_before = cdata_section
    match token {
      XmlToken::StartCdataSection => {
        cdata_section = true
      }
      XmlToken::EndCdataSection => {
        cdata_section = false
      }
      _ => ()
    }

    // indent determination
    let indent_val = if options.inline {
      // token_indent_inline: look backward
      let mut result = true
      let mut found = false
      let mut j = i - 1
      while j >= 0 && !found {
        match tokens[j] {
          XmlToken::StartElement(_, _) => {
            if levels[j] < level_i {
              if content_models[j] == 1 {
                result = true
              } else {
                result = false
              }
              found = true
            } else if levels[j] == level_i {
              match token {
                XmlToken::EndElement(_) => {
                  if content_models[j] == 1 {
                    result = true
                  } else {
                    result = false
                  }
                  found = true
                }
                _ => ()
              }
            }
          }
          _ => ()
        }
        j = j - 1
      }
      result
    } else {
      match token {
        XmlToken::StartElement(_, _) => {
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
        }
        XmlToken::EndElement(_) => {
          if indent_level is Some(v) && v == level_i {
            indent_level = None
            false
          } else if indent_level is None {
            true
          } else {
            false
          }
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
          Some(true) => {
            s = s + " standalone=\"yes\""
          }
          _ => ()
        }
        s = s + "?>"
        out.push(s)
        out.push("\n")
      }
      XmlToken::StartElement(name, attrs) => {
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
          } else {
            if options.correct {
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
                    XmlToken::StartElement(_, _) => { break }
                    XmlToken::CharacterData(t) => {
                      if !is_empty_str(t) { all_ws = false; break }
                    }
                    _ => { all_ws = false; break }
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
                    XmlToken::EndElement(_) => { break }
                    XmlToken::CharacterData(t) => {
                      if !is_empty_str(t) { all_ws = false; break }
                    }
                    _ => { all_ws = false; break }
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
      XmlToken::StartCdataSection => {
        out.push("<![CDATA[")
      }
      XmlToken::EndCdataSection => {
        out.push("]]>")
      }
      XmlToken::StartDoctypeDecl(name, system_id, public_id, inline) => {
        let mut s = "<!DOCTYPE " + name
        match public_id {
          Some(pid) => {
            match system_id {
              Some(sid) => {
                s = s + " PUBLIC \"" + pid + "\" \"" + sid + "\""
              }
              None => {
                s = s + " PUBLIC \"" + pid + "\""
              }
            }
          }
          None => {
            match system_id {
              Some(sid) => {
                s = s + " SYSTEM \"" + sid + "\""
              }
              None => ()
            }
          }
        }
        if inline {
          s = s + " ["
        }
        out.push(s)
      }
      XmlToken::EndDoctypeDecl => {
        out.push(">")
      }
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
