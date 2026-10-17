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
const https = require("https");
const http = require("http");

const pkg = require("./package.json");

const TARGETS = {
  "linux-x64": "linux-x86_64",
  "linux-arm64": "linux-aarch64",
  "darwin-arm64": "darwin-aarch64",
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

function binaryPath() {
  return path.join(
    __dirname,
    "bin",
    process.platform === "win32" ? "xmlfmt.exe" : "xmlfmt"
  );
}

function isInstalled() {
  try {
    fs.accessSync(binaryPath(), fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
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

async function ensureBinary({ force = false, log = () => {} } = {}) {
  const dest = binaryPath();

  if (!force && !process.env.XMLFMT_FORCE_DOWNLOAD && isInstalled()) {
    return dest;
  }

  if (process.env.XMLFMT_SKIP_DOWNLOAD) {
    if (isInstalled()) return dest;
    throw new Error("XMLFMT_SKIP_DOWNLOAD is set but no binary is installed");
  }

  const target = targetName();
  if (!target) {
    throw new Error(
      `unsupported platform ${process.platform}-${process.arch}; xmlfmt ` +
        `supports linux-x64, linux-arm64 and darwin-arm64`
    );
  }

  log(`xmlfmt: downloading ${downloadUrl(target)}`);
  await download(target, dest);
  log(`xmlfmt: installed ${dest}`);
  return dest;
}

module.exports = {
  pkg,
  TARGETS,
  targetName,
  downloadUrl,
  binaryPath,
  isInstalled,
  ensureBinary,
};