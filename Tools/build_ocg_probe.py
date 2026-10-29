#!/usr/bin/env python3
"""Build the opt-in Linux OCG diagnostic; never fetch without --fetch.

This builds only the MIT Fluorohydride core, not the GPL client or AGPL KCG fork.
No system installation, CMake, Godot headers or third-party Python package needed.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from import_ocg_cards import load_pool, reviewed_script

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache/ocg"


def run(*args: str | Path, cwd: Path | None = None) -> None:
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True, timeout=300)


def prepare_core(core: Path, metadata: dict, fetch: bool) -> str:
    """Resume an interrupted empty initialization, never overwrite another tree."""
    if not core.exists():
        if not fetch:
            raise RuntimeError("core is not cached; rerun with --fetch to authorize downloads")
        run("git", "init", core)
    head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=core,
                          capture_output=True, text=True, timeout=30)
    if head.returncode != 0:
        # A failed initial network fetch leaves an initialized but empty repo.
        # Recover it with explicit download permission, without touching a populated
        # checkout or arbitrarily adopting a non-Git directory supplied by the user.
        if not (core / ".git").exists() or any(path.name != ".git" for path in core.iterdir()):
            raise RuntimeError("core directory has no valid HEAD and is not an empty initialized repository")
        if not fetch:
            raise RuntimeError("core initialization is incomplete; rerun with --fetch")
        run("git", "fetch", "--depth=1", metadata["repository"], metadata["revision"], cwd=core)
        run("git", "checkout", "--detach", "FETCH_HEAD", cwd=core)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=core, text=True, timeout=30).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=core, text=True, timeout=30).strip()
    if revision != metadata["revision"] or dirty:
        raise RuntimeError("core checkout must be clean and exactly match ThirdParty/ocg/lock.json")
    return revision


def extract_pinned_source(core: Path, revision: str, destination: Path) -> None:
    archive = subprocess.check_output(["git", "archive", "--format=tar", revision], cwd=core, timeout=30)
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(destination, filter="data")


def generate_card_fixture(root: Path, destination: Path) -> None:
    """Strict two-card metadata conversion, not a permissive all-card importer."""
    data = json.loads((root / "Data/reference_cards/newdoria_battle.json").read_text())
    if not isinstance(data, dict) or type(data.get("schema_version")) is not int or data["schema_version"] != 1 or not isinstance(data.get("cards"), list):
        raise ValueError("unsupported reference card data schema")
    expected = {32541773: ("Normal Monster", "EARTH", 1200, 1500),
                4335645: ("Effect Monster", "DARK", 1200, 800)}
    if (len(data["cards"]) != 2 or not all(isinstance(card, dict) and type(card.get("code")) is int for card in data["cards"])
            or {card["code"] for card in data["cards"]} != set(expected)):
        raise ValueError("reference fixture must contain exactly the two reviewed card IDs")
    rows = []
    for card in data["cards"]:
        code = card["code"]
        passcode = card.get("passcode")
        if not isinstance(passcode, str) or len(passcode) != 8 or not passcode.isascii() or not passcode.isdigit() or int(passcode) != code:
            raise ValueError("printed passcode must preserve eight digits and map to the integer core ID")
        category, attribute, attack, defense = expected[code]
        if (card.get("category"), card.get("attribute"), card.get("attack"), card.get("defense")) != expected[code]:
            raise ValueError("reference fixture differs from the reviewed official card metadata")
        if any(type(card.get(key)) is not int for key in ("level", "attack", "defense")) or card.get("level") != 4 or card.get("race") != "Fiend":
            raise ValueError("reference fixture has an unsupported level or race")
        subtype = "TYPE_NORMAL" if category == "Normal Monster" else "TYPE_EFFECT"
        rows.append(f"{{{code}u, TYPE_MONSTER | {subtype}, 4, ATTRIBUTE_{attribute}, RACE_FIEND, {attack}, {defense}, 0}}")
    script = reviewed_script(root)
    digest = hashlib.sha256(script.encode()).hexdigest()
    checks = (root / "Tools/ocg/lua/test_newdoria.lua").read_text()
    pool, pool_digest = load_pool(root)
    practice_rows = []
    for card in pool:
        race = card["race"].replace("-", "").upper()
        tuner = " | TYPE_TUNER" if card["tuner"] else ""
        practice_rows.append(f"{{{card['code']}u, TYPE_MONSTER | TYPE_NORMAL{tuner}, {card['level']}, ATTRIBUTE_{card['attribute']}, RACE_{race}, {card['attack']}, {card['defense']}, {card['setcode']}}}")
    destination.write_text(
        "// Generated from reviewed project-owned inputs; do not edit.\n#pragma once\n"
        "struct ReferenceCardRow { uint32_t code, type, level, attribute, race; int32_t attack, defense; uint64_t setcode; };\n"
        "static const ReferenceCardRow REFERENCE_CARDS[] = {" + ",".join(rows) + "};\n"
        "static const ReferenceCardRow PRACTICE_CARDS[] = {" + ",".join(practice_rows) + "};\n"
        "static const char PRACTICE_POOL_SHA256[] = \"" + pool_digest + "\";\n"
        "static const char NEWDORIA_LUA[] = " + json.dumps(script) + ";\n"
        "static const char NEWDORIA_CHECKS[] = " + json.dumps(checks) + ";\n"
        "static const char NEWDORIA_LUA_SHA256[] = \"" + digest + "\";\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="download pinned core and Lua")
    parser.add_argument("--core-dir", type=Path, default=CACHE / "ygopro-core")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 1, 4))
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("this first build target supports Linux only; no untested platform claim")
    if not 1 <= args.jobs <= 32:
        parser.error("--jobs must be 1..32")
    for executable in ("git", "g++"):
        if not shutil.which(executable):
            parser.error(f"required compiler/tool missing: {executable}")
    lock = json.loads((ROOT / "ThirdParty/ocg/lock.json").read_text())
    CACHE.mkdir(parents=True, exist_ok=True)
    core = args.core_dir.resolve()
    revision = prepare_core(core, lock["core"], args.fetch)
    # Compile only the pinned Git tree, not ignored files or worktree changes
    # hidden by assume-unchanged/skip-worktree flags. No mutable glob is trusted.
    core_source = CACHE / "core-source"
    extract_pinned_source(core, revision, core_source)
    archive = CACHE / f"lua-{lock['lua']['version']}.tar.gz"
    if not archive.exists():
        if not args.fetch:
            parser.error("Lua archive is not cached; rerun with --fetch")
        temporary = archive.with_suffix(".download")
        with urllib.request.urlopen(lock["lua"]["url"], timeout=60) as source:
            temporary.write_bytes(source.read(4 * 1024 * 1024))
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock["lua"]["sha256"]:
        parser.error(f"Lua checksum mismatch; remove {archive} and fetch again")
    # Re-extract the verified archive each time: an edited cached source must not be
    # silently accepted as a pinned dependency. Safe extraction rejects traversal.
    lua_directory = CACHE / f"lua-{lock['lua']['version']}"
    if lua_directory.exists():
        shutil.rmtree(lua_directory)
    with tarfile.open(archive) as tar:
        tar.extractall(CACHE, filter="data")
    lua = CACHE / f"lua-{lock['lua']['version']}" / "src"
    objects = CACHE / "objects"
    objects.mkdir(exist_ok=True)
    generate_card_fixture(ROOT, objects / "reference_cards.h")
    # Upstream premake/lua.lua compiles Lua as C++, matching interpreter.h linkage.
    sources = [("g++", source) for source in sorted(lua.glob("*.c")) if source.name not in ("lua.c", "luac.c", "linit.c", "onelua.c")]
    sources += [("g++", source) for source in sorted(core_source.glob("*.cpp"))]
    sources += [("g++", ROOT / "Tools/ocg/probe.cpp")]

    def compile_one(item: tuple[str, Path]) -> Path:
        compiler, source = item
        obj = objects / (source.name + ".o")
        flags = ["-std=c++14"] if compiler == "g++" else ["-std=c99"]
        run(compiler, *flags, "-O2", "-DLUA_USE_LINUX", f'-DOCG_REVISION="{revision}"',
            "-I", lua, "-I", core_source, "-I", objects, "-c", source, "-o", obj)
        return obj

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        compiled = list(pool.map(compile_one, sources))
    target = ROOT / "Tools/ocg/bin/ocg_probe"
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_suffix(".pending")
    run("g++", *compiled, "-ldl", "-lm", "-o", pending)
    # Smoke-test before replacing a previously usable binary.
    result = subprocess.run([str(pending), "--seed", "42"], check=True, capture_output=True, text=True, timeout=15)
    if json.loads(result.stdout).get("status") != "ok":
        raise RuntimeError("native diagnostic did not pass")
    pending.replace(target)
    print(f"Built and verified {target}\nCore revision: {revision}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
        print(f"OCG BUILD FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
