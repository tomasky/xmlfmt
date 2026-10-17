#!/usr/bin/env node
// Postinstall hook: download the prebuilt `xmlfmt` binary for this platform.
//
// This is best-effort: if the download fails the install still succeeds, and
// `bin/xmlfmt.js` retries on first run. Set XMLFMT_SKIP_DOWNLOAD=1 to opt out.
"use strict";

const { ensureBinary, pkg } = require("./lib");

if (process.env.XMLFMT_SKIP_DOWNLOAD) {
  console.log("xmlfmt: XMLFMT_SKIP_DOWNLOAD set, skipping binary download");
  process.exit(0);
}

ensureBinary({ log: console.log })
  .then(() => process.exit(0))
  .catch((err) => {
    console.warn(`xmlfmt: could not download the native binary: ${err.message}`);
    console.warn(
      `xmlfmt: it will be downloaded on first run instead. If that also fails, ` +
        `set XMLFMT_DOWNLOAD_BASE (or XMLFMT_REPO/XMLFMT_VERSION) to a mirror and run ` +
        `\`npm rebuild ${pkg.name}\`.`
    );
    process.exit(0);
  });