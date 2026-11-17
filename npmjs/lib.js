"use strict";

// Shared install logic for the npm wrapper: works out which prebuilt `xmlfmt`
// binary to use and downloads it from GitHub Releases on demand.
//
// Overridable for forks / private mirrors:
//   XMLFMT_REPO            owner/repo            (default: parsed from package.json)
//   XMLFMT_VERSION         release version       (default: package.json version)
//   XMLFMT_DOWNLOAD_BASE   full base URL         (overrides XMLFMT_REPO/XMLFMT_VERSION)
//   XMLFMT_FORCE_DOWNLOAD  re-download even if the binary is present
//   XMLFMT_SKIP_DOWNLOAD   never download

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const https = require("https");
const http = require("http");

const pkg = require("./package.json");

const TARGETS = {
  "linux-x64": "linux-x86_64",
  "linux-arm64": "linux-aarch64",
  "darwin-arm64": "darwin-aarch64",
  "darwin-x64": "darwin-x86_64",
};

function repoSlug(repo) {
  if (!repo) return null;
  const url = typeof repo === "string" ? repo : repo.url || "";
  const m = url.match(/github\.com[/:]([^/]+)\/([^/.]+)/);
  return m ? `${m[1]}/${m[2]}` : null;
}

function targetName() {
  return TARGETS[`${process.platform}-${process.arch}`];
}

function downloadUrl(target) {
  if (process.env.XMLFMT_DOWNLOAD_BASE) {
    return `${process.env.XMLFMT_DOWNLOAD_BASE.replace(/\/$/, "")}/xmlfmt-${target}`;
  }
  const repo = process.env.XMLFMT_REPO || repoSlug(pkg.repository) || "tomasky/xmlfmt";
  const version = process.env.XMLFMT_VERSION || pkg.version;
  return `https://github.com/${repo}/releases/download/v${version}/xmlfmt-${target}`;
}

function binaryPath(dir) {
  return path.join(
    dir || __dirname,
    "bin",
    process.platform === "win32" ? "xmlfmt.exe" : "xmlfmt"
  );
}

// The downloaded binary is only valid for the package version that fetched it.
// Its stamp is written next to it so an upgrade can tell a current binary from
// one left behind by an older version: the wrapper used to accept any existing
// file, so a stale download silently kept the old behaviour after `npm i -g`.
const STAMP_NAME = ".xmlfmt-version";

function stampPath(dir) {
  return path.join(dir || __dirname, "bin", STAMP_NAME);
}

// Version recorded for the binary currently in `dir`, or null if unknown.
function readStamp(dir) {
  try {
    return fs.readFileSync(stampPath(dir), "utf8").trim();
  } catch {
    return null;
  }
}

function writeStamp(dir, version) {
  fs.mkdirSync(path.dirname(stampPath(dir)), { recursive: true });
  fs.writeFileSync(stampPath(dir), `${version}\n`);
}

// True when a binary is present *and* was downloaded for this package version.
function isInstalled(dir) {
  try {
    fs.accessSync(binaryPath(dir), fs.constants.X_OK);
  } catch {
    return false;
  }
  return readStamp(dir) === pkg.version;
}

function fetch(url, redirects) {
  return new Promise((resolve, reject) => {
    if (redirects > 10) return reject(new Error("too many redirects"));
    const client = url.startsWith("http:") ? http : https;
    const req = client.get(
      url,
      { headers: { "user-agent": `xmlfmt-npm/${pkg.version}` } },
      (res) => {
        const { statusCode, headers } = res;
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          const next = new URL(headers.location, url).toString();
          resolve(fetch(next, (redirects || 0) + 1));
          return;
        }
        if (statusCode !== 200) {
          res.resume();
          reject(new Error(`GET ${url} -> HTTP ${statusCode}`));
          return;
        }
        resolve(res);
      }
    );
    req.on("error", reject);
  });
}

async function download(target, dest) {
  const url = downloadUrl(target);
  const res = await fetch(url, 0);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  await new Promise((resolve, reject) => {
    const out = fs.createWriteStream(dest);
    res.pipe(out);
    out.on("finish", () => out.close(resolve));
    out.on("error", reject);
    res.on("error", reject);
  });
  fs.chmodSync(dest, 0o755);
  return url;
}

// Fetch a small body as text (used for checksum files).
function fetchText(url) {
  return fetch(url, 0).then(
    (res) =>
      new Promise((resolve, reject) => {
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => resolve(body));
        res.on("error", reject);
      })
  );
}

function sha256File(file) {
  return crypto
    .createHash("sha256")
    .update(fs.readFileSync(file))
    .digest("hex");
}

// Pull the expected hash for `assetName` out of a sha256sum-style file
// ("<hex>  <name>"); the published name differs from the local dest path.
function expectedHash(checksumBody, assetName) {
  for (const line of checksumBody.split(/\r?\n/)) {
    const m = line.match(/^([0-9a-fA-F]{64})\s+\*?(.+)$/);
    if (m && m[2].trim() === assetName) {
      return m[1].toLowerCase();
    }
  }
  return null;
}

// Verify a downloaded binary against its published `<url>.sha256`.
// Mirrors install.sh: a missing checksum file only warns, a mismatch is
// fatal and deletes the downloaded file so it cannot be executed.
async function verifyChecksum(target, dest, log = () => {}) {
  const asset = `xmlfmt-${target}`;
  const url = `${downloadUrl(target)}.sha256`;
  let body;
  try {
    body = await fetchText(url);
  } catch (err) {
    log(`xmlfmt: warning: no checksum published (${url}), skipping verification`);
    return;
  }
  const expected = expectedHash(body, asset);
  if (!expected) {
    log(`xmlfmt: warning: checksum file does not list ${asset}, skipping verification`);
    return;
  }
  const actual = sha256File(dest);
  if (actual !== expected) {
    try {
      fs.unlinkSync(dest);
    } catch {}
    throw new Error(
      `checksum mismatch for ${asset}: expected ${expected}, got ${actual}; ` +
        `the downloaded file was deleted`
    );
  }
  log(`xmlfmt: checksum verified for ${asset}`);
}

async function ensureBinary({ force = false, log = () => {}, dir } = {}) {
  const dest = binaryPath(dir);
  const stale = (() => {
    try {
      fs.accessSync(dest, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  })();

  if (!force && !process.env.XMLFMT_FORCE_DOWNLOAD && isInstalled(dir)) {
    return dest;
  }

  if (process.env.XMLFMT_SKIP_DOWNLOAD) {
    if (isInstalled(dir)) return dest;
    throw new Error("XMLFMT_SKIP_DOWNLOAD is set but no binary is installed");
  }

  // Say why an existing binary is being replaced instead of silently reusing
  // it: a stale download after an upgrade is the failure this check exists for.
  if (stale && !force) {
    const found = readStamp(dir);
    log(
      `xmlfmt: installed binary is for ${found || "an unknown version"}, ` +
        `this package is ${pkg.version}; fetching the matching binary`
    );
  }

  const target = targetName();
  if (!target) {
    throw new Error(
      `unsupported platform ${process.platform}-${process.arch}; xmlfmt ` +
        `supports linux-x64, linux-arm64, darwin-arm64 and darwin-x64`
    );
  }

  log(`xmlfmt: downloading ${downloadUrl(target)}`);
  await download(target, dest);
  await verifyChecksum(target, dest, log);
  writeStamp(dir, pkg.version);
  log(`xmlfmt: installed ${dest}`);
  return dest;
}

module.exports = {
  pkg,
  TARGETS,
  STAMP_NAME,
  targetName,
  downloadUrl,
  binaryPath,
  stampPath,
  readStamp,
  writeStamp,
  isInstalled,
  ensureBinary,
  verifyChecksum,
  expectedHash,
  sha256File,
};