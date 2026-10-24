#!/usr/bin/env python3
"""Build a freestanding offline shader inspector using local LLVM/Wine headers.

Usage: build-dxbc-inspector.py WINE_ROOT LLVM_BIN LLD_BIN OUTPUT_DIRECTORY
Wine's bundled winegcc cannot link here because its developer import libraries
and original build-machine paths are absent. Generate only the needed imports.
"""
from pathlib import Path
import subprocess
import sys

wine, llvm, lld, output = map(Path, sys.argv[1:5])
output.mkdir(parents=True, exist_ok=True)
imports = {
    "kernel32": ["GetCommandLineW", "LoadLibraryW", "GetProcAddress", "ExitProcess",
                 "CreateFileW", "GetFileSizeEx", "HeapAlloc", "HeapFree", "GetProcessHeap",
                 "ReadFile", "WriteFile", "CloseHandle"],
    "shell32": ["CommandLineToArgvW"],
}
libraries = []
for name, functions in imports.items():
    definition = output / f"{name}.def"
    definition.write_text(f"LIBRARY {name}.dll\nEXPORTS\n" + "\n".join(functions) + "\n")
    library = output / f"{name}.lib"
    subprocess.run([str(llvm / "llvm-dlltool"), "-m", "i386:x86-64", "-d", str(definition),
                    "-l", str(library)], check=True)
    libraries.append(str(library))
source = Path(__file__).with_name("disassemble-dxbc.c")
obj = output / "disassemble-dxbc.obj"
subprocess.run([str(llvm / "clang"), "--target=x86_64-windows-msvc", "-ffreestanding",
                "-fno-stack-protector", "-isystem", str(wine / "include/wine/windows"),
                "-isystem", str(wine / "include/wine/msvcrt"), "-c", str(source), "-o", str(obj)], check=True)
program = output / "aniimo-dxbc-disassemble.exe"
subprocess.run([str(lld / "lld-link"), "/entry:mainCRTStartup", "/subsystem:console", "/nodefaultlib",
                "/out:" + str(program), str(obj), *libraries], check=True)
print(program)
