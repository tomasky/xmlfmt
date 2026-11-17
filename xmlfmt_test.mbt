// Blackbox tests run against the package's public API. Use `@xmlfmt` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "format_default indents nested elements" {
  let out = @xmlfmt.format_default("<root><a>1</a><b>2</b></root>")
  inspect(
    out,
    content=(
      #|<root>
      #|  <a>1</a>
      #|  <b>2</b>
      #|</root>
    ),
  )
}

///|
test "format_default keeps already-flat input stable" {
  assert_eq(@xmlfmt.format_default("<a>hi</a>"), "<a>hi</a>")
}

///|
test "compress produces no indentation" {
  let opts = @xmlfmt.default_options()
  let opts = { ..opts, compress: true, }
  assert_eq(
    @xmlfmt.format("<root><a>1</a></root>", opts),
    "<root><a>1</a></root>",
  )
}

///|
test "indent width is honoured" {
  let opts = @xmlfmt.default_options()
  let opts = { ..opts, indent: 4, }
  inspect(
    @xmlfmt.format("<root><a>1</a></root>", opts),
    content=(
      #|<root>
      #|    <a>1</a>
      #|</root>
    ),
  )
}

///|
test "stray closing tags do not abort" {
  // Regression: an unmatched end tag drove the level negative, and the
  // negative indent width reached String::make, aborting the process.
  inspect(
    @xmlfmt.format_default("</r>"),
    content=(
      #|
      #|</r>
    ),
  )
  inspect(
    @xmlfmt.format_default("</a></b>"),
    content=(
      #|
      #|</a>
      #|</b>
    ),
  )
  inspect(
    @xmlfmt.format_default("</>"),
    content=(
      #|
      #|</>
    ),
  )
  inspect(
    @xmlfmt.format_default("<r></b>"),
    content=(
      #|<r></b>
    ),
  )
  inspect(
    @xmlfmt.format_default("</r><r><a>1</a></r>"),
    content=(
      #|
      #|</r><r>
      #|  <a>1</a>
      #|</r>
    ),
  )
}

///|
test "unterminated input does not abort" {
  for input in ["<", "<r", "<r a=\"1", "<!-- x", "<?pi", "<![CDATA[x"] {
    // Only requirement: it returns without aborting.
    let out = @xmlfmt.format_default(input)
    assert_true(out.length() >= 0)
  }
}

///|
test "declarations are preserved verbatim" {
  // Regression: every `<!...>` used to be rewritten as a mangled DOCTYPE
  // (`<!DOCTYPE DOCTYPE SYSTEM ""u.dtd">`) and internal subsets were dropped.
  inspect(
    @xmlfmt.format_default("<!DOCTYPE r SYSTEM \"u.dtd\"><r/>"),
    content=(
      #|<!DOCTYPE r SYSTEM "u.dtd"><r></r>
    ),
  )
  inspect(
    @xmlfmt.format_default("<!ELEMENT r ANY>"),
    content="<!ELEMENT r ANY>",
  )
  inspect(
    @xmlfmt.format_default("<!DOCTYPE r [<!ELEMENT r ANY>]><r/>"),
    content="<!DOCTYPE r [<!ELEMENT r ANY>]><r></r>",
  )
  // Lowercase `<!doctype ...>` is not valid XML but must not be destroyed.
  inspect(
    @xmlfmt.format_default("<!doctype r><r/>"),
    content="<!doctype r><r></r>",
  )
}

///|
test "declaration formatting is idempotent" {
  let src = "<!DOCTYPE r [ <!ELEMENT r ANY> ]><r>a</r>"
  let once = @xmlfmt.format_default(src)
  assert_eq(@xmlfmt.format_default(once), once)
}

///|
test "unterminated declaration does not abort" {
  // Only requirement: it returns without aborting.
  let out = @xmlfmt.format_default("<!DOCTYPE")
  assert_true(out.length() >= 0)
}

///|
test "format_default keeps attributes of multi-line start tags" {
  // Regression: a start tag whose attributes were spread over several lines
  // used to come back with junk attributes (`=""`) and no indentation.
  let src = "<root\n   a=\"1\"\n   b=\"2\"\n>\n  <c>x</c>\n</root>"
  inspect(
    @xmlfmt.format_default(src),
    content=(
      #|<root a="1" b="2">
      #|  <c>x</c>
      #|</root>
    ),
  )
}

///|
test "format_default normalises CRLF and tabs inside tags" {
  let src = "<root\r\n\ta=\"1\"\r\n\tb=\"2\"\r\n><c/></root>"
  inspect(
    @xmlfmt.format_default(src),
    content=(
      #|<root a="1" b="2">
      #|  <c></c>
      #|</root>
    ),
  )
}

///|
test "multi-line start tag formatting is idempotent" {
  let once = @xmlfmt.format_default("<r\n  a=\"1\"\n>\n  <c/>\n</r>")
  assert_eq(@xmlfmt.format_default(once), once)
}

///|
test "attribute values keep inner spaces and equals signs" {
  let out = @xmlfmt.format_default("<r a=\"x y\" b=\"k=v\"/>")
  assert_eq(out, "<r a=\"x y\" b=\"k=v\"></r>")
}

///|
test "decode_input reads UTF-8, with or without a BOM" {
  assert_eq(@xmlfmt.decode_input(b"<a>b</a>"), "<a>b</a>")
  assert_eq(@xmlfmt.decode_input(b"\xef\xbb\xbf<a>b</a>"), "<a>b</a>")
  // Multi-byte UTF-8 survives untouched
  // "汉字" as UTF-8 bytes: the same bytes must come back as characters.
  assert_eq(@xmlfmt.decode_input(b"\xe6\xb1\x89\xe5\xad\x97"), "汉字")
}

///|
test "decode_input reads UTF-16 with a BOM" {
  // "<a>hi</a>" in UTF-16LE and UTF-16BE, each with its BOM.
  let le : Array[Byte] = [0xFF, 0xFE]
  let be : Array[Byte] = [0xFE, 0xFF]
  let text = "<a>hi</a>"
  for c in text.to_array() {
    let code = c.to_int()
    le.push(code.to_byte())
    le.push((code >> 8).to_byte())
    be.push((code >> 8).to_byte())
    be.push(code.to_byte())
  }
  assert_eq(@xmlfmt.decode_input(Bytes::from_array(le)), text)
  assert_eq(@xmlfmt.decode_input(Bytes::from_array(be)), text)
}

///|
test "decode_input recognises UTF-16 without a BOM" {
  // `<?xml` would otherwise be read as text full of NUL bytes.
  let le : Array[Byte] = [0x3C, 0x00, 0x3F, 0x00]
  let be : Array[Byte] = [0x00, 0x3C, 0x00, 0x3F]
  for c in "xml?>".to_array() {
    le.push(c.to_int().to_byte())
    le.push(0)
    be.push(0)
    be.push(c.to_int().to_byte())
  }
  assert_eq(@xmlfmt.decode_input(Bytes::from_array(le)), "<?xml?>")
  assert_eq(@xmlfmt.decode_input(Bytes::from_array(be)), "<?xml?>")
}

///|
test "decode_input falls back to Latin-1 for invalid UTF-8" {
  // ISO-8859-1 "café": the 0xE9 byte must not become U+FFFD.
  assert_eq(@xmlfmt.decode_input(b"caf\xe9"), "café")
}

///|
test "format_default handles a UTF-16 encoded document" {
  let le : Array[Byte] = [0xFF, 0xFE]
  for c in "<r><a>x</a></r>".to_array() {
    le.push(c.to_int().to_byte())
    le.push(0)
  }
  let text = @xmlfmt.decode_input(Bytes::from_array(le))
  assert_eq(@xmlfmt.format_default(text), "<r>\n  <a>x</a>\n</r>")
}
