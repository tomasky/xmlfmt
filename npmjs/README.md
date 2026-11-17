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
| `darwin-x64`         | `xmlfmt-darwin-x86_64` |

Assets are produced by `.github/workflows/release.yml` when a `v*` tag is
pushed.

## Install scripts are blocked by default

Recent npm (12+) and pnpm (10+) versions do **not** run a dependency's install
scripts unless the package is approved, so `postinstall` is skipped and
`bin/xmlfmt` is missing right after install:

```
npm warn install-scripts 1 package had install scripts blocked because they are not covered by allowScripts:
npm warn install-scripts   @tomasko/xmlfmt@0.1.3 (postinstall: node install.js)
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

## Upgrading

The wrapper only runs a binary that was downloaded for the installed package
version. After `npm i -g @tomasko/xmlfmt@latest`, a binary left behind by an
older version is detected (its version stamp in `bin/.xmlfmt-version` no longer
matches) and replaced on the next run, with a note on stderr:

```
xmlfmt: installed binary is for 0.1.5, this package is 0.1.8; fetching the matching binary
```

The wrapper also asks the binary for `--version` on every run. A binary that
reports a different version than the package is replaced before it is used, and
a release asset that reports the wrong version is rejected with an error instead
of being run:

```
xmlfmt: /path/bin/xmlfmt reports 0.1.5, this package is 0.1.9; reinstalling the matching binary
xmlfmt: the downloaded binary reports 0.1.5 but this package is 0.1.9; the release asset for v0.1.9 is stale or built from another commit
```

So `xmlfmt --version` always reports the version you installed. If a run still
shows an older version, the file being executed is not this package: check
`which -a xmlfmt`.

## Linux builds: glibc and musl

Each Linux release ships two builds: `xmlfmt-linux-<arch>` (statically linked
against musl, portable everywhere) and `xmlfmt-linux-<arch>-gnu` (linked against
glibc). On a glibc machine the wrapper tries the glibc build first and falls
back to the musl one if it is not published, because some hardened hosts kill
the static musl binary before it can print anything.

## If the tool prints nothing

A native binary that dies before it can print (wrong architecture, `SIGSEGV`
from an incompatible build, a seccomp policy that blocks a syscall) used to look
like a silent no-op. It is now reported:

```
xmlfmt: /path/bin/xmlfmt was killed by SIGSEGV before it produced output
xmlfmt: this is usually a binary that does not match this machine (uname -m: x64) ...
```

Run the binary directly to confirm, and include the signal name when reporting:

```bash
"$(npm root -g)/@tomasko/xmlfmt/bin/xmlfmt" --help; echo "exit=$?"
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
