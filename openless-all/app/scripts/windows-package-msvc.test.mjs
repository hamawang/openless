import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const appRoot = join(scriptsDir, "..");
const scriptPath = join(scriptsDir, "windows-package-msvc.ps1");
const launcherPath = join(scriptsDir, "windows-package-msvc.cmd");
const imeBuildPath = join(scriptsDir, "windows-ime-build.ps1");
const tauriConfigPath = join(appRoot, "src-tauri", "tauri.conf.json");
const wixFragmentPath = join(appRoot, "src-tauri", "wix", "openless-ime.wxs");

const script = readFileSync(scriptPath, "utf8");
const launcher = readFileSync(launcherPath, "utf8");
const imeBuild = readFileSync(imeBuildPath, "utf8");
const tauriConfig = JSON.parse(readFileSync(tauriConfigPath, "utf8"));
const wixFragment = readFileSync(wixFragmentPath, "utf8");

const requiredFragments = [
  "Install-RustMsvcToolchain",
  "https://win.rustup.rs/x86_64",
  "stable-x86_64-pc-windows-msvc",
  "Find-VsDevCmd",
  "VsDevCmd.bat",
  "npm.cmd ci",
  "windows-ime-build.ps1",
  "OPENLESS_IME_DLL",
  "OpenLessIme.dll",
  "tauri build -- --target x86_64-pc-windows-msvc --bundles msi",
  "Repair-TauriMsiBundle",
  "light.exe",
  "main.wixobj",
  "openless-ime.wixobj",
  "locale.wxl",
  "WebView2Loader.dll",
  "Compress-Archive",
  "Get-FileHash -Algorithm SHA256",
];

for (const fragment of requiredFragments) {
  assert.match(script, new RegExp(fragment.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")), `missing ${fragment}`);
}

assert.match(script, /\[switch\]\$SkipRustInstall/, "script should support opting out of Rust installation");
assert.match(script, /\[switch\]\$SkipNpmCi/, "script should support reusing existing node_modules");
assert.match(script, /\[switch\]\$CleanArtifacts/, "script should support cleaning the output directory");

assert.match(imeBuild, /\[string\]\$OutputDirectory/, "IME build should support a package-specific output directory");
assert.match(imeBuild, /\[string\]\$IntermediateDirectory/, "IME build should support a package-specific intermediate directory");
assert.match(imeBuild, /\/p:OutDir=/, "IME build should pass OutDir to MSBuild");
assert.match(imeBuild, /\/p:IntDir=/, "IME build should pass IntDir to MSBuild");

assert.deepEqual(tauriConfig.bundle.windows.wix.fragmentPaths, ["wix/openless-ime.wxs"]);
assert.deepEqual(tauriConfig.bundle.windows.wix.componentRefs, ["OpenLessImeDllComponent"]);

assert.match(wixFragment, /DirectoryRef Id="INSTALLDIR"/, "WiX fragment should install into the app directory");
assert.match(wixFragment, /Component Id="OpenLessImeDllComponent"/, "WiX fragment should define the TSF DLL component");
assert.match(wixFragment, /Source="src-tauri\\target\\windows-ime-msvc\\x64\\Release\\OpenLessIme\.dll"/, "WiX fragment should consume the package-built IME DLL");
assert.match(wixFragment, /regsvr32\.exe/, "MSI should register and unregister the TSF DLL");
assert.match(wixFragment, /RegisterOpenLessIme/, "MSI should register OpenLess IME during install");
assert.match(wixFragment, /UnregisterOpenLessIme/, "MSI should unregister OpenLess IME during uninstall");

assert.match(launcher, /powershell\.exe/, "launcher should call powershell.exe");
assert.match(launcher, /-ExecutionPolicy Bypass/, "launcher should bypass execution policy for this process");
assert.match(launcher, /windows-package-msvc\.ps1/, "launcher should invoke the packaging script");
assert.match(launcher, /%SUPPLIED_ARGS%/, "launcher should forward user arguments");
