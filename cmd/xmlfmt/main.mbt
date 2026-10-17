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
  while i < args.length() {
    let arg = args[i]
    if arg == "--help" || arg == "-h" {
      print_usage()
      return
    } else if arg == "--indent" || arg == "-i" {
      i = i + 1
      if i < args.length() {
        indent = parse_int(args[i])
      }
    } else if arg.has_prefix("--indent=") {
      indent = parse_int(arg.unsafe_substring(start=9, end=arg.length()))
    } else if arg == "--indent-char" || arg == "-I" {
      i = i + 1
      if i < args.length() {
        indent_char = args[i]
      }
    } else if arg == "--output" || arg == "--outfile" || arg == "-o" {
      i = i + 1
      if i < args.length() {
        outfile = Some(args[i])
      }
    } else if arg == "--infile" || arg == "-f" {
      i = i + 1
      if i < args.length() {
        infile = Some(args[i])
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
      eprintln("Unknown option: " + arg)
    } else {
      files.push(arg)
    }
    i = i + 1
  }

  let options = @lib.XmlOptions::{
    indent: indent,
    indent_char: indent_char,
    compress: compress,
    selfclose: selfclose,
    selfclose_space: selfclose_space,
    inline: inline,
    correct: correct,
    blanks: blanks,
    eof_newline: eof_newline,
    preserve: preserve,
    preserve_attributes: preserve_attributes,
    encode_attributes: encode_attributes,
  }

  // Determine input files
  if infile is Some(f) {
    files.push(f)
  }

  if files.is_empty() {
    files.push("-")
  }

  for file in files {
    let content = if file == "-" {
      read_stdin()
    } else {
      @fs.read_file_to_string(file) catch {
        _ => {
          eprintln("Error reading file: " + file)
          ""
        }
      }
    }
    let result = @lib.format(content, options)
    if overwrite && file != "-" {
      @fs.write_string_to_file(file, result) catch {
        _ => eprintln("Error writing file: " + file)
      }
    } else if outfile is Some(out) {
      @fs.write_string_to_file(out, result) catch {
        _ => eprintln("Error writing file: " + out)
      }
    } else {
      println(result)
    }
  }
}

///|
fn print_usage() -> Unit {
  eprintln("Usage: xmlfmt [options] [file...]")
  eprintln("")
  eprintln("Options:")
  eprintln("  -i, --indent <num>            Number of indent chars per level (default: 2)")
  eprintln("  -I, --indent-char <char>      Indentation character (default: space)")
  eprintln("  -c, --compress                Minify output (remove whitespace)")
  eprintln("  -s, --selfclose               Use self-closing tags for empty elements")
  eprintln("  -S, --selfclose-space         Add space before /> in self-closing tags")
  eprintln("  -l, --disable-inlineformatting")
  eprintln("                                Disable inline formatting")
  eprintln("  -C, --disable-correction      Disable whitespace correction")
  eprintln("  -b, --blanks                  Preserve blank lines")
  eprintln("  -n, --eof-newline             Add newline at end of file")
  eprintln("  -p, --preserve <elems>        Comma-separated elements to preserve whitespace")
  eprintln("  -a, --preserve-attributes     Preserve attribute order")
  eprintln("  -E, --encode-attributes       Encode > and ' in attribute values")
  eprintln("  -o, --output/--outfile <file> Write output to file")
  eprintln("  -f, --infile <file>           Input file")
  eprintln("  -w, --overwrite               Overwrite input file")
  eprintln("  -h, --help                    Show this help")
  eprintln("")
  eprintln("Examples:")
  eprintln("  xmlfmt input.xml                    Pretty-print to stdout")
  eprintln("  xmlfmt -c input.xml                 Compress/minify")
  eprintln("  xmlfmt -i 4 input.xml               4-space indentation")
  eprintln("  xmlfmt -s -S input.xml              Self-closing tags with space")
  eprintln("  xmlfmt -o out.xml input.xml         Write to file")
  eprintln("  xmlfmt -w input.xml                 Overwrite in place")
  eprintln("  cat input.xml | xmlfmt -            Read from stdin")
}

///|
fn parse_int(s : String) -> Int {
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
  if neg { -result } else { result }
}

///|
fn read_stdin() -> String {
  // Read from stdin using env or file descriptor
  // MoonBit doesn't have direct stdin read in core; use /dev/stdin
  @fs.read_file_to_string("/dev/stdin") catch {
    _ => ""
  }
}
