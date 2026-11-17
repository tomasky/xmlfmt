// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "is_empty_str accepts whitespace-only and empty strings" {
  assert_true(is_empty_str(""))
  assert_true(is_empty_str(" "))
  assert_true(is_empty_str(" \t\n\r "))
  assert_false(is_empty_str("x"))
  assert_false(is_empty_str(" x"))
}

///|
test "encode_attribute escapes entities" {
  // & and < are always encoded
  assert_eq(encode_attribute("a&b", false), "a&amp;b")
  assert_eq(encode_attribute("a<b", false), "a&lt;b")
  // > and ' only with the encode option
  assert_eq(encode_attribute("a>b'c", false), "a>b'c")
  assert_eq(encode_attribute("a>b'c", true), "a&gt;b&apos;c")
  // Quotes are always encoded
  assert_eq(encode_attribute("a\"b", false), "a&quot;b")
}

///|
test "indent_prefix scales with level and honours options" {
  let opts = default_options()
  // Level 0 still emits the leading newline; only the indent run is empty.
  assert_eq(indent_prefix(0, opts), "\n")
  assert_eq(indent_prefix(1, opts), "\n  ")
  assert_eq(indent_prefix(2, opts), "\n    ")
  // A negative level must never reach String::make (which aborts).
  assert_eq(indent_prefix(-1, opts), "")
  // Tab indentation
  let tabs = { ..opts, indent_char: "\t", indent: 1, }
  assert_eq(indent_prefix(3, tabs), "\n\t\t\t")
  // compress and indent=0 disable indentation entirely
  assert_eq(indent_prefix(5, { ..opts, compress: true, }), "")
  assert_eq(indent_prefix(5, { ..opts, indent: 0, }), "")
}

///|
test "parse_attrs reads space-separated key=value pairs" {
  assert_eq(parse_attrs("version=\"1.0\""), [("version", "1.0")])
  assert_eq(
    parse_attrs("version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\""),
    [("version", "1.0"), ("encoding", "UTF-8"), ("standalone", "yes")],
  )
  // Values without quotes parse; bare keys without '=' are dropped
  assert_eq(parse_attrs("a=b c"), [("a", "b")])
  assert_eq(parse_attrs(""), [])
  // Any whitespace separates attributes, so a declaration wrapped over
  // several lines still yields clean names and values.
  assert_eq(
    parse_attrs("version=\"1.0\"\n  encoding=\"UTF-8\"\tstandalone=\"yes\""),
    [("version", "1.0"), ("encoding", "UTF-8"), ("standalone", "yes")],
  )
  // Quoted values may contain whitespace and '='; whitespace around '=' is ok.
  assert_eq(parse_attrs("a = \"x y\" b=\"2\""), [("a", "x y"), ("b", "2")])
  assert_eq(parse_attrs("k=\"a=b\""), [("k", "a=b")])
  // Single-quoted values are handled too
  assert_eq(parse_attrs("k='v w'"), [("k", "v w")])
}

///|
test "get_attr finds the first match" {
  let attrs = [("a", "1"), ("b", "2"), ("a", "3")]
  assert_eq(get_attr(attrs, "a"), Some("1"))
  assert_eq(get_attr(attrs, "b"), Some("2"))
  assert_eq(get_attr(attrs, "missing"), None)
}

///|
test "compute_levels clamps stray end tags at zero" {
  // Regression: unbalanced end tags used to drive levels negative, which
  // eventually aborted the formatter inside String::make.
  assert_eq(compute_levels(parse_xml("</r>")), [0])
  assert_eq(compute_levels(parse_xml("</a></b>")), [0, 0])
  assert_eq(compute_levels(parse_xml("<r></b>")), [0, 0])
  assert_eq(
    compute_levels(parse_xml("</r><r><a>1</a></r>")),
    // tokens: End(r) Start(r) Start(a) "1" End(a) End(r)
    [0, 0, 1, 2, 1, 0],
  )
  // Balanced nesting still counts up and down; a self-closing tag yields a
  // start/end pair at the same level.
  assert_eq(compute_levels(parse_xml("<a><b><c/></b></a>")), [0, 1, 2, 2, 1, 0])
}

///|
test "compute_content_models classifies element-only vs mixed content" {
  let tokens = parse_xml("<r><a/></r>")
  let levels = compute_levels(tokens)
  // Root has an element child -> 1
  assert_eq(compute_content_models(tokens, levels)[0], 1)
  let tokens2 = parse_xml("<r>x<a/></r>")
  let levels2 = compute_levels(tokens2)
  // Root has both text and an element child -> 3
  assert_eq(compute_content_models(tokens2, levels2)[0], 3)
}

///|
test "parser keeps declarations verbatim" {
  // The declaration token must carry the exact source bytes, including
  // quoted identifiers and internal subsets.
  let src = "<!DOCTYPE r SYSTEM \"u.dtd\">"
  match parse_xml(src)[0] {
    XmlToken::Declaration(raw) => assert_eq(raw, src)
    _ => fail("expected a Declaration token")
  }
  let subset = "<!DOCTYPE r [<!ELEMENT r ANY>]>"
  match parse_xml(subset)[0] {
    XmlToken::Declaration(raw) => assert_eq(raw, subset)
    _ => fail("expected a Declaration token")
  }
}

///|
test "parser reports self-closing elements as a start/end pair" {
  let tokens = parse_xml("<a/>")
  assert_true(
    tokens[0] is XmlToken::StartElement(_, _) &&
    tokens[1] is XmlToken::EndElement(_),
  )
}

///|
test "parser keeps attributes of start tags wrapped over several lines" {
  // Regression: only ' ' separated attributes, so newlines and tabs inside a
  // start tag were swallowed into attribute names and emitted as junk
  // (`<root\n ="" a="1">`).
  let tokens = parse_xml("<root\n   a=\"1\"\n   b=\"2\"\n>\n  <c/>\n</root>")
  match tokens[0] {
    XmlToken::StartElement(name, attrs) => {
      assert_eq(name, "root")
      assert_eq(attrs, [("a", "1"), ("b", "2")])
    }
    _ => fail("expected a StartElement token")
  }
  // An end tag with whitespace before '>' keeps its clean name
  match parse_xml("</root\n>")[0] {
    XmlToken::EndElement(name) => assert_eq(name, "root")
    _ => fail("expected an EndElement token")
  }
}

///|
test "parser splits an XML declaration wrapped over several lines" {
  let tokens = parse_xml("<?xml\n version=\"1.0\"\n encoding=\"UTF-8\"?><a/>")
  match tokens[0] {
    XmlToken::XmlDecl(version, encoding, _) => {
      assert_eq(version, "1.0")
      assert_eq(encoding, Some("UTF-8"))
    }
    _ => fail("expected an XmlDecl token")
  }
}
