# 10eros-runpod-worker

RunPod serverless worker for [TenStrip/LTX2.3-10Eros](https://huggingface.co/TenStrip/LTX2.3-10Eros) — a layer-scaled merge of [Sulphur-2](https://huggingface.co/SulphurAI/Sulphur-2-base) (LTX 2.3 architecture), optimized for **image-to-video** generation.

The worker accepts a ComfyUI workflow + a Cloudflare R2 reference-image key, runs i2v inference, and uploads the resulting MP4 back to R2 as a 7-day presigned URL.

## What's baked into the image

| Path | Source | fp8 size | bf16 size |
|---|---|---|---|
| `models/checkpoints/10Eros_v1_<variant>.safetensors` | `TenStrip/LTX2.3-10Eros` | 29.6 GB | 46.1 GB |
| `models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors` | `Comfy-Org/ltx-2` | ~6.5 GB | ~6.5 GB |
| `models/latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.0.safetensors` | `Lightricks/LTX-2.3` | ~1 GB | ~1 GB |
| `models/loras/ltx-2.3-22b-distilled-lora-1.1_fro90_ceil72_condsafe.safetensors` | `SulphurAI/Sulphur-2-base` | ~1 GB | ~1 GB |
| **Total** | | **~37 GB** | **~54 GB** |

Plus ComfyUI itself (with the `ComfyUI-LTXVideo` custom node).

The 10Eros checkpoint bundles its own CLIP and VAE — no separate VAELoader needed. Workflows just use a single `CheckpointLoaderSimple`.

## Variants — fp8 or bf16

The Dockerfile takes a `MODEL_VARIANT` build arg:

- **`fp8`** (default) — `10Eros_v1_fp8_transformer.safetensors`, 29.6 GB. Fits comfortably on H100 80 GB or A100 80 GB.
- **`bf16`** — `10Eros_v1_bf16.safetensors`, 46.1 GB. Higher precision; recommend H100 80 GB or RTX PRO 6000 96 GB. Tight on A100 80 GB at higher resolutions.

Build both as separate images (the variant is fixed at build time — the file is too large to swap at request time) and deploy as two RunPod endpoints if you want to A/B compare quality:

```bash
MODEL_VARIANT=fp8  IMAGE_TAG=jmendapara/10eros-runpod-worker:latest bash scripts/build-on-pod.sh
# → pushes jmendapara/10eros-runpod-worker:latest-fp8

MODEL_VARIANT=bf16 IMAGE_TAG=jmendapara/10eros-runpod-worker:latest bash scripts/build-on-pod.sh
# → pushes jmendapara/10eros-runpod-worker:latest-bf16
```

The build script auto-suffixes the tag with the variant if it isn't already there.

## Request shape

```jsonc
{
  "input": {
    // REQUIRED. ComfyUI workflow JSON in API format (Workflow → Save (API Format) in ComfyUI).
    "workflow": { "<node_id>": { "class_type": "...", "inputs": {...} }, ... },

    // REQUIRED, non-empty. Each entry downloads the R2 object at r2_key into
    // /comfyui/input/<basename> and rewrites workflow[node_id].inputs[input_field]
    // to the local filename. Always at least one entry — this worker is i2v-only.
    "r2_inputs": [
      { "node_id": "153:124", "input_field": "image", "r2_key": "refs/dog.png" }
    ],

    // OPTIONAL. When present, output keys go to users/<uid>/generations/<8char>.<ext>
    // (presigned 7d). Without uid, keys go to <job_id>/<8char>.<ext>.
    "uid": "user_abc123",

    // OPTIONAL. Per-request override for COMFY_ORG_API_KEY env var.
    "comfy_org_api_key": "..."
  }
}
```

A complete example workflow lives in `test_input_fp8.json` / `test_input_bf16.json`. The two files differ only in the `ckpt_name` strings — same prompt, same r2_inputs, same seed — making them suitable for A/B comparison.

## Response shape

When `BUCKET_ENDPOINT_URL` is configured (production):

```jsonc
{
  "videos": [
    {
      "filename": "10Eros_fp8_00001.mp4",
      "type": "s3_url",
      "data": "https://<account>.r2.cloudflarestorage.com/users/.../<8char>.mp4?X-Amz-..."
    }
  ]
}
```

URLs are 7-day presigned R2 GETs. The key prefix is `users/<uid>/generations/` if `uid` was sent, otherwise `<job_id>/`.

When R2 is not configured (local docker-compose dev), the worker falls back to inline base64 in `data`.

## Required environment variables

| Variable | Purpose |
|---|---|
| `BUCKET_ENDPOINT_URL` | R2 endpoint, e.g. `https://<account>.r2.cloudflarestorage.com` |
| `BUCKET_ACCESS_KEY_ID` | R2 API token access key |
| `BUCKET_SECRET_ACCESS_KEY` | R2 API token secret |
| `R2_BUCKET_NAME` | Bucket the output `.mp4` is uploaded to |
| `R2_INPUT_BUCKET_NAME` | Optional — input bucket. Defaults to `R2_BUCKET_NAME` if unset. |

Optional tunables (see `.runpod/hub.json` for the full list):

| Variable | Default | Purpose |
|---|---|---|
| `COMFY_ORG_API_KEY` | unset | Default Comfy.org API key for API Nodes |
| `WEBSOCKET_RECONNECT_ATTEMPTS` | 5 | Retries when WS drops mid-job |
| `WEBSOCKET_RECONNECT_DELAY_S` | 3 | Seconds between reconnect attempts |
| `WEBSOCKET_TRACE` | false | Detailed frame-level WS logs |
| `REFRESH_WORKER` | false | Restart worker after each job |
| `NETWORK_VOLUME_DEBUG` | true | Dump network-volume diagnostics per job |
| `COMFY_LOG_LEVEL` | DEBUG | ComfyUI verbosity |

## Building locally (no push)

```bash
docker buildx build \
    --target final \
    --build-arg MODEL_VARIANT=fp8 \
    --build-arg HUGGINGFACE_ACCESS_TOKEN="$HF_TOKEN" \
    -t 10eros-runpod-worker:fp8 .

docker compose up
# Hits the local handler at :8000, ComfyUI UI at :8188.
# No R2 env vars in compose → output comes back as base64.
```

## Building on a build host (Hetzner / RunPod GPU pod)

The script clones the repo itself into `/tmp`, so you don't need a local checkout — pipe it straight from GitHub:

```bash
export DOCKERHUB_USERNAME=...
export DOCKERHUB_TOKEN=...
export IMAGE_TAG=yourname/10eros-runpod-worker:latest
export MODEL_VARIANT=fp8     # or bf16
# Optional: export HUGGINGFACE_ACCESS_TOKEN=... if Lightricks/LTX-2.3 gates
# Optional: export CUDA_LEVEL=12.8 for Blackwell GPUs

curl -fsSL https://raw.githubusercontent.com/Jmendapara/10eros-runpod-worker/main/scripts/build-on-pod.sh | bash
```

If you're already on a local checkout, you can also just run `bash scripts/build-on-pod.sh` — same result, the script always reclones from `REPO_URL` (default: `Jmendapara/10eros-runpod-worker`) into `/tmp/10eros-build-workspace` so it never picks up uncommitted changes.

The script handles Docker installation, Docker Hub login, repo clone, build, and push. Script is idempotent — re-running it is safe.

## Testing the model+workflow directly

If you suspect the worker code (handler.py / Dockerfile / R2 plumbing) but want to confirm the underlying model and workflow work, exec into the running container after `docker compose up`:

```bash
docker compose exec 10eros-worker bash
# inside the container:
tail -f /var/log/comfyui.log
# in another shell:
docker compose exec 10eros-worker bash -c \
    'curl -X POST http://127.0.0.1:8188/prompt \
        -H "Content-Type: application/json" \
        -d "$(jq -c "{prompt: .input.workflow}" /test_input_fp8.json)"'
```

This bypasses the RunPod handler, the WebSocket layer, and the R2 round-trip entirely — if it succeeds, the model and workflow are working. (Note: this skips R2 input download too, so the `LoadImage` node will fail unless you upload a file to `/comfyui/input/dog.png` first via `docker cp`.)

## Deployment to RunPod

1. Push the image with `scripts/build-on-pod.sh`.
2. Create a serverless endpoint at https://www.runpod.io/console/serverless using the pushed image tag.
3. Configure GPU + container disk:
   - **fp8**: H100 80 GB or A100 80 GB. Container disk: 80 GB.
   - **bf16**: H100 80 GB or RTX PRO 6000 96 GB. Container disk: 120 GB.
4. Set `Min Workers=0`, `Max Workers=1` to start.
5. Add the four R2 env vars listed above.
6. Send a request with a real R2 key.

## Architecture cheat-sheet

```
client ──────────► RunPod /run ──► handler.py
                                      │
                                      ├─ validate_input (require r2_inputs)
                                      ├─ check_server (ComfyUI HTTP up?)
                                      ├─ process_r2_inputs ──► R2 download ──► /comfyui/input/<basename>
                                      │                                            │
                                      │                                            ▼
                                      ├─ ws.connect → POST /prompt ──► ComfyUI executes workflow
                                      │
                                      ├─ websocket recv loop (status → executing → done/error)
                                      ├─ get_history → get_file_data → mp4 bytes
                                      ├─ upload_output_to_r2 ──► R2 put_object
                                      └─ return { videos: [{ type: s3_url, data: presigned_url }] }
```

## License

MIT (matches the wan-animate-runpod-worker template this repo descends from).
