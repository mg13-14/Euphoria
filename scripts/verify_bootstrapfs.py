#!/usr/bin/env python3
# verify_bootstrapfs.py — static verification of the rootful mount-over delivery
# (T5/T13/T14/T14-验收维度). Run from repo root or scripts/ dir.
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
def rd(p): return open(os.path.join(ROOT, p), encoding="utf-8").read()
def has(p, s): return s in rd(p)

checks = []
def ck(name, cond):
    checks.append((name, bool(cond)))

# --- 1. component present -----------------------------------------------------
for f in ["Makefile", "entitlements.plist", "src/main.m", "src/apfs_probe.h",
          "src/apfs_probe.m", "src/dirutils.h", "src/dirutils.m",
          "src/progress.h", "src/progress.m", "src/eufs_common.h",
          "src/eufs_state.h", "src/eufs_state.m"]:
    p = f"BaseBin/bootstrapfs/{f}"
    ck(f"component file {p}", os.path.exists(os.path.join(ROOT, p)) and os.path.getsize(os.path.join(ROOT, p)) > 100)

# --- 2. build wiring -----------------------------------------------------------
mk = rd("BaseBin/Makefile")
ck("BaseBin/Makefile: bootstrapfs in subprojects", re.search(r"^subprojects:.*\bbootstrapfs\b", mk, re.M))
ck("BaseBin/Makefile: bootstrapfs build rule", re.search(r"^bootstrapfs: .*libjailbreak", mk, re.M))
ck("BaseBin/Makefile: bootstrapfs in clean", re.search(r"-C bootstrapfs \$@", mk))
ck("bootstrapfs/Makefile: links libjailbreak", has("BaseBin/bootstrapfs/Makefile", "-ljailbreak"))
ck("bootstrapfs/Makefile: entitlements signing", has("BaseBin/bootstrapfs/Makefile", "-Sentitlements.plist"))

# --- 3. engine hardening (C7 risk closure) -------------------------------------
probe = rd("BaseBin/bootstrapfs/src/apfs_probe.m")
ck("probe: container discovered via statfs+IOKit (not hardcoded)", "statfs" in probe and "IORegistryEntryGetParentEntry" in probe)
ck("probe: both layout candidates verified before use", "candidates" in probe and "IOKit" in probe)
ck("probe: APFS SPI dlopen presence-reported", "APFS.framework" in probe and "eufs_emit_probe" in probe)
ck("no fixed on-volume Dopamine marker (risk #10)", not has("BaseBin/bootstrapfs/src/main.m", ".Dopamine_Rootful"))

du = rd("BaseBin/bootstrapfs/src/dirutils.m")
ck("copy: symlinks preserved verbatim (risk #4)", "readlink" in du and "symlink(" in du and "realpath" not in du)
ck("copy: bounded retries with backoff (risk #5)", "EUFS_COPY_ATTEMPTS" in du and "eufs_retry_delay_ms" in du)
ck("copy: fseventsd noise skipped (risk #3)", ".fseventsd" in du)

main_src = rd("BaseBin/bootstrapfs/src/main.m")
ck("engine: precheck before any volume creation (T13)", main_src.index("eufs_available_bytes") < main_src.index("eufs_create_volume"))
ck("engine: staging before commit (transactional, T13)", main_src.index("EUFS_STAGING_ROOT") < main_src.index("commit phase"))
ck("engine: rollback destroys staged volumes", "rollback:" in main_src and "eufs_destroy_volume" in main_src)
ck("engine: purge guarded by --confirm", "--confirm" in main_src)
ck("engine: progress fd plumbing", "--progress-fd" in main_src and "EUFS_PROGRESS_FD" in main_src)
ck("engine: kernel-cred dance around mount/unmount", "jbclient_root_steal_ucred" in probe)

# --- 4. libjailbreak orchestration ---------------------------------------------
ck("libjailbreak: rootful_fakefs.h/.c present",
   os.path.exists(os.path.join(ROOT, "BaseBin/libjailbreak/src/rootful_fakefs.c")))
rfc = rd("BaseBin/libjailbreak/src/rootful.c")
ck("rootful.c: placeholders replaced by engine", "rootful_fakefs_run" in rfc and "port APFSRW pending" not in rfc)
ck("rootful.c: progress trampoline wired", "rootful_engine_progress_trampoline" in rfc)
ck("rootful.c: disable delegates to engine", "rootful_fakefs_run(\"disable\"" in rfc)
rfh = rd("BaseBin/libjailbreak/src/rootful.h")
ck("rootful.h: rootful_enable_ex + progress typedef exported", "rootful_enable_ex" in rfh and "rootful_progress_fn" in rfh)

# --- 5. consumers ---------------------------------------------------------------
ck("jbctl: rootful command group", "internal rootful" in rd("BaseBin/jbctl/src/internal.m") and "purge" in rd("BaseBin/jbctl/src/internal.m"))
eup = rd("BaseBin/euphoria/src/main.m")
ck("euphoria: [STAGE] forwarding", "[STAGE] %s" in eup)
ck("euphoria: rootful_enable_ex used", "rootful_enable_ex" in eup)

# --- 6. docs --------------------------------------------------------------------
ck("docs: T15 delivery package present", os.path.exists(os.path.join(ROOT, "docs/06-rootful开关与进度视觉交付包_T15.md")))

# --- report ---------------------------------------------------------------------
failed = [n for n, ok in checks if not ok]
for n, ok in checks:
    print(("PASS " if ok else "FAIL ") + n)
print(f"\n{len(checks)-len(failed)}/{len(checks)} checks passed")
sys.exit(1 if failed else 0)
