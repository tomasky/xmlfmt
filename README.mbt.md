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

```moonbit
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

## License

Apache-2.0
