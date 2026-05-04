# Sample request bodies

Drop-in JSON payloads for testing a deployed 10eros-runpod-worker endpoint. Each file is a complete `{ "input": { ... } }` body — POST to RunPod's `/runsync` (or `/run` for async + `/status/<id>` poll) with no edits needed beyond uploading a reference image to R2 first.

## Prerequisites

1. **Endpoint deployed** via `scripts/build-on-pod.sh` (see top-level README).
2. **R2 reference image uploaded** at `refs/dog.png` in the bucket configured as `R2_INPUT_BUCKET_NAME` (or `R2_BUCKET_NAME` if input bucket isn't set).
   - Or edit `r2_inputs[0].r2_key` in each file to point at your own image.
3. **RunPod API key** in `RUNPOD_API_KEY`.
4. **Endpoint ID** in `RUNPOD_ENDPOINT_ID`.

```bash
export RUNPOD_API_KEY="rpa_..."
export RUNPOD_ENDPOINT_ID="abc123xyz"
```

## Curl invocation pattern

Synchronous (waits up to 300s):

```bash
curl -X POST "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/runsync" \
    -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
    -H "Content-Type: application/json" \
    -d @test_inputs/01_smoke_test_fp8.json | jq .
```

Asynchronous (returns immediately with an id, then poll):

```bash
ID=$(curl -s -X POST "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/run" \
    -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
    -H "Content-Type: application/json" \
    -d @test_inputs/02_full_length_fp8.json | jq -r '.id')

watch -n 5 "curl -s -H 'Authorization: Bearer ${RUNPOD_API_KEY}' \
    https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/status/${ID} | jq ."
```

Local (docker-compose, `SERVE_API_LOCALLY=true`):

```bash
curl -X POST http://127.0.0.1:8000/runsync \
    -H "Content-Type: application/json" \
    -d @test_inputs/01_smoke_test_fp8.json | jq .
```

## What each file does

### Happy paths (expect `videos[0].type = "s3_url"` in response)

| File | Endpoint | Length | Purpose |
|---|---|---|---|
| `01_smoke_test_fp8.json` | fp8 | 25 frames (~1 s) | Fastest possible end-to-end check — confirms ComfyUI starts, R2 download works, model loads, output uploads back. Run this first after every deploy. |
| `02_full_length_fp8.json` | fp8 | 121 frames (~5 s) | Full default config. The fp8 half of an A/B comparison. |
| `03_full_length_bf16.json` | bf16 | 121 frames (~5 s) | Same prompt + seed as `02`, against the bf16 endpoint. Compare quality side-by-side. |
| `04_no_uid_fp8.json` | fp8 | 49 frames (~2 s) | Omits `uid` — output key lands at `<job_id>/<8char>.mp4` instead of `users/<uid>/generations/<8char>.mp4`. Verifies the prefix fallback. |
| `05_custom_seed_and_prompt_fp8.json` | fp8 | 49 frames (~2 s) | Demonstrates how to set `RandomNoise.noise_seed` (nodes `153:127` + `153:151`) for reproducibility, and how the prompt drives the motion description. |

### Error paths (expect `{ "error": "..." }` in response)

These exist so you can verify the worker degrades gracefully and the error messages are surfaced cleanly to your client.

| File | Expected response |
|---|---|
| `06_error_missing_r2_inputs.json` | `{ "error": "'r2_inputs' is required and must contain at least one entry (i2v-only)" }` |
| `07_error_empty_r2_inputs.json` | `{ "error": "'r2_inputs' must contain at least one entry (i2v-only)" }` |
| `08_error_bogus_r2_key.json` | `{ "error": "Failed to download R2 inputs: An error occurred (404) when calling the GetObject operation..." }` |
| `09_error_unknown_node_id.json` | `{ "error": "Failed to download R2 inputs: r2_inputs references node_id '999' which is not in the workflow" }` |
| `10_error_unknown_checkpoint.json` | ComfyUI 400 surfaced via `queue_workflow` — should list the unknown checkpoint and (helpfully) the available alternatives. |

### Checkpoint variant routing test

Sending `03_full_length_bf16.json` to the **fp8** endpoint (or vice-versa) should fail with the same shape as `10_error_unknown_checkpoint.json` — proves your client is hitting the right endpoint.

## Customizing for your own reference image

Every file points at `refs/dog.png` by default. Three knobs to change:

```json
"r2_inputs": [
  {
    "node_id": "153:124",
    "input_field": "image",
    "r2_key": "refs/your_image.png"   ← change this
  }
]
```

Don't change `node_id` or `input_field` — those map to the `LoadImage` node in the baked workflow. Only `r2_key` should vary.

## Tweaking generation parameters

The most useful nodes to edit per request:

| Node ID | Class | Field | Effect |
|---|---|---|---|
| `153:125` | PrimitiveInt (length) | `value` | Frame count. Default 121 ≈ 5s @ 24fps. Try 25 (1s), 49 (2s), 241 (10s). |
| `153:132` | CLIPTextEncode (positive prompt) | `text` | Describe the desired motion / camera movement / lighting evolution. |
| `153:123` | CLIPTextEncode (negative prompt) | `text` | What to suppress. Default is generic anti-artefact list. |
| `153:127` | RandomNoise | `noise_seed` | Low-res sampler seed. `0` = random per-run. Pin to reproduce. |
| `153:151` | RandomNoise | `noise_seed` | High-res sampler seed. Same. |
| `153:140` | PrimitiveFloat (fps) | `value` | Output fps. Default 24. The model is trained at 24fps; deviating may cause artefacts. |
| `153:143` | LoraLoaderModelOnly | `strength_model` | Distill LoRA strength. Default 1.0. Lower (0.5–0.8) for less distillation, more steps but possibly better quality. |
