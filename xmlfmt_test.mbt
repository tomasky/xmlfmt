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
