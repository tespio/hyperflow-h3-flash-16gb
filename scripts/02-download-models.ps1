# Runs from the repository root.
# Downloads the Q4_K_M transformer, the nvfp4 text encoder, and both VAEs (~28.5 GB).
#
# Needs the `hf` CLI:  pip install -U huggingface_hub

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$models = Join-Path $root 'ComfyUI\models'
New-Item -ItemType Directory -Force -Path `
    (Join-Path $models 'diffusion_models'), `
    (Join-Path $models 'text_encoders'), `
    (Join-Path $models 'vae'), `
    (Join-Path $root 'dl') | Out-Null

# 8.4 GB - the compressed 13.7B transformer
hf download VideoRebirthAI/hyperflow-h3-flash `
    fl2va_gguf/minimax_h3_fl2va_hyperflow_flash_14b-Q4_K_M.gguf `
    --local-dir (Join-Path $root 'dl')

# 14.6 GB text encoder + 4.9 GB video VAE + 0.6 GB audio VAE
hf download Comfy-Org/MiniMax-H3 `
    text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors `
    vae/minimax_h3_video_vae_fp16.safetensors `
    vae/minimax_h3_audio_vae_fp32.safetensors `
    --local-dir (Join-Path $root 'dl2')

# ComfyUI wants them flat in the models directories, not in the repo subfolders.
Move-Item (Join-Path $root 'dl\fl2va_gguf\*.gguf')             (Join-Path $models 'diffusion_models') -Force
Move-Item (Join-Path $root 'dl2\text_encoders\*.safetensors')  (Join-Path $models 'text_encoders')    -Force
Move-Item (Join-Path $root 'dl2\vae\*.safetensors')            (Join-Path $models 'vae')              -Force

Write-Host "`nWeights in place:"
Get-ChildItem $models -Recurse -File -Filter *.safetensors |
    Select-Object @{n='GB';e={[math]::Round($_.Length/1GB,2)}},Name
Get-ChildItem $models -Recurse -File -Filter *.gguf |
    Select-Object @{n='GB';e={[math]::Round($_.Length/1GB,2)}},Name
