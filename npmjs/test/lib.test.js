"use strict";

// Tests for the npm wrapper's install logic. Run with:
//
//   node --test npmjs/test/
//
// The interesting case is the regression this file exists for: a binary left
// behind by an older package version used to be accepted, so `npm i -g` could
// upgrade the package and still run the old formatter.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const http = require("http");

const lib = require("../lib");

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "xmlfmt-test-"));
}

// A stand-in for the native binary: `--version` must answer like the real one.
function fakeBinary(version) {
  return `#!/bin/sh\necho "xmlfmt ${version}"\n`;
}

function writeBinary(dir, contents) {
  const dest = lib.binaryPath(dir);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, contents);
  fs.chmodSync(dest, 0o755);
  return dest;
}

// Set env vars for the duration of `fn`, which may be async: awaiting inside
// the caller is what keeps the vars alive for the whole download.
async function withEnv(vars, fn) {
  const saved = {};
  for (const key of Object.keys(vars)) {
    saved[key] = process.env[key];
    if (vars[key] === undefined) delete process.env[key];
    else process.env[key] = vars[key];
  }
  try {
    return await fn();
  } finally {
    for (const key of Object.keys(saved)) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
}

test("downloadUrl points at the release for this package version", async () => {
  await withEnv({ XMLFMT_DOWNLOAD_BASE: undefined, XMLFMT_REPO: undefined, XMLFMT_VERSION: undefined }, () => {
    assert.equal(
      lib.downloadUrl("linux-x86_64"),
      `https://github.com/tomasky/xmlfmt/releases/download/v${lib.pkg.version}/xmlfmt-linux-x86_64`
    );
  });
});

test("downloadUrl honours mirror overrides", async () => {
  await withEnv(
    {
      XMLFMT_DOWNLOAD_BASE: "https://mirror.example/rel/",
      XMLFMT_REPO: undefined,
      XMLFMT_VERSION: undefined,
    },
    () => {
      assert.equal(
        lib.downloadUrl("darwin-aarch64"),
        "https://mirror.example/rel/xmlfmt-darwin-aarch64"
      );
    }
  );
  await withEnv(
    { XMLFMT_DOWNLOAD_BASE: undefined, XMLFMT_REPO: "me/fork", XMLFMT_VERSION: "9.9.9" },
    () => {
      assert.equal(
        lib.downloadUrl("linux-aarch64"),
        "https://github.com/me/fork/releases/download/v9.9.9/xmlfmt-linux-aarch64"
      );
    }
  );
});

test("expectedHash matches the published sha256sum line", () => {
  const body = [
    "aa".repeat(32) + "  xmlfmt-linux-x86_64",
    "bb".repeat(32) + " *xmlfmt-darwin-aarch64",
    "",
  ].join("\n");
  assert.equal(lib.expectedHash(body, "xmlfmt-linux-x86_64"), "aa".repeat(32));
  assert.equal(lib.expectedHash(body, "xmlfmt-darwin-aarch64"), "bb".repeat(32));
  assert.equal(lib.expectedHash(body, "xmlfmt-linux-aarch64"), null);
});

test("isInstalled requires a binary stamped for this package version", () => {
  const dir = tmpdir();
  assert.equal(lib.isInstalled(dir), false, "no binary");

  writeBinary(dir, fakeBinary("0.0.0"));
  assert.equal(lib.isInstalled(dir), false, "binary without a stamp (pre-stamp install)");

  lib.writeStamp(dir, "0.1.5");
  assert.equal(lib.isInstalled(dir), false, "binary stamped for another version");

  lib.writeStamp(dir, lib.pkg.version);
  assert.equal(lib.isInstalled(dir), true, "binary stamped for this version");

  assert.equal(lib.readStamp(dir), lib.pkg.version);
  assert.equal(lib.binaryPath(dir), path.join(dir, "bin", "xmlfmt"));
  assert.equal(lib.stampPath(dir), path.join(dir, "bin", lib.STAMP_NAME));
});

test("ensureBinary keeps a binary stamped for this version", async () => {
  const dir = tmpdir();
  writeBinary(dir, fakeBinary(lib.pkg.version));
  lib.writeStamp(dir, lib.pkg.version);

  // No server is running: any download attempt would fail the test.
  const logs = [];
  const dest = await lib.ensureBinary({ dir, glibc: false, log: (line) => logs.push(line) });
  assert.equal(dest, lib.binaryPath(dir));
  assert.deepEqual(logs, []);
});

test("ensureBinary replaces a stale binary instead of silently using it", async () => {
  const target = lib.targetName();
  assert.ok(target, "tests require a supported platform");

  const dir = tmpdir();
  writeBinary(dir, fakeBinary("0.1.5"));
  lib.writeStamp(dir, "0.1.5");

  const fresh = Buffer.from(fakeBinary(lib.pkg.version));
  const sha = require("crypto").createHash("sha256").update(fresh).digest("hex");
  const server = http.createServer((req, res) => {
    if (req.url === `/xmlfmt-${target}`) {
      res.writeHead(200);
      res.end(fresh);
    } else if (req.url === `/xmlfmt-${target}.sha256`) {
      res.writeHead(200);
      res.end(`${sha}  xmlfmt-${target}\n`);
    } else {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;

  try {
    await withEnv({ XMLFMT_DOWNLOAD_BASE: `http://127.0.0.1:${port}` }, async () => {
      const logs = [];
      const dest = await lib.ensureBinary({ dir, log: (line) => logs.push(line) });
      assert.equal(fs.readFileSync(dest, "utf8"), fresh.toString());
      assert.equal(lib.readStamp(dir), lib.pkg.version);
      assert.ok(
        logs.some((line) => line.includes("unknown version") || line.includes("0.1.5")),
        `expected a stale-binary message, got: ${JSON.stringify(logs)}`
      );
      assert.ok(
        logs.some((line) => line.includes("checksum verified")),
        `expected checksum verification, got: ${JSON.stringify(logs)}`
      );
    });
  } finally {
    server.close();
  }

  // A binary whose checksum does not match must never be kept.
  const dir2 = tmpdir();
  const badServer = http.createServer((req, res) => {
    res.writeHead(200);
    if (req.url.endsWith(".sha256")) res.end(`${"cc".repeat(32)}  xmlfmt-${target}\n`);
    else res.end(fakeBinary(lib.pkg.version));
  });
  await new Promise((resolve) => badServer.listen(0, "127.0.0.1", resolve));
  try {
    await withEnv(
      { XMLFMT_DOWNLOAD_BASE: `http://127.0.0.1:${badServer.address().port}` },
      async () => {
        await assert.rejects(
          () => lib.ensureBinary({ dir: dir2, glibc: false, log: () => {} }),
          /checksum mismatch/
        );
      }
    );
  } finally {
    badServer.close();
  }
  assert.equal(fs.existsSync(lib.binaryPath(dir2)), false);
  assert.equal(lib.readStamp(dir2), null, "no stamp for a rejected download");
});

test("ensureBinary distrusts a stamped binary that reports another version", async () => {
  const target = lib.targetName();
  assert.ok(target, "tests require a supported platform");

  const dir = tmpdir();
  // Stamp claims the current version, the binary inside is an old one: exactly
  // what a copied node_modules or an image layer produced.
  writeBinary(dir, fakeBinary("0.1.5"));
  lib.writeStamp(dir, lib.pkg.version);
  assert.equal(lib.isInstalled(dir), true, "stamp alone says installed");

  const fresh = Buffer.from(fakeBinary(lib.pkg.version));
  const sha = require("crypto").createHash("sha256").update(fresh).digest("hex");
  const server = http.createServer((req, res) => {
    res.writeHead(200);
    if (req.url.endsWith(".sha256")) res.end(`${sha}  xmlfmt-${target}\n`);
    else res.end(fresh);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await withEnv(
      { XMLFMT_DOWNLOAD_BASE: `http://127.0.0.1:${server.address().port}` },
      async () => {
        const logs = [];
        const dest = await lib.ensureBinary({ dir, glibc: false, log: (line) => logs.push(line) });
        assert.equal(lib.probeVersion(dest), lib.pkg.version);
        assert.ok(
          logs.some((line) => line.includes("reports 0.1.5")),
          `expected a version-mismatch message, got: ${JSON.stringify(logs)}`
        );
      }
    );
  } finally {
    server.close();
  }
});

test("ensureBinary rejects a release asset built from another commit", async () => {
  const target = lib.targetName();
  assert.ok(target, "tests require a supported platform");

  const dir = tmpdir();
  // The download succeeds and its checksum is right, but the binary is stale:
  // publishing the npm package before tagging the release does this.
  const stale = Buffer.from(fakeBinary("0.0.9"));
  const sha = require("crypto").createHash("sha256").update(stale).digest("hex");
  const server = http.createServer((req, res) => {
    res.writeHead(200);
    if (req.url.endsWith(".sha256")) res.end(`${sha}  xmlfmt-${target}\n`);
    else res.end(stale);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await withEnv(
      { XMLFMT_DOWNLOAD_BASE: `http://127.0.0.1:${server.address().port}` },
      async () => {
        await assert.rejects(
          () => lib.ensureBinary({ dir, glibc: false, log: () => {} }),
          /reports 0\.0\.9/
        );
      }
    );
  } finally {
    server.close();
  }
  assert.equal(fs.existsSync(lib.binaryPath(dir)), false, "stale asset removed");
  assert.equal(lib.readStamp(dir), null, "no stamp for a mismatched binary");
});

test("probe explains a binary that dies instead of reporting a version", () => {
  const dir = tmpdir();
  // Answers nothing and kills itself: the pre-wrapper symptom was silence.
  writeBinary(dir, "#!/bin/sh\nkill -SEGV $$\n");
  const probed = lib.probe(lib.binaryPath(dir));
  assert.equal(probed.version, null);
  assert.match(probed.reason, /killed by SIG/);
});

test("probe explains a binary that cannot be executed at all", () => {
  const dir = tmpdir();
  const dest = lib.binaryPath(dir);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, "not a program\n");
  fs.chmodSync(dest, 0o755);
  const probed = lib.probe(dest);
  assert.equal(probed.version, null);
  assert.match(probed.reason, /cannot be executed|exited with status/);
});

test("launcher reports a binary killed by a signal instead of staying silent", () => {
  const { spawnSync } = require("child_process");
  const dir = tmpdir();
  // A copy of the package that answers --version (so it is not reinstalled)
  // and then dies without printing: exactly what an incompatible build does.
  for (const file of ["lib.js", "package.json"]) {
    fs.copyFileSync(path.join(__dirname, "..", file), path.join(dir, file));
  }
  fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
  fs.copyFileSync(
    path.join(__dirname, "..", "bin", "xmlfmt.js"),
    path.join(dir, "bin", "xmlfmt.js")
  );
  const binary = path.join(dir, "bin", "xmlfmt");
  fs.writeFileSync(
    binary,
    `#!/bin/sh\nif [ "$1" = "--version" ]; then echo "xmlfmt ${lib.pkg.version}"; exit 0; fi\nkill -SEGV $$\n`
  );
  fs.chmodSync(binary, 0o755);
  fs.writeFileSync(path.join(dir, "bin", lib.STAMP_NAME), `${lib.pkg.version}\n`);

  const res = spawnSync(process.execPath, [path.join(dir, "bin", "xmlfmt.js"), "--help"], {
    encoding: "utf8",
  });
  assert.equal(res.status, 1);
  assert.equal(res.stdout, "", "a killed binary produces no stdout");
  assert.match(res.stderr, /killed by SIGSEGV/);
  assert.match(res.stderr, /does not match this machine/);
});

test("targetCandidates prefers a glibc build on glibc Linux only", () => {
  if (process.platform !== "linux") return;
  const target = lib.targetName();
  assert.deepEqual(lib.targetCandidates(false), [target]);
  assert.deepEqual(lib.targetCandidates(true), [`${target}-gnu`, target]);
});

test("ensureBinary falls back when the preferred asset is missing", async () => {
  const target = lib.targetName();
  assert.ok(target, "tests require a supported platform");
  // Only glibc Linux has a second candidate to fall back to; elsewhere the
  // single candidate is downloaded directly and there is no fallback message.
  if (lib.targetCandidates(true).length < 2) return;

  const dir = tmpdir();
  const fresh = Buffer.from(fakeBinary(lib.pkg.version));
  const sha = require("crypto").createHash("sha256").update(fresh).digest("hex");
  // Only the musl asset exists: the gnu one 404s, which must not abort.
  const server = http.createServer((req, res) => {
    if (req.url === `/xmlfmt-${target}` || req.url === `/xmlfmt-${target}.sha256`) {
      res.writeHead(200);
      res.end(req.url.endsWith(".sha256") ? `${sha}  xmlfmt-${target}\n` : fresh);
    } else {
      res.writeHead(404);
      res.end();
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await withEnv(
      { XMLFMT_DOWNLOAD_BASE: `http://127.0.0.1:${server.address().port}` },
      async () => {
        const logs = [];
        const dest = await lib.ensureBinary({ dir, glibc: true, log: (line) => logs.push(line) });
        assert.equal(lib.probeVersion(dest), lib.pkg.version);
        assert.ok(
          logs.some((line) => line.includes("is unavailable")),
          `expected a fallback message, got: ${JSON.stringify(logs)}`
        );
      }
    );
  } finally {
    server.close();
  }
});
