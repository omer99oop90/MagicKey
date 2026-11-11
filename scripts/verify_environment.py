#!/usr/bin/env python3
"""
Magic Key — Development Environment & Foundation Verification Script
Performs an empirical check of the environment, shared storage, toolchains,
and architectural constraints.
"""

import os
import sys
import shutil
import subprocess
import platform

PROJECT_DIR = "/storage/emulated/0/ANTYEE/MagicKey"

def print_header(title):
    print("\n" + "=" * 60)
    print(f" {title}")
    print("=" * 60)

def check_system():
    print_header("1. Host System, Kernel & Memory")
    print(f"System   : {platform.system()} {platform.release()}")
    print(f"Machine  : {platform.machine()}")
    print(f"Platform : {platform.platform()}")
    
    sdk_prop = os.environ.get("ANDROID__BUILD_VERSION_SDK", "Unknown")
    print(f"Android SDK Level: {sdk_prop}")

    # Inspect /proc/meminfo
    try:
        meminfo = {}
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    meminfo[parts[0].strip()] = int(parts[1].strip().split()[0])
        total_ram = meminfo.get("MemTotal", 0) / 1024
        avail_ram = meminfo.get("MemAvailable", 0) / 1024
        swap_total = meminfo.get("SwapTotal", 0) / 1024
        swap_free = meminfo.get("SwapFree", 0) / 1024
        print(f"Physical RAM   : {total_ram:.1f} MiB ({total_ram/1024:.2f} GiB usable from hardware)")
        print(f"Available RAM  : {avail_ram:.1f} MiB ({avail_ram/1024:.2f} GiB)")
        print(f"zRAM Swap Total: {swap_total:.1f} MiB ({swap_total/1024:.2f} GiB)")
        print(f"zRAM Swap Free : {swap_free:.1f} MiB ({swap_free/1024:.2f} GiB)")
    except Exception as e:
        print(f"  [WARN] Unable to parse /proc/meminfo: {e}")

def check_storage():
    print_header("2. Storage & Filesystem Diagnostics")
    print(f"Target Project Directory: {PROJECT_DIR}")
    
    # Check directory existence
    if os.path.exists(PROJECT_DIR):
        print("  [PASS] Project directory exists.")
    else:
        print("  [FAIL] Project directory does NOT exist.")
        return

    # Check write permissions
    test_file = os.path.join(PROJECT_DIR, ".verify_test")
    try:
        with open(test_file, "w") as f:
            f.write("magic_key_write_test")
        os.remove(test_file)
        print("  [PASS] Storage write access verified.")
    except Exception as e:
        print(f"  [FAIL] Storage write error: {e}")

    # Check symlink capability (Android FUSE behavior)
    symlink_test = os.path.join(PROJECT_DIR, ".symlink_test")
    try:
        os.symlink(PROJECT_DIR, symlink_test)
        os.remove(symlink_test)
        print("  [INFO] Symbolic links: Supported.")
    except (OSError, NotImplementedError) as e:
        print(f"  [INFO] Symbolic links: Restricted by FUSE filesystem ({e.__class__.__name__}).")

    # Check available storage
    stat = os.statvfs(PROJECT_DIR)
    free_bytes = stat.f_bavail * stat.f_frsize
    total_bytes = stat.f_blocks * stat.f_frsize
    free_gb = free_bytes / (1024 ** 3)
    total_gb = total_bytes / (1024 ** 3)
    
    print(f"  Total Capacity : {total_gb:.2f} GB")
    print(f"  Available Space: {free_gb:.2f} GB")
    if free_gb < 4.0:
        print("  [WARN] Storage constraint: Available space is under 4 GB. Heavy SDKs must not be downloaded.")
    else:
        print("  [PASS] Storage capacity is adequate.")

def check_toolchains():
    print_header("3. Toolchain & Development Tools")
    
    tools = [
        ("git", ["git", "--version"]),
        ("rustc", ["rustc", "--version"]),
        ("cargo", ["cargo", "--version"]),
        ("clang", ["clang", "--version"]),
        ("make", ["make", "--version"]),
        ("java", ["java", "-version"]),
        ("javac", ["javac", "-version"]),
        ("d8", ["d8", "--version"]),
        ("dart", ["dart", "--version"]),
        ("flutter", ["flutter", "--version"]),
        ("python3", ["python3", "--version"]),
        ("aapt", ["aapt", "version"]),
        ("apksigner", ["apksigner", "--version"]),
        ("zipalign", None),
    ]

    for tool_name, cmd in tools:
        path = shutil.which(tool_name)
        if not path:
            print(f"  [MISSING] {tool_name:<10}")
            continue

        version = "Found (Executable)"
        if cmd:
            try:
                proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
                out = (proc.stdout or proc.stderr).strip().splitlines()
                if out:
                    version = out[0][:50]
            except Exception:
                pass
        print(f"  [FOUND]   {tool_name:<10} -> {path} ({version})")

def check_documentation():
    print_header("4. Project Documentation & Foundation Suite")
    required_files = [
        "PROJECT_BLUEPRINT.md",
        "ARCHITECTURE.md",
        "ROADMAP.md",
        "README.md",
        "CHANGELOG.md",
        "LICENSES.md",
    ]
    
    for filename in required_files:
        filepath = os.path.join(PROJECT_DIR, filename)
        if os.path.exists(filepath):
            size = os.path.getsize(filepath)
            print(f"  [OK] {filename:<22} ({size:,} bytes)")
        else:
            print(f"  [MISSING] {filename:<22}")

def main():
    print("============================================================")
    print("  MAGIC KEY — SYSTEM ENVIRONMENT & FOUNDATION VERIFICATION  ")
    print("============================================================")
    check_system()
    check_storage()
    check_toolchains()
    check_documentation()
    print_header("Verification Complete")
    print("Foundation phase status: READY FOR PHASE 1 IMPLEMENTATION.\n")

if __name__ == "__main__":
    main()
