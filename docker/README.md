# REA in Docker

`rea:local` is REA built from this checkout plus every Linux-capable provider,
pinned to the versions REA documents as verified:

| Provider / tool | Version | Configured by |
|---|---|---|
| Ghidra + JDK 21 | 12.1.4 | `GHIDRA_INSTALL_DIR` |
| Hopper (Linux demo) | current public demo | REA's own installer, `/opt/hopper` |
| Kuna | 1.833 | `REA_KUNA_COMMAND` |
| Rizin | 0.7.4 | `REA_RIZIN_COMMAND` |
| GNU objdump, GDB, TShark, sigrok-cli, cc65 | Ubuntu 24.04 packages | `PATH` / `REA_*_COMMAND` |
| pwntools (+ pyelftools, Unicorn) | 4.15.0 | `REA_PWNTOOLS_PYTHON` |
| pwndbg | 2026.09.15 | `REA_PWNDBG_*` |
| JADX headless MCP / Apktool / adb | 0.7.1 / 3.0.3 / latest | `REA_JADX_MCP_JAR`, `REA_APKTOOL_COMMAND`, `REA_ADB_PATH` |
| WABT | 1.0.42 | `REA_WABT_BIN_DIRECTORY` |
| Wakaru | 1.14.0 | `REA_WAKARU_COMMAND` |
| mitmproxy | 12.2.3 | `REA_MITMDUMP_COMMAND` |
| Binwalk / Unblob | 3.1.0 / 26.6.4 | `REA_BINWALK_COMMAND`, `REA_UNBLOB_COMMAND` |
| Chromium (Playwright) | 1.58.2 | `REA_BROWSER_EXECUTABLE` |
| Frida client | 17.23.2 | bundled npm dependency |

Not included: IDA and JEB (bring your own), Cutter (GUI), macOS-only Swift/LLDB.

## Build

```sh
docker build -t rea:local .
docker run --rm rea:local doctor --json
```

## Paths

The container sees only what is mounted. Host folders are mounted read-only
under `/targets/...`; `/work` is a writable scratch/output folder. Always pass
container paths (`/targets/iclone/...`), never Windows paths.

## Live instrumentation of Windows processes

REA's Frida provider runs in the container and attaches to a `frida-server`
on the host:

1. On Windows, run `E:\re-tools\frida\start-frida-server.ps1` (listens on
   `127.0.0.1:27042` only). Stop it when done.
2. From REA, use remote address `host.docker.internal:27042`, e.g.
   `rea list-frida-processes --remote-address host.docker.internal:27042`.
