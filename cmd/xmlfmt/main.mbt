///|
fn main {
  let args = @env.args()
  // Parse arguments
  let mut indent = 2
  let mut indent_char = " "
  let mut outfile : String? = None
  let mut overwrite = false
  let mut preserve : Array[String] = []
  let mut blanks = false
  let mut compress = false
  let mut selfclose = false
  let mut selfclose_space = false
  let mut infile : String? = None
  let mut inline = true
  let mut correct = true
  let mut eof_newline = false
  let mut preserve_attributes = false
  let mut encode_attributes = false
  let files : Array[String] = []

  let mut i = 1 // skip program name
  let mut had_error = false
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      print_usage()
      return
    } else if arg == "--version" || arg == "-v" || arg == "-V" {
      println("xmlfmt \{@lib.VERSION}")
      return
    } else if arg == "--indent" || arg == "-i" {
      i = i + 1
      if i < args.length() {
        indent = parse_int(args[i])
      } else {
        usage_error("option \{arg} requires a value")
      }
    } else if arg.has_prefix("--indent=") {
      indent = parse_int(arg.unsafe_substring(start=9, end=arg.length()))
    } else if arg == "--indent-char" || arg == "-I" {
      i = i + 1
      if i < args.length() {
        indent_char = args[i]
      } else {
        usage_error("option \{arg} requires a value")
      }
    } else if arg == "--output" || arg == "--outfile" || arg == "-o" {
      i = i + 1
      if i < args.length() {
        outfile = Some(args[i])
      } else {
        usage_error("option \{arg} requires a value")
      }
    } else if arg == "--infile" || arg == "-f" {
      i = i + 1
      if i < args.length() {
        infile = Some(args[i])
      } else {
        usage_error("option \{arg} requires a value")
      }
    } else if arg == "--overwrite" || arg == "-w" {
      overwrite = true
    } else if arg == "--preserve" || arg == "-p" {
      i = i + 1
      if i < args.length() {
        preserve = args[i]
          .replace_all(old=",", new=" ")
          .split(" ")
          .map(fn(s) { s.trim().to_owned() })
          .filter(fn(s) { !s.is_empty() })
          .collect()
      } else {
        usage_error("option \{arg} requires a value")
      }
    } else if arg == "--blanks" || arg == "-b" {
      blanks = true
    } else if arg == "--compress" || arg == "-c" {
      compress = true
    } else if arg == "--selfclose" || arg == "-s" {
      selfclose = true
    } else if arg == "--selfclose-space" || arg == "-S" {
      selfclose_space = true
    } else if arg == "--disable-inlineformatting" || arg == "-l" {
      inline = false
    } else if arg == "--disable-correction" || arg == "-C" {
      correct = false
    } else if arg == "--eof-newline" || arg == "-n" {
      eof_newline = true
    } else if arg == "--preserve-attributes" || arg == "-a" {
      preserve_attributes = true
    } else if arg == "--encode-attributes" || arg == "-E" {
      encode_attributes = true
    } else if arg == "-" {
      files.push("-")
    } else if arg.has_prefix("--") || arg.has_prefix("-") {
      usage_error("unknown option \{arg}")
    } else {
      files.push(arg)
    }
    i = i + 1
  }

  let options = @lib.XmlOptions::{
    indent,
    indent_char,
    compress,
    selfclose,
    selfclose_space,
    inline,
    correct,
    blanks,
    eof_newline,
    preserve,
    preserve_attributes,
    encode_attributes,
  }

  // Determine input files
  if infile is Some(f) {
    files.push(f)
  }

  if files.is_empty() {
    files.push("-")
  }

  for file in files {
    let content : String? = if file == "-" {
      Some(@lib.decode_input(read_stdin_bytes()))
    } else {
      Some(@lib.decode_input(@fs.read_file_to_bytes(file))) catch {
        _ => {
          eprintln("xmlfmt: cannot read \{file}")
          had_error = true
          None
        }
      }
    }
    // A file that could not be read contributes no output at all: printing an
    // empty document would look like a successful, empty result.
    guard content is Some(content) else { continue }
    let result = @lib.format(content, options)
    if overwrite && file != "-" {
      @fs.write_string_to_file(file, result) catch {
        _ => {
          eprintln("xmlfmt: cannot write \{file}")
          had_error = true
        }
      }
    } else if outfile is Some(out) {
      @fs.write_string_to_file(out, result) catch {
        _ => {
          eprintln("xmlfmt: cannot write \{out}")
          had_error = true
        }
      }
    } else {
      println(result)
    }
  }

  if had_error {
    @env.exit(1)
  }
}

///|
/// Print an argument error plus the usage summary to stderr and exit with
/// status 2, matching the `xmlformat` CLI this tool is ported from.
fn usage_error(message : String) -> Unit {
  eprintln("xmlfmt: \{message}")
  eprintln("Try 'xmlfmt --help' for more information.")
  @env.exit(2)
}

///|
/// Write the usage summary to stdout: `--help` is a normal, successful
/// request, so its output must be capturable and pipeable like any other
/// program output. Errors go through `usage_error` instead.
fn print_usage() -> Unit {
  println("Usage: xmlfmt [options] [file...]")
  println("")
  println("Options:")
  println(
    "  -i, --indent <num>            Number of indent chars per level (default: 2)",
  )
  println(
    "  -I, --indent-char <char>      Indentation character (default: space)",
  )
  println("  -c, --compress                Minify output (remove whitespace)")
  println(
    "  -s, --selfclose               Use self-closing tags for empty elements",
  )
  println(
    "  -S, --selfclose-space         Add space before /> in self-closing tags",
  )
  println("  -l, --disable-inlineformatting")
  println("                                Disable inline formatting")
  println("  -C, --disable-correction      Disable whitespace correction")
  println("  -b, --blanks                  Preserve blank lines")
  println("  -n, --eof-newline             Add newline at end of file")
  println(
    "  -p, --preserve <elems>        Comma-separated elements to preserve whitespace",
  )
  println("  -a, --preserve-attributes     Preserve attribute order")
  println("  -E, --encode-attributes       Encode > and ' in attribute values")
  println("  -o, --output/--outfile <file> Write output to file")
  println("  -f, --infile <file>           Input file")
  println("  -w, --overwrite               Overwrite input file")
  println("  -h, --help                    Show this help")
  println("  -v, --version                 Show the version")
  println("")
  println("Examples:")
  println("  xmlfmt input.xml                    Pretty-print to stdout")
  println("  xmlfmt -c input.xml                 Compress/minify")
  println("  xmlfmt -i 4 input.xml               4-space indentation")
  println("  xmlfmt -s -S input.xml              Self-closing tags with space")
  println("  xmlfmt -o out.xml input.xml         Write to file")
  println("  xmlfmt -w input.xml                 Overwrite in place")
  println("  cat input.xml | xmlfmt -            Read from stdin")
}

///|
fn parse_int(s : String) -> Int32 {
  let mut result = 0
  let mut neg = false
  let mut i = 0
  let chars = s.to_array()
  if chars.length() > 0 && chars[0] == '-' {
    neg = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
    i = i + 1
  }
  if neg {
    -result
  } else {
    result
  }
}

///|
#borrow(buf)
extern "C" fn read(fd : Int32, buf : Bytes, count : Int32) -> Int32 = "read"

///|
fn read_stdin_bytes() -> Bytes {
  let chunks : Array[Byte] = []
  let buf_size = 65536
  while true {
    let buf = Bytes::make(buf_size, 0)
    let n = read(0, buf, buf_size)
    if n <= 0 {
      break
    }
    let mut i = 0
    while i < n {
      chunks.push(buf[i])
      i = i + 1
    }
  }
  Bytes::from_array(chunks)
}
