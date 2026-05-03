# 10Eros RunPod Worker (LTX 2.3 i2v)

Image-to-video generation with [TenStrip/LTX2.3-10Eros](https://huggingface.co/TenStrip/LTX2.3-10Eros) — a layer-scaled merge of [Sulphur-2](https://huggingface.co/SulphurAI/Sulphur-2-base) (LTX 2.3 architecture) optimized for image-to-video. Reference image is pulled from a Cloudflare R2 bucket; the resulting MP4 is uploaded back to R2 and returned as a 7-day presigned URL.

## What's included

This image bakes in everything the i2v workflow needs — no cold-start downloads:

- ComfyUI + the `ComfyUI-LTXVideo` custom node
- 10Eros checkpoint (CLIP + VAE bundled): `fp8` (29.6 GB) **or** `bf16` (46.1 GB), chosen at build time via the `MODEL_VARIANT` build arg
- Gemma 12B fp4 text encoder (~6.5 GB)
- LTX 2.3 distill LoRA (~1 GB) for fast 6–8 step inference
- LTX 2.3 spatial upscaler (~1 GB)

## Required configuration

| Variable | Purpose |
|---|---|
| `BUCKET_ENDPOINT_URL` | R2 endpoint, e.g. `https://<account>.r2.cloudflarestorage.com` |
| `BUCKET_ACCESS_KEY_ID` | R2 API token access key |
| `BUCKET_SECRET_ACCESS_KEY` | R2 API token secret |
| `R2_BUCKET_NAME` | Bucket the output is uploaded to |
| `R2_INPUT_BUCKET_NAME` | Optional — defaults to `R2_BUCKET_NAME` |

See the [full README on GitHub](https://github.com/Jmendapara/10eros-runpod-worker) for additional tunables.

## Input

```json
{
  "input": {
    "workflow": { "/* full ComfyUI workflow JSON (API format) */": "..." },
    "r2_inputs": [
      { "node_id": "16", "input_field": "image", "r2_key": "refs/character.png" }
    ],
    "uid": "user_abc123"
  }
}
```

- `workflow` — required. Export from ComfyUI via **Workflow → Save (API Format)**.
- `r2_inputs` — required, non-empty. Each entry downloads the R2 object at `r2_key` into `/comfyui/input/` and overwrites `workflow[node_id].inputs[input_field]` with the downloaded filename.
- `uid` — optional. If set, output keys are scoped to `users/<uid>/generations/`.

## Output

```json
{
  "videos": [
    {
      "filename": "10Eros_00001.mp4",
      "type": "s3_url",
      "data": "https://<account>.r2.cloudflarestorage.com/users/.../10Eros_00001.mp4?X-Amz-..."
    }
  ]
}
```

URLs are 7-day presigned R2 GETs.

## Recommended GPU

- **fp8 variant**: H100 80 GB or A100 80 GB.
- **bf16 variant**: H100 80 GB or RTX PRO 6000 96 GB (tight on A100 80 GB at higher resolutions).

## More info

Full docs and source: https://github.com/Jmendapara/10eros-runpod-worker
