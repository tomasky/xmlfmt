# xmlfmt

An XML formatter written in [MoonBit](https://www.moonbitlang.com/), ported from
[python xmlformatter](https://pypi.org/project/xmlformatter/) (v0.2.9).

## Features

- Pretty-print XML with configurable indentation
- Compress/minify XML output
- Self-closing tags
- Whitespace correction and normalization
- Preserve whitespace in specified elements
- Preserve or sort attribute order
- Encode attribute values
- CDATA, comments, processing instructions, DOCTYPE support
- CLI tool with file/stdin support

## Installation

### As a library (MoonBit)

```bash
moon add kupas/xmlfmt
```

### As a CLI (from source)

```bash
moon install kupas/xmlfmt/cmd/xmlfmt
```

This builds from source using the MoonBit toolchain and installs the `xmlfmt`
binary to `~/.moon/bin`.

### As a CLI (prebuilt binary)

```bash
curl -LsSf https://raw.githubusercontent.com/tomasky/xmlfmt/main/install.sh | bash
```

### npm

```bash
npm install -g @tomasko/xmlfmt
# or
pnpm install -g @tomasko/xmlfmt
```

## Usage

### Library

```moonbit nocheck
import "kupas/xmlfmt"

fn main {
  let xml = "<root><child>text</child></root>"
  let result = @xmlfmt.format(xml, @xmlfmt.default_options())
  println(result)
}
```

### CLI

```bash
moon install kupas/xmlfmt/cmd/xmlfmt
xmlfmt input.xml
xmlfmt --compress input.xml
xmlfmt --indent 4 input.xml
```

## Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--indent <num>` | `-i` | 2 | Number of indent characters per level |
| `--indent-char <char>` | `-I` | space | Indentation character |
| `--compress` | `-c` | false | Minify output: remove all unnecessary whitespace, single line |
| `--selfclose` | `-s` | false | Use self-closing tags for empty elements (`<empty/>`) |
| `--selfclose-space` | `-S` | false | Add space before `/>` (`<empty />`) |
| `--disable-inlineformatting` | `-l` | false | Disable inline formatting (see below) |
| `--disable-correction` | `-C` | false | Disable whitespace correction |
| `--blanks` | `-b` | false | Preserve blank lines (collapse multiple into one) |
| `--eof-newline` | `-n` | false | Add newline at end of file |
| `--preserve <elems>` | `-p` | none | Comma-separated elements to preserve whitespace in |
| `--preserve-attributes` | `-a` | false | Preserve original attribute order (default: sort) |
| `--encode-attributes` | `-E` | false | Encode `>` and `'` in attribute values |
| `--output <file>` | `-o` | none | Write output to file |
| `--infile <file>` | `-f` | none | Input file |
| `--overwrite` | `-w` | false | Overwrite input file in place |

### Pretty Output (default)

By default, xmlfmt produces pretty-printed output with indentation:

```xml
<root>
  <child>text</child>
  <nested>
    <deep>value</deep>
  </nested>
</root>
```

### Inline Formatting

By default, elements containing only text stay on a single line: `<a>abc</a>`.
Elements containing child elements are expanded. Use `--disable-inlineformatting`
(`-l`) to expand text-only elements too:

```xml
<!-- default (inline) -->
<root>
  <name>John</name>
  <items>
    <item>1</item>
    <item>2</item>
  </items>
</root>

<!-- with -l (disabled inline) -->
<root>
  <name>
    John
  </name>
  <items>
    <item>
      1
    </item>
  </items>
</root>
```

### Compress Mode

`--compress` (`-c`) removes all unnecessary whitespace and produces single-line
output: `<root><child>text</child></root>`. Useful for minification.

### Self-Closing Tags

`--selfclose` (`-s`) converts empty elements to self-closing form:

```xml
<!-- input:  <root><empty></empty></root> -->
<!-- output: <root><empty/></root> -->
```

Add `--selfclose-space` (`-S`) for a space before `/>`: `<empty />`.

### Whitespace Correction

By default, xmlfmt normalizes whitespace in text nodes: collapses multiple
spaces, converts tabs/newlines to spaces, and trims leading/trailing spaces
adjacent to tags. Use `--disable-correction` (`-C`) to preserve original
whitespace.

### Preserve Whitespace

Use `--preserve` (`-p`) to keep whitespace untouched in specific elements
and their descendants (e.g., `<pre>`, `<code>`, `<script>`):

```bash
xmlfmt -p "pre,code,script" input.xml
```

### Attribute Handling

- By default, attributes are sorted alphabetically
- `--preserve-attributes` (`-a`): keep original order
- `--encode-attributes` (`-E`): also encode `>` and `'` (default only encodes `&`, `<`, `"`)

### Blank Lines

`--blanks` (`-b`): preserve blank lines (multiple blank lines collapse to one).

### EOF Newline

`--eof-newline` (`-n`): ensure file ends with a newline character.

## License

Apache-2.0
