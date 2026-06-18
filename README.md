# datasight-vllm-gpu

This repository is deployed on the DSRI OpenShift cluster. It serves as the private GPU backend for the public
[`datasight-llm-server`](https://github.com/OmericoN/datasight-llm-server)
CPU gateway. It will pull models from vLLM.



Default validation model:

```text
Qwen/Qwen2.5-0.5B-Instruct
```

This repository defaults to the small model because it is the fastest way to
prove GPU scheduling, image pull, PVC mounting, service discovery, and vLLM
startup during a booked GPU window.

Target production model:

```text
Qwen/Qwen2.5-32B-Instruct-AWQ
```

Switch to the 32B AWQ model only after the small model is healthy through the
CPU gateway.

## Developer Quick Guide
> This guide assumes you have access to the `ub-datasight` project and logged in via `oc login`.

### Starting the GPU Backend
- Schedule a GPU time window via ['DSRI GPU Calendar'](https://dsri.maastrichtuniversity.nl/gpu-booking)
- Start the GPU in `hold` mode (for safety):
  ```bash
  oc set env -n ub-datasight deployment/datasight-vllm-gpu VLLM_START_MODE=hold
  oc scale -n ub-datasight deployment/datasight-vllm-gpu --replicas=1
  ```
- Check GPU attachement:
  ```bash
  oc exec -n ub-datasight deployment/datasight-vllm-gpu -- sh -lc 'ls -l /dev/nvidia* 2>/dev/null || echo no-nvidia-devices'
  ```
- If GPU is available, switch to `serve mode` and restart rollout:
  ```bash
  oc set env -n ub-datasight deployment/datasight-vllm-gpu VLLM_START_MODE=serve
  oc rollout restart -n ub-datasight deployment/datasight-vllm-gpu
  ```

### Gracefully Shutting Down GPU Service
- Switch back to the safety `hold` mode:
  ```bash
  oc set env -n ub-datasight deployment/datasight-vllm-gpu VLLM_START_MODE=hold
  ```
- Scale down to 0 replicas:
  ```bash
  oc scale -n ub-datasight deployment/datasight-vllm-gpu --replicas=0
  ```



## Required Environment

```text
HOST=0.0.0.0
PORT=8000
VLLM_MODEL=Qwen/Qwen2.5-0.5B-Instruct
SERVED_MODEL_NAME=Qwen/Qwen2.5-0.5B-Instruct
VLLM_DTYPE=auto
HF_HOME=/hf-cache
HUGGINGFACE_HUB_CACHE=/hf-cache/hub
TRANSFORMERS_CACHE=/hf-cache/transformers
XDG_CACHE_HOME=/hf-cache/xdg
VLLM_CACHE_ROOT=/hf-cache/vllm
TRITON_CACHE_DIR=/hf-cache/triton
TORCHINDUCTOR_CACHE_DIR=/hf-cache/torchinductor
HOME=/tmp
USER=datasight
LOGNAME=datasight
PYTHONPYCACHEPREFIX=/tmp/pycache
VLLM_START_MODE=serve
```

Optional:

```text
VLLM_EXTRA_ARGS=<additional vLLM CLI flags>
```

Debug hold mode:

```text
VLLM_START_MODE=hold
```

In hold mode the entrypoint logs its environment and runs `tail -f /dev/null`.
It does not start vLLM, call Python, or download a model. Use this to confirm
that the image, OpenShift security context, PVC mount, and GPU scheduling keep a
pod alive. Set `VLLM_START_MODE=serve` to start vLLM again after the container
runtime is validated.

The deployment now defaults to `VLLM_START_MODE=serve` with the small validation
model. Keep this model until `/health`, `/v1/models`, and one tiny chat request
work through the CPU gateway.

## Gateway Integration
> To connect the GPU backend to the CPU gateway

In the `datasight-llm-server` deployment, set env variables:

```text
LLM_BACKEND_URL=http://datasight-vllm-gpu:8000
LLM_MODEL=<same served model name>
```

If backend-side auth is added to vLLM, set this only on the CPU gateway:

```text
LLM_BACKEND_API_KEY=<backend-secret>
```



## Validation Checklist

Before scaling GPU to `1`:

- PVC exists and is mounted at `/hf-cache`.
- `datasight-vllm-gpu` Service exists on port `8000`.
- No public Route exists for `datasight-vllm-gpu`.
- CPU gateway has `LLM_BACKEND_URL=http://datasight-vllm-gpu:8000`.
- CPU gateway has `API_KEYS` configured for public use.

During a booked GPU window:

- Scale `datasight-vllm-gpu` to `1`.
- Confirm the pod starts and becomes ready.
- Confirm the CPU gateway `/gpu-status` reports `gpu_available: true`.
- Confirm the CPU gateway `/v1/models` works with an API key.
- Confirm a tiny `/v1/chat/completions` request works with low `max_tokens`.

After testing:

- Scale `datasight-vllm-gpu` back to `0`.
- Confirm GPU quota returns to unused.
- Confirm the CPU gateway still answers `/health`.
- Confirm the CPU gateway returns `503` for chat when the backend is down.

## Acceptance Criteria

- The repository builds a vLLM image from `Dockerfile`.
- The service listens on `0.0.0.0:8000`.
- `/health` returns `200` when vLLM is ready.
- `/v1/models` returns OpenAI-compatible model metadata.
- `/v1/chat/completions` works through the CPU gateway.
- The GPU deployment requests `nvidia.com/gpu: "1"`.
- The GPU deployment defaults to `replicas: 0`.
- No public Route is created for `datasight-vllm-gpu`.
- Model cache persists across pod restarts via `/hf-cache`.
- GPU quota is consumed only when `datasight-vllm-gpu` is scaled to `1`.
