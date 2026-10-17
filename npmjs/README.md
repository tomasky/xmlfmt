# xmlfmt (npm)

npm wrapper for [`xmlfmt`](../../blob/main/README.mbt.md) — an XML formatter
written in MoonBit.

```bash
pnpm install -g @tomasko/xmlfmt
xmlfmt --help
xmlfmt input.xml
```

## How it works

The package itself contains only a small launcher. On install, `install.js`
downloads the prebuilt `xmlfmt` binary for the current platform from GitHub
Releases and writes it to `bin/xmlfmt`. The published `bin` entry (`bin/xmlfmt.js`)
then spawns it, forwarding arguments, standard IO and the exit code.

The postinstall download is best-effort, and the launcher downloads the
binary on first run if it is missing (for example when installing with
`--ignore-scripts`, or when the release was not available yet).

Supported targets:

| Node `platform-arch` | Release asset       |
| -------------------- | ------------------- |
| `linux-x64`          | `xmlfmt-linux-x86_64`   |
| `linux-arm64`        | `xmlfmt-linux-aarch64`  |
| `darwin-arm64`       | `xmlfmt-darwin-aarch64` |

Intel macOS (`darwin-x64`) is not supported: the MoonBit toolchain no longer
ships a `darwin-x86_64` target, so no such build can be produced.

Assets are produced by `.github/workflows/release.yml` when a `v*` tag is
pushed.

## Install scripts are blocked by default

Recent npm (12+) and pnpm (10+) versions do **not** run a dependency's install
scripts unless the package is approved, so `postinstall` is skipped and
`bin/xmlfmt` is missing right after install:

```
npm warn install-scripts 1 package had install scripts blocked because they are not covered by allowScripts:
npm warn install-scripts   @tomasko/xmlfmt@0.1.2 (postinstall: node install.js)
xmlfmt: native binary not found at .../node_modules/@tomasko/xmlfmt/bin/xmlfmt
```

Nothing is broken: `bin/xmlfmt.js` downloads the binary on first run. To have it
downloaded at install time instead, approve the build once:

```bash
npm install-scripts approve @tomasko/xmlfmt   # npm 12+ (writes `allowScripts`)
pnpm approve-builds                       # pnpm 10+
```

Either way, re-run the download manually with:

```bash
npm rebuild @tomasko/xmlfmt
# or
pnpm rebuild @tomasko/xmlfmt
```

## Overrides

| Variable             | Purpose                                          |
| -------------------- | ------------------------------------------------ |
| `XMLFMT_REPO`        | `owner/repo` to download from                    |
| `XMLFMT_VERSION`     | release version to download                      |
| `XMLFMT_DOWNLOAD_BASE` | full base URL (mirror), e.g. `https://host/assets` |
| `XMLFMT_FORCE_DOWNLOAD` | re-download even if the binary is present        |
| `XMLFMT_SKIP_DOWNLOAD` | skip the download entirely                       |

## Publishing

From this directory:

```bash
npm publish --access public
# or
pnpm publish --access public
```

`--access public` is required for scoped packages such as `@tomasko/xmlfmt`.
Change `name`, `repository` and `homepage` in `package.json` first if you
publish under a different scope or repository.
