#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright © 2026 Hazen Studio
"""
bundle-dylibs.py: Make MacLC.app self-contained by bundling Homebrew dylibs.
Usage: bundle-dylibs.py [--verify-only] [--list] path/to/MacLC.app
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
from typing import Optional


def is_macho(path: str) -> bool:
    """Check if path is a regular Mach-O file (skipping symlinks)."""
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as f:
            header = f.read(8)
        if len(header) < 4:
            return False
        magic = header[:4]
        # 64-bit Mach-O (feedfacf / cffaedfe)
        if magic in (b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe"):
            return True
        # 32-bit Mach-O (feedface / cefaedfe)
        if magic in (b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe"):
            return True
        # Fat binary (cafebabe / bebafeca)
        if magic in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
            if len(header) >= 8:
                if magic == b"\xca\xfe\xba\xbe":
                    nfat = struct.unpack(">I", header[4:8])[0]
                else:
                    nfat = struct.unpack("<I", header[4:8])[0]
                # Fat binary only if nfat_arch < 30 (to distinguish from Java .class)
                return nfat < 30
            return False
    except Exception:
        return False
    return False


def find_macho_files(bundle_path: str) -> list[str]:
    """Find all regular Mach-O files under Contents/."""
    contents_dir = os.path.join(bundle_path, "Contents")
    macho_files = []
    for root, _, files in os.walk(contents_dir):
        for f in files:
            p = os.path.join(root, f)
            if is_macho(p):
                macho_files.append(p)
    macho_files.sort()
    return macho_files


def get_install_id(path: str) -> str:
    """Read install id (LC_ID_DYLIB) using otool -D."""
    try:
        res = subprocess.run(
            ["otool", "-D", path],
            capture_output=True,
            text=True,
            errors="replace",
            check=True,
        )
    except subprocess.CalledProcessError:
        return ""
    lines = [line.strip() for line in res.stdout.splitlines() if line.strip()]
    for line in lines[1:]:
        if not line.endswith(":"):
            return line
    return ""


def get_deps(path: str, install_id: str = "") -> list[str]:
    """Read dependencies using otool -L, dropping the file's own install id."""
    try:
        res = subprocess.run(
            ["otool", "-L", path],
            capture_output=True,
            text=True,
            errors="replace",
            check=True,
        )
    except subprocess.CalledProcessError:
        return []
    deps = []
    for line in res.stdout.splitlines():
        line = line.strip()
        if not line or line.endswith(":"):
            continue
        m = re.match(r"^(.*?)\s+\(compatibility version", line)
        if m:
            dep = m.group(1).strip()
            if install_id and dep == install_id:
                continue
            deps.append(dep)
    return deps


def get_rpaths_and_weak(path: str) -> tuple[list[str], set[str]]:
    """Read LC_RPATH entries and LC_LOAD_WEAK_DYLIB deps using otool -l."""
    try:
        res = subprocess.run(
            ["otool", "-l", path],
            capture_output=True,
            text=True,
            errors="replace",
            check=True,
        )
    except subprocess.CalledProcessError:
        return [], set()
    rpaths = []
    weak_deps = set()
    current_cmd = None
    for line in res.stdout.splitlines():
        line = line.strip()
        if line.startswith("cmd "):
            parts = line.split()
            if len(parts) > 1:
                current_cmd = parts[1]
        elif current_cmd == "LC_RPATH" and line.startswith("path "):
            m = re.match(r"^path\s+(.*?)\s+\(offset\s+\d+\)$", line)
            if m:
                rpaths.append(m.group(1))
        elif current_cmd == "LC_LOAD_WEAK_DYLIB" and line.startswith("name "):
            m = re.match(r"^name\s+(.*?)\s+\(offset\s+\d+\)$", line)
            if m:
                weak_deps.add(m.group(1))
    return rpaths, weak_deps


def is_system_path(path: str) -> bool:
    """Return True if path is a macOS system path."""
    return path.startswith("/usr/lib/") or path.startswith("/System/")


def is_inside(path: str, parent: str) -> bool:
    """Return True if path is inside parent directory."""
    try:
        return (
            os.path.commonpath([os.path.abspath(parent), os.path.abspath(path)])
            == os.path.abspath(parent)
        )
    except ValueError:
        return False


def resolve_dependency(
    dep_str: str,
    orig_dir: str,
    file_rpaths: list[str],
    bundle_path: str,
    macos_path: str,
    frameworks_path: str,
    main_rpaths: list[str],
) -> str | None:
    """Resolve dep_str to a filesystem path if possible."""
    if is_system_path(dep_str):
        return dep_str

    if dep_str.startswith("@rpath/"):
        sub = dep_str[len("@rpath/") :]
        # 1. Try file's own LC_RPATHs
        for r in file_rpaths:
            exp = r.replace("@loader_path", orig_dir).replace("@executable_path", macos_path)
            cand = os.path.normpath(os.path.join(exp, sub))
            if os.path.exists(cand):
                return cand
        # 2. Try main executable's LC_RPATHs
        for r in main_rpaths:
            cand = os.path.normpath(os.path.join(r, sub))
            if os.path.exists(cand):
                return cand
        # 3. Try Contents/Frameworks/
        cand = os.path.normpath(os.path.join(frameworks_path, sub))
        if os.path.exists(cand):
            return cand
        return None

    if dep_str.startswith("@loader_path/"):
        sub = dep_str[len("@loader_path/") :]
        cand = os.path.normpath(os.path.join(orig_dir, sub))
        if os.path.exists(cand):
            return cand
        return None

    if dep_str.startswith("@executable_path/"):
        sub = dep_str[len("@executable_path/") :]
        cand = os.path.normpath(os.path.join(macos_path, sub))
        if os.path.exists(cand):
            return cand
        return None

    if dep_str.startswith("/"):
        cand = os.path.normpath(dep_str)
        if os.path.exists(cand):
            return cand
        return None

    return None


def verify_bundle(bundle_path: str) -> bool:
    """
    Verification pass:
    Every dep must be system or resolve to an existing file inside the bundle
    using only in-bundle rpaths (image's own rpaths plus main executable's).
    No LC_RPATH may point outside the bundle.
    """
    contents_path = os.path.join(bundle_path, "Contents")
    macos_path = os.path.join(contents_path, "MacOS")
    main_executable = os.path.join(macos_path, "MacLC")

    # Main executable's in-bundle rpaths
    main_rpaths = []
    if os.path.isfile(main_executable):
        raw_rpaths, _ = get_rpaths_and_weak(main_executable)
        for r in raw_rpaths:
            exp = r.replace("@loader_path", macos_path).replace("@executable_path", macos_path)
            norm = os.path.normpath(exp)
            if is_inside(norm, bundle_path) and os.path.isdir(norm):
                main_rpaths.append(norm)

    all_files = find_macho_files(bundle_path)
    violations = []

    for file_path in all_files:
        file_dir = os.path.dirname(file_path)
        rpaths, _ = get_rpaths_and_weak(file_path)

        # Check LC_RPATHs: none may point outside bundle
        for r in rpaths:
            exp = r.replace("@loader_path", file_dir).replace("@executable_path", macos_path)
            norm = os.path.normpath(exp)
            if not is_inside(norm, bundle_path):
                violations.append(
                    f"Error: {file_path} LC_RPATH '{r}' points outside bundle ({norm})"
                )

        # Check dependencies
        inst_id = get_install_id(file_path)
        deps = get_deps(file_path, inst_id)
        for dep in deps:
            if is_system_path(dep):
                continue
            if dep.startswith("@loader_path/"):
                rel = dep[len("@loader_path/") :]
                cand = os.path.normpath(os.path.join(file_dir, rel))
                if not (os.path.exists(cand) and is_inside(cand, bundle_path)):
                    violations.append(
                        f"Error: {file_path} dependency '{dep}' missing inside bundle ({cand})"
                    )
            elif dep.startswith("@executable_path/"):
                rel = dep[len("@executable_path/") :]
                cand = os.path.normpath(os.path.join(macos_path, rel))
                if not (os.path.exists(cand) and is_inside(cand, bundle_path)):
                    violations.append(
                        f"Error: {file_path} dependency '{dep}' missing inside bundle ({cand})"
                    )
            elif dep.startswith("@rpath/"):
                sub = dep[len("@rpath/") :]
                found = False
                # Try file's own in-bundle rpaths
                for r in rpaths:
                    exp = r.replace("@loader_path", file_dir).replace("@executable_path", macos_path)
                    norm = os.path.normpath(exp)
                    if is_inside(norm, bundle_path):
                        cand = os.path.normpath(os.path.join(norm, sub))
                        if os.path.exists(cand) and is_inside(cand, bundle_path):
                            found = True
                            break
                if not found:
                    # Try main executable's in-bundle rpaths
                    for r in main_rpaths:
                        cand = os.path.normpath(os.path.join(r, sub))
                        if os.path.exists(cand) and is_inside(cand, bundle_path):
                            found = True
                            break
                if not found:
                    violations.append(
                        f"Error: {file_path} dependency '{dep}' cannot be resolved via in-bundle rpaths"
                    )
            elif dep.startswith("/"):
                if not (os.path.exists(dep) and is_inside(dep, bundle_path)):
                    violations.append(
                        f"Error: {file_path} absolute dependency '{dep}' points outside bundle"
                    )
            else:
                violations.append(
                    f"Error: {file_path} dependency '{dep}' is unresolved or unhandled"
                )

    if violations:
        for v in violations:
            sys.stderr.write(f"{v}\n")
        return False
    return True


def copy_licenses(
    bundle_path: str,
    formula_info: dict[str, dict],
) -> None:
    """Copy license files and generate README.txt."""
    if not formula_info:
        return

    lic_base_dir = os.path.join(bundle_path, "Contents/Resources/Licenses")
    patterns = ("COPYING*", "LICENSE*", "LICENCE*", "COPYRIGHT*", "NOTICE*")

    for formula, info in formula_info.items():
        keg_root = info["keg_root"]
        formula_lic_dir = os.path.join(lic_base_dir, formula)
        os.makedirs(formula_lic_dir, exist_ok=True)
        if os.path.isdir(keg_root):
            for item in os.listdir(keg_root):
                src_file = os.path.join(keg_root, item)
                if os.path.isfile(src_file) and not os.path.islink(src_file):
                    if any(fnmatch.fnmatch(item.upper(), p) for p in patterns):
                        shutil.copy2(src_file, os.path.join(formula_lic_dir, item))

    # Fetch brew info
    formula_names = sorted(formula_info.keys())
    brew_map = {}
    try:
        proc = subprocess.run(
            ["brew", "info", "--json=v2", "--formula"] + formula_names,
            capture_output=True,
            text=True,
            check=True,
        )
        bdata = json.loads(proc.stdout)
        for f in bdata.get("formulae", []):
            name = f.get("name")
            if name:
                brew_map[name] = f
            for alias in f.get("aliases", []):
                brew_map[alias] = f
    except Exception as e:
        sys.stderr.write(f"Warning: brew info failed: {e}\n")

    readme_lines = [
        "These are unmodified Homebrew builds of third-party libraries, each under its own licence; sources at the URLs listed.",
        "",
    ]
    for formula in formula_names:
        info = formula_info[formula]
        version = info["version"]
        dylibs = sorted(info["dylibs"])
        bentry = brew_map.get(formula, {})
        spdx = bentry.get("license") or "Unknown"
        homepage = bentry.get("homepage") or "Unknown"
        source_url = bentry.get("urls", {}).get("stable", {}).get("url") or "Unknown"

        readme_lines.append("-" * 72)
        readme_lines.append(f"Formula:     {formula}")
        readme_lines.append(f"Version:     {version}")
        readme_lines.append(f"License:     {spdx}")
        readme_lines.append(f"Homepage:    {homepage}")
        readme_lines.append(f"Source URL:  {source_url}")
        readme_lines.append(f"Bundled:     {', '.join(dylibs)}")

    readme_lines.append("-" * 72)
    readme_lines.append("")

    readme_path = os.path.join(lic_base_dir, "README.txt")
    os.makedirs(os.path.dirname(readme_path), exist_ok=True)
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write("\n".join(readme_lines))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Make MacLC.app self-contained by bundling Homebrew dylibs."
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Run verification pass only",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Print external closure and exit without modifying",
    )
    parser.add_argument("bundle", help="Path to MacLC.app")
    args = parser.parse_args()

    bundle_path = os.path.abspath(args.bundle)
    if not os.path.isdir(bundle_path):
        sys.stderr.write(f"Error: Bundle directory not found: {bundle_path}\n")
        sys.exit(1)

    contents_path = os.path.join(bundle_path, "Contents")
    macos_path = os.path.join(contents_path, "MacOS")
    frameworks_path = os.path.join(contents_path, "Frameworks")
    main_executable = os.path.join(macos_path, "MacLC")

    if args.verify_only:
        ok = verify_bundle(bundle_path)
        if not ok:
            sys.exit(1)
        print("Verification succeeded: bundle is self-contained.")
        sys.exit(0)

    # Main executable's rpaths for resolving @rpath
    main_rpaths = []
    if os.path.isfile(main_executable):
        raw_rpaths, _ = get_rpaths_and_weak(main_executable)
        for r in raw_rpaths:
            exp = r.replace("@loader_path", macos_path).replace("@executable_path", macos_path)
            norm = os.path.normpath(exp)
            if is_inside(norm, bundle_path) and os.path.isdir(norm):
                main_rpaths.append(norm)

    # Initial scan of app files
    initial_macho_files = find_macho_files(bundle_path)
    app_files = set(initial_macho_files)

    preexisting_framework_basenames = set()
    if os.path.isdir(frameworks_path):
        preexisting_framework_basenames = set(os.listdir(frameworks_path))

    # Data structures for dependency resolution and copying
    # binary_info: file_target_path -> dict(orig_path, orig_dir, deps, rpaths, weak_deps, is_copied)
    binary_info = {}
    dep_to_bundled = {}  # (referencing_target_path, dep_str) -> bundled_target_path

    # External closure tracking
    # realpath -> (target_basename, resolved_path)
    realpath_to_target_basename = {}
    target_basename_to_realpath = {}

    # Queue of files to analyze: list of (file_key, orig_path, orig_dir, is_copied)
    queue = []
    for f in initial_macho_files:
        queue.append((f, f, os.path.dirname(f), False))

    scanned_count = 0

    while queue:
        file_target_path, orig_path, orig_dir, is_copied = queue.pop(0)
        scanned_count += 1

        install_id = get_install_id(orig_path)
        deps = get_deps(orig_path, install_id)
        rpaths, weak_deps = get_rpaths_and_weak(orig_path)

        binary_info[file_target_path] = {
            "orig_path": orig_path,
            "orig_dir": orig_dir,
            "deps": deps,
            "rpaths": rpaths,
            "weak_deps": weak_deps,
            "is_copied": is_copied,
        }

        for dep_str in deps:
            if is_system_path(dep_str):
                continue

            resolved = resolve_dependency(
                dep_str,
                orig_dir,
                rpaths,
                bundle_path,
                macos_path,
                frameworks_path,
                main_rpaths,
            )

            if resolved is None:
                if dep_str in weak_deps:
                    continue
                sys.stderr.write(
                    f"Error: Missing external dependency '{dep_str}' referenced by {orig_path}\n"
                )
                sys.exit(1)

            if is_inside(resolved, bundle_path):
                dep_to_bundled[(file_target_path, dep_str)] = resolved
            else:
                # External dependency
                dep_base = os.path.basename(resolved)
                if dep_base in preexisting_framework_basenames:
                    # Reuse existing in-bundle file
                    bundled_file = os.path.join(frameworks_path, dep_base)
                    dep_to_bundled[(file_target_path, dep_str)] = bundled_file
                else:
                    ext_realpath = os.path.realpath(resolved)
                    if not os.path.exists(ext_realpath):
                        if dep_str in weak_deps:
                            continue
                        sys.stderr.write(
                            f"Error: Missing external dependency '{dep_str}' (realpath: {ext_realpath}) referenced by {orig_path}\n"
                        )
                        sys.exit(1)

                    if ext_realpath not in realpath_to_target_basename:
                        lib_id = get_install_id(ext_realpath)
                        if lib_id:
                            target_base = os.path.basename(lib_id)
                        else:
                            target_base = os.path.basename(ext_realpath)

                        if target_base in target_basename_to_realpath:
                            existing_real = target_basename_to_realpath[target_base]
                            if existing_real != ext_realpath:
                                sys.stderr.write(
                                    f"Error: Two different files with the same basename '{target_base}': '{existing_real}' and '{ext_realpath}'\n"
                                )
                                sys.exit(1)

                        target_basename_to_realpath[target_base] = ext_realpath
                        realpath_to_target_basename[ext_realpath] = target_base

                        new_bundled_path = os.path.join(frameworks_path, target_base)
                        # Recurse into copied lib
                        queue.append(
                            (
                                new_bundled_path,
                                ext_realpath,
                                os.path.dirname(ext_realpath),
                                True,
                            )
                        )

                    target_base = realpath_to_target_basename[ext_realpath]
                    dep_to_bundled[(file_target_path, dep_str)] = os.path.join(
                        frameworks_path, target_base
                    )

    if args.list:
        for realpath in sorted(realpath_to_target_basename.keys()):
            print(realpath)
        sys.exit(0)

    # Step 4: Copy external dylibs into Contents/Frameworks
    os.makedirs(frameworks_path, exist_ok=True)
    copied_file_paths = []
    total_bytes = 0

    for ext_realpath, target_base in realpath_to_target_basename.items():
        target_path = os.path.join(frameworks_path, target_base)
        shutil.copy2(ext_realpath, target_path)
        # chmod u+w
        cur_mode = os.stat(target_path).st_mode
        os.chmod(target_path, cur_mode | stat.S_IWUSR | stat.S_IRUSR | stat.S_IXUSR)
        copied_file_paths.append(target_path)
        total_bytes += os.path.getsize(target_path)

    # Step 5: Rewrite references, install names, and LC_RPATHs
    modified_files = set()

    for file_target_path, info in binary_info.items():
        flags = []
        is_copied = info["is_copied"]

        if is_copied:
            # Copied libs: -id @rpath/<name> and delete all their LC_RPATH entries
            flags.extend(["-id", f"@rpath/{os.path.basename(file_target_path)}"])
            for r in info["rpaths"]:
                flags.extend(["-delete_rpath", r])
        else:
            # App files: delete every LC_RPATH that points outside the bundle
            for r in info["rpaths"]:
                if r.startswith("/"):
                    if not is_inside(r, bundle_path):
                        flags.extend(["-delete_rpath", r])
                else:
                    exp = r.replace("@loader_path", info["orig_dir"]).replace(
                        "@executable_path", macos_path
                    )
                    norm = os.path.normpath(exp)
                    if not is_inside(norm, bundle_path):
                        flags.extend(["-delete_rpath", r])

        # Rewriting dependencies to @loader_path/<relative>
        changes = {}
        for dep_str in info["deps"]:
            if is_system_path(dep_str):
                continue
            key = (file_target_path, dep_str)
            if key in dep_to_bundled:
                bundled_target = dep_to_bundled[key]
                rel = os.path.relpath(bundled_target, os.path.dirname(file_target_path))
                new_ref = f"@loader_path/{rel}"
                if dep_str != new_ref:
                    changes[dep_str] = new_ref

        for old_ref, new_ref in changes.items():
            flags.extend(["-change", old_ref, new_ref])

        if flags:
            # Ensure file is writable
            cur_mode = os.stat(file_target_path).st_mode
            if not (cur_mode & stat.S_IWUSR):
                os.chmod(file_target_path, cur_mode | stat.S_IWUSR)

            res = subprocess.run(
                ["install_name_tool"] + flags + [file_target_path],
                capture_output=True,
                text=True,
            )
            if res.returncode != 0:
                sys.stderr.write(
                    f"install_name_tool failed on {file_target_path}:\n{res.stderr}\n"
                )
                sys.exit(1)
            modified_files.add(file_target_path)

    # Step 6: Re-sign modified files ad hoc
    for f in modified_files | set(copied_file_paths):
        res = subprocess.run(
            ["codesign", "--force", "--sign", "-", f],
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            sys.stderr.write(f"codesign failed on {f}:\n{res.stderr}\n")
            sys.exit(1)

    # Step 7: Licenses
    formula_info = {}
    cellar_re = re.compile(r"^/opt/homebrew/Cellar/([^/]+)/([^/]+)/")
    for ext_realpath, target_base in realpath_to_target_basename.items():
        m = cellar_re.match(ext_realpath)
        if m:
            formula = m.group(1)
            version = m.group(2)
            keg_root = f"/opt/homebrew/Cellar/{formula}/{version}"
            if formula not in formula_info:
                formula_info[formula] = {
                    "version": version,
                    "keg_root": keg_root,
                    "dylibs": set(),
                }
            formula_info[formula]["dylibs"].add(target_base)

    copy_licenses(bundle_path, formula_info)

    # Step 8: Verification pass
    ok = verify_bundle(bundle_path)
    if not ok:
        sys.exit(1)

    # Step 9: Summary
    total_mb = total_bytes / (1024 * 1024)
    print(
        f"Summary: {scanned_count} files scanned, {len(copied_file_paths)} libs copied ({total_mb:.1f} MB), {len(formula_info)} formulae."
    )


if __name__ == "__main__":
    main()
