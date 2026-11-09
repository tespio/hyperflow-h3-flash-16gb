# Creates a ComfyUI checkout, a virtualenv that reuses the machine's existing
# PyTorch, and both custom nodes.
#
# If you do not already have a CUDA PyTorch, see README.md > "Clean PyTorch install".

param(
    [string]$ComfyUI = (Join-Path (Split-Path -Parent $PSScriptRoot) 'ComfyUI')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ComfyUI)) {
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git $ComfyUI
}
Set-Location $ComfyUI

if (-not (Test-Path '.venv')) {
    python -m venv --system-site-packages .venv
}

# Keep the existing torch; requirements.txt would otherwise let pip replace it.
'torch==2.14.1' | Set-Content constraints.txt

.\.venv\Scripts\python.exe -m pip install --upgrade pip --quiet
.\.venv\Scripts\python.exe -m pip install -r requirements.txt -c constraints.txt --no-warn-script-location

Set-Location custom_nodes
if (-not (Test-Path 'ComfyUI-GGUF')) {
    git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git
}
if (-not (Test-Path 'ComfyUI-HyperFlow-Flash')) {
    git clone --depth 1 https://github.com/Video-Rebirth/ComfyUI-HyperFlow-Flash.git
}
Set-Location ..

.\.venv\Scripts\python.exe -m pip install gguf --quiet

.\.venv\Scripts\python.exe -c "import torch; print('torch', torch.__version__, '| cuda available:', torch.cuda.is_available())"
Write-Host "`nInstall complete in $ComfyUI"
Write-Host "Next: scripts\02-download-models.ps1"
