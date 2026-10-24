#!/usr/bin/env python3
"""Compatibility entry point using the corrected explicit-GPU-reference reader.

Usage remains BUNDLE_ROOT OUTPUT_DIRECTORY. Output now follows the canonical
material shader manifest/program filenames and includes all referenced stages.
Parameter blocks must never be interpreted as shader programs.
"""
from pathlib import Path
import subprocess
import sys

root,output=map(Path,sys.argv[1:3])
research=Path(__file__).resolve().parent.parent/"Research/2026-10-23"
subprocess.run([sys.executable,str(Path(__file__).with_name("extract-material-shader.py")),
                str(root),str(research/"unity-bundle-directory-index.json"),
                str(research/"grass-material-data.json"),str(output)],check=True)
