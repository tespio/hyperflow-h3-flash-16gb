# Submits a text-to-video+audio job to a running ComfyUI server and reports timing.
#
#   .\scripts\generate.ps1 -Prompt "A street musician plays..." -Length 124
#   .\scripts\generate.ps1 -Prompt "..." -Width 960 -Height 544 -Length 124 -Steps 4
#
# -ComfyUI defaults to a ComfyUI checkout next to this repository, which is what
# 01-install-comfyui.ps1 creates. Point it elsewhere if yours lives somewhere else.

param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [int]$Width = 1344,
    [int]$Height = 768,
    [int]$Length = 124,
    [ValidateSet(4, 6, 8)][int]$Steps = 6,
    [int]$Seed = 42,
    [int]$TimeoutMin = 60,
    [string]$ComfyUI = (Join-Path (Split-Path -Parent $PSScriptRoot) 'ComfyUI'),
    [string]$Server = 'http://127.0.0.1:8188'
)

$ErrorActionPreference = 'Stop'

$template = Join-Path $ComfyUI 'custom_nodes\ComfyUI-HyperFlow-Flash\example_workflows\api\hyperflow_t2v_api.json'
if (-not (Test-Path $template)) {
    throw "Workflow template not found: $template`nPass -ComfyUI <path to your ComfyUI checkout>."
}

$wf = Get-Content $template -Raw | ConvertFrom-Json

foreach ($k in $wf.PSObject.Properties.Name) {
    $node = $wf.$k
    switch ($node.class_type) {
        'MiniMaxH3ImageToVideo' {
            $node.inputs.prompt = $Prompt
            $node.inputs.width  = $Width
            $node.inputs.height = $Height
            $node.inputs.length = $Length
        }
        'HyperFlowSigmas' { $node.inputs.steps = $Steps }
        'RandomNoise'     { $node.inputs.noise_seed = $Seed }
    }
}

$body = @{ prompt = $wf; client_id = 'hyperflow-cli' } | ConvertTo-Json -Depth 40
$queued = Invoke-RestMethod -Uri "$Server/prompt" -Method Post -Body $body -ContentType 'application/json'
$id = $queued.prompt_id
Write-Host ("queued {0}  {1}x{2} {3}f  {4} steps" -f $id, $Width, $Height, $Length, $Steps)

$t0 = Get-Date
$deadline = $t0.AddMinutes($TimeoutMin)
$peakVram = 0

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5

    $vram = [int]((nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits) -replace '\s', '')
    if ($vram -gt $peakVram) { $peakVram = $vram }

    $entry = (Invoke-RestMethod -Uri "$Server/history/$id").$id
    if (-not $entry) {
        Write-Host ("[{0,4}s] {1} MiB VRAM" -f [int]((Get-Date) - $t0).TotalSeconds, $vram)
        continue
    }

    $elapsed = (Get-Date) - $t0

    if ($entry.status.status_str -eq 'error') {
        Write-Host "FAILED after $([int]$elapsed.TotalSeconds)s"
        foreach ($m in $entry.status.messages) { $m | ConvertTo-Json -Depth 10 -Compress }
        exit 1
    }

    foreach ($nodeId in $entry.outputs.PSObject.Properties.Name) {
        foreach ($v in $entry.outputs.$nodeId.videos) {
            Write-Host ("output : output\{0}\{1}" -f $v.subfolder, $v.filename)
        }
    }
    Write-Host ("time   : {0:N1} s" -f $elapsed.TotalSeconds)
    Write-Host ("peak   : {0:N0} MiB VRAM" -f $peakVram)
    exit 0
}

Write-Host "TIMEOUT after $TimeoutMin min"
exit 2
