# HyperFlow H3 Flash on a 16 GB GPU

Running a **13.7B joint video + audio diffusion model** locally on an RTX 4070 Ti Super.

The model's authors publish benchmarks for 24 GB and 32 GB cards and note that
*"16 GB GPUs are not measured yet."* This repo fills in that row: what it takes to get
[HyperFlow H3 Flash](https://github.com/Video-Rebirth/hyperflow-h3-flash) running on a
16 GB consumer card, in full, with the exact commands and what they actually cost.

**Status: working.** 5.2 s clips at the model's native 1344×768, with a 32 kHz stereo
soundtrack, in about 4.5 minutes — a 960×544 draft in 91 seconds, and a full 15 s clip in
37 minutes. No patched kernels, no cloud, no quantization beyond the Q4_K_M GGUF the
authors ship.

![frame from a generated clip](media/5s-1344x768-frame.png)

---

## Hardware

| | |
|---|---|
| GPU | NVIDIA RTX 4070 Ti SUPER, 16 GB (16376 MiB), driver 621.01 |
| CPU | Intel Core i7-13700KF |
| RAM | 32 GB DDR5-6000 (2× 16 GB Corsair) |
| Storage | Samsung 980 PRO NVMe SSD |
| OS | Windows 11 Pro (10.0.26300) |

The 980 PRO matters more than it looks. On a 16 GB card ComfyUI streams the transformer
off disk on every sampling step; a slow drive would dominate the runtime.

## Results

Text-to-video, Q4_K_M GGUF, `nvfp4_awq` text encoder, `--fast-disk`:

| Preset | Clip | Resolution | Steps | Total | Peak VRAM |
|---|---|---|---|---|---|
| Draft | 5.2 s | 960×544 | 4 | **91 s** | 13.4 GB¹ |
| Standard | 5.2 s | 1344×768 | 6 | **272 s** | 10,975 MiB |
| Full | 15 s | 1344×768 | 6 | **2,209 s** | 15,974 MiB |

¹ Sampled immediately after a 15 s run, so the card was still releasing memory. Treat it as
an upper bound; the steady-state figure was ~10.9 GB.

The Draft preset is the one to iterate with — a 3× speedup over Standard, and the result is
still perfectly watchable. Spend the time on Standard only once the prompt is right.

For comparison, the authors report 151–152 s for the same 5.2 s clip on a 24 GB RTX 4090.
This card lands at **1.79×** that — 56% of a 4090's throughput, which sits between the
4070 Ti Super's ~40% compute and ~67% memory-bandwidth ratios versus a 4090. The 16 GB
penalty is smaller than feared: re-reading 6.8 GB of weights off the 980 PRO on every step
costs less than the VRAM shortfall would suggest.

Output is real: H.264 1344×768 at 24 fps with an AAC 32 kHz stereo track, muxed into MP4.

```text
duration  : 5.17 s
video     : 1344x768  h264  24 fps  124 frames
audio     : aac  32000 Hz  2 ch
```

Samples: [`media/5s-960x544-4steps.mp4`](media/5s-960x544-4steps.mp4) ·
[`media/5s-1344x768.mp4`](media/5s-1344x768.mp4) ·
[`media/15s-1344x768.mp4`](media/15s-1344x768.mp4)

## What this model is

MiniMax-H3 is a 31B open model that generates video and synchronized audio together.
HyperFlow H3 Flash is Video Rebirth's compressed derivative:

- **Pruning + low-rank factorization** — 3 of 50 blocks dropped, 102 linears factored, down to 13.7B parameters.
- **Two-time (t, r) conditioning** — every token sees both the current noise level and the step endpoint, which allows 4/6/8-step sampling with no classifier-free guidance.
- **W8A8 INT8 with a Hadamard rotation** — used by the INT8 path, not by the GGUF one.

Default output is 1344×768 at 24 fps with a 32 kHz stereo soundtrack, 5.2 to 15 seconds.

---

## Setup

Four steps, ~30 minutes including a 28.5 GB download. Everything runs from the repository root.

### 0. Prerequisites

- Python 3.10+ (3.12 used here), Git, and the `hf` CLI (`pip install -U huggingface_hub`)
- An Ampere-or-newer NVIDIA GPU and a CUDA PyTorch
- **~35 GB free disk** for weights plus ComfyUI

### 1. ComfyUI and its dependencies

```powershell
.\scripts\01-install-comfyui.ps1
```

This clones ComfyUI (needs **0.43.0 or newer** for the `MiniMaxH3ImageToVideo` node) and
both custom nodes — [ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF) and
[ComfyUI-HyperFlow-Flash](https://github.com/Video-Rebirth/ComfyUI-HyperFlow-Flash) —
into a virtualenv that reuses the machine's existing PyTorch.

> **Clean PyTorch install.** The script assumes a CUDA PyTorch already exists and pins it
> so `pip` cannot replace it. On a fresh machine, drop `--system-site-packages`, remove
> `constraints.txt`, and install torch first: `pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130`.
> Use a cu13x build if you can — ComfyUI wants one for its optimized kernels (see [Gotchas](#gotchas)).

### 2. Weights (28.5 GB)

```powershell
.\scripts\02-download-models.ps1
```

| File | Size | Goes to |
|---|---|---|
| `minimax_h3_fl2va_hyperflow_flash_14b-Q4_K_M.gguf` | 8.4 GB | `models/diffusion_models/` |
| `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | 14.6 GB | `models/text_encoders/` |
| `minimax_h3_video_vae_fp16.safetensors` | 4.9 GB | `models/vae/` |
| `minimax_h3_audio_vae_fp32.safetensors` | 0.6 GB | `models/vae/` |

Two things that trip people up here:

- The transformer lives under **`fl2va_gguf/`** in the repo, and the filename carries a
  `minimax_h3_fl2va_` prefix. There is no `hyperflow-h3-flash-14b-Q4_K_M.gguf`.
- There are **two** VAEs. Without the audio one you get silent video, which rather defeats
  the point of this model.

### 3. Start the server

```powershell
.\scripts\03-start-server.ps1
```

which is just:

```powershell
cd ComfyUI
.\.venv\Scripts\python.exe main.py --fast-disk
```

Open `http://127.0.0.1:8188`, then **Workflow → Browse Templates → ComfyUI-HyperFlow-Flash**
and pick `hyperflow_t2v`, `hyperflow_i2v`, `hyperflow_flf2v`, or `hyperflow_ref2v`.

**`--fast-disk` is not optional on a 32 GB machine.** It streams offloaded weights from the
OS file page cache instead of copying them into pinned RAM, which keeps anonymous RSS around
8–16 GB. Without it you will hit the pagefile.

### 4. Generate from the command line

```powershell
.\scripts\generate.ps1 -Prompt "A street musician plays a weathered acoustic guitar on a cobblestone corner at golden hour." -Length 124
```

```text
queued 3897feb3-...  1344x768 124f  6 steps
output : output\hyperflow\t2v_00001_.mp4
time   : 272.2 s
peak   : 10,975 MiB VRAM
```

All four scripts take a `-ComfyUI <path>` argument. It defaults to a checkout next to this
repository, which is what step 1 creates — pass it explicitly if your ComfyUI lives
somewhere else.

---

## How 16 GB actually fits

The interesting part. At 5.2 s the log looks like this:

```text
Requested to load MiniMaxH3TEModel_
Model MiniMaxH3TEModel_ prepared for dynamic VRAM loading. 14956MB Staged.
Requested to load MiniMaxH3
loaded partially; 2353.20 MB usable, 2105.13 MB loaded,
                 6831.58 MB offloaded, 248.06 MB buffer reserved
HyperFlow: transformer weights in disk (weights_in=auto)
```

So ComfyUI keeps **about 2.1 GB of the transformer resident** — the log's own numbers are
`2105 MB loaded, 6832 MB offloaded` — and streams the rest from the 980 PRO on every step.
The 14.6 GB text encoder can never co-reside with it, so the two are swapped between the
encode and sample stages.

At 15 s the budget collapses entirely:

```text
loaded partially; 0.00 MB usable, 0.00 MB loaded, 8936.71 MB offloaded
```

Nothing stays resident. Every block is re-read from disk on all six steps. That is the
whole cost of a 16 GB card here, and it is why the 15 s case costs far more than 3× the
5.2 s case.

Peak VRAM on that run was **15,974 MiB of 16,376 MiB — 97.5% of the card**. No headroom is
left to absorb anything, and the per-step timings show it: 230 s on the best step, 524 s on
the worst, 372 s on average. The same step of the same graph alternately takes four minutes
and nine minutes depending on how the page cache and the disk streaming line up. On the
5.2 s clip the spread is 36.4–36.7 s — dead flat.

**Stability, not just speed, is what the extra VRAM buys you.** A 16 GB card can run this
model, but at 15 s it runs it on a knife edge.

**The scaling is quadratic in tokens.** 37.7k → 109k tokens is 2.89×, but mean per-step time
goes 36.5 s → 372 s, i.e. **10.2×**. Attention alone would predict 2.89² = 8.35, so the
remaining ~20% is the loss of residency — at 15 s there is no cached weight left to reuse.
Both effects stack, exactly as the model card warns: *"Attention cost grows with the square
of the token count."*

Practical consequence: **halve the resolution before you halve anything else.** Tokens scale
with pixel count, so 960×544 is roughly 4× fewer tokens and ~16× less attention work — and
dropping to 4 steps compounds it. That is where the 91 s Draft preset comes from: 3× faster
than Standard, which is the difference between iterating on a prompt and going for coffee.

## Gotchas

Things that cost time, in order of how much they cost.

**Flags that do not exist.** `--gpu-only-inference` is not a ComfyUI flag; argparse exits
with `unrecognized arguments`. The real flag is `--gpu-only`, and on a 16 GB card it is the
opposite of what you want — it pins everything, text encoder included, in VRAM. It is also
mutually exclusive with `--lowvram`.

**`--lowvram` does nothing for you.** Its current help text: *"Doesn't do anything if
dynamic vram is enabled."* DynamicVRAM is on by default here. On older builds it moves the
text encoder to the CPU, which is slower than what the scheduler would have done anyway.

**`--fast-disk` is the one flag that matters.** Everything else in a typical "low VRAM"
launch line is noise or actively harmful.

**INT8 is a 24 GB path.** The INT8 safetensors are 14.9 GB — nearly the whole card, with no
room for activations. The "16 GB PC" columns in the official benchmarks mean 16 GB of
*system RAM*, not VRAM. Easy to misread, and it changes the recommendation completely.

**The Python package is out of reach.** `hyperflow-h3-flash --offload stream` wants ≥69 GiB
of system RAM with the fp8 text encoder. 32 GB is not close. ComfyUI is the only route.

**cu130 warning.** ComfyUI 0.44.0 logs *"You need pytorch with cu130 or higher to use
optimized CUDA operations"* and disables `comfy_kitchen`'s CUDA backend, falling back to
eager. This setup ran on the machine's existing torch 2.14.1+cu126 and works fine; a cu13x
build should claw back a few seconds per run, mostly in text-encoder dequant.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Out of system RAM | Confirm `--fast-disk` is actually on; put weights on NVMe |
| Out of GPU memory | Drop resolution first, then `length`; `Q3_K_M` (6.7 GB) as a last resort |
| Loader dropdown empty | Files must be flat in `models/diffusion_models`, `models/text_encoders`, `models/vae` |
| `MiniMaxH3ImageToVideo` missing | ComfyUI older than 0.43.0 |
| Workflow loads but nodes are red | Custom nodes cloned but `pip install -r requirements.txt` was never run |
| Silent video | Audio VAE missing from `models/vae/` |
| `CUDA error: invalid argument` on long `ref2v` | Start with `--disable-cuda-malloc` |

## License — read this before you download

The weights are a derivative of MiniMax-H3 under the **MiniMax H3 Community License**,
which **does not cover the European Union, the United Kingdom, South Korea, or the United
States** without prior authorization from MiniMax. Products over $20M annual revenue need
written authorization, and generated content distributed publicly must be disclosed as
AI-generated.

This repository contains **no model weights** — only scripts and notes. Code here is MIT;
the models are not mine to license. Check the
[license Q&A](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/docs/QA-about-License.md)
and the [application form](https://platform.minimax.io/h3-license) before you start.

## Repository layout

```text
.
├─ scripts/
│  ├─ 01-install-comfyui.ps1    # ComfyUI + venv + both custom nodes
│  ├─ 02-download-models.ps1    # 28.5 GB of weights
│  ├─ 03-start-server.ps1       # main.py --fast-disk
│  └─ generate.ps1              # headless API client with timing
├─ media/                       # sample output
└─ logs/
```

`ComfyUI/`, the venv, and all weights are gitignored.

## Versions used

| | |
|---|---|
| ComfyUI | 0.44.0 (`fca60fe`, 2026-11-08) |
| ComfyUI-GGUF | `6ea2651` |
| ComfyUI-HyperFlow-Flash | `c807a89` (2026-11-09) |
| PyTorch | 2.14.1+cu126 |
| Python | 3.12.10 |

## Credits

Model by [Video Rebirth](https://www.videorebirth.com/); built on
[MiniMax-H3](https://huggingface.co/MiniMaxAI/MiniMax-H3). GGUF layout follows
[Unsloth](https://huggingface.co/unsloth/MiniMax-H3-GGUF)'s convention. Rotated INT8
pioneered by [`WAS/Minimax-h3_Singularity_v2_pruned`](https://huggingface.co/WAS/Minimax-h3_Singularity_v2_pruned).

Nothing here is affiliated with Video Rebirth or MiniMax. These are one person's notes from
one machine.
