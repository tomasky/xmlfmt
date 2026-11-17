#!/usr/bin/env node
// Launcher for the native `xmlfmt` binary. Downloads it on first run if the
// postinstall step did not (e.g. `--ignore-scripts`), then forwards all
// arguments, stdio and the exit code.
"use strict";

const { spawnSync } = require("child_process");
const { ensureBinary, pkg } = require("../lib");

async function main() {
  let binary;
  try {
    binary = await ensureBinary({
      log: (line) => process.stderr.write(line + "\n"),
    });
  } catch (err) {
    console.error(`xmlfmt: ${err.message}`);
    console.error(
      `xmlfmt: run \`npm rebuild ${pkg.name}\` to retry, or set XMLFMT_DOWNLOAD_BASE ` +
        `(or XMLFMT_REPO/XMLFMT_VERSION) to a mirror.`
    );
    process.exit(1);
  }

  const result = spawnSync(binary, process.argv.slice(2), { stdio: "inherit" });

  if (result.error) {
    console.error(`xmlfmt: failed to launch ${binary}: ${result.error.message}`);
    console.error(
      `xmlfmt: run \`npm rebuild ${pkg.name}\` to re-download it, or set ` +
        `XMLFMT_DOWNLOAD_BASE to a mirror that serves this platform.`
    );
    process.exit(1);
  }

  // A child killed by a signal produces no output of its own, which used to
  // look like "the tool prints nothing". Say what happened instead.
  if (result.signal) {
    console.error(
      `xmlfmt: ${binary} was killed by ${result.signal} before it produced output`
    );
    console.error(
      `xmlfmt: this is usually a binary that does not match this machine ` +
        `(uname -m: ${process.arch}). Re-run with \`XMLFMT_FORCE_DOWNLOAD=1\` ` +
        `after publishing assets for ${pkg.version}, or report it with ` +
        `\`file ${binary}\``
    );
    process.exit(1);
  }

  process.exit(typeof result.status === "number" ? result.status : 1);
}

main();
