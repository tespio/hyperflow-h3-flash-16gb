# Starts the ComfyUI server with disk-backed weight streaming.
#
# --fast-disk is the important flag on a 32 GB machine: ComfyUI streams offloaded
# weights out of the OS file page cache instead of copying them into pinned RAM,
# which keeps anonymous RSS around 8-16 GB.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'ComfyUI')

$env:PYTHONUNBUFFERED = '1'
.\.venv\Scripts\python.exe main.py --fast-disk
