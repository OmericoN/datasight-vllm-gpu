# datasight-vllm-gpu

Private DSRI/OpenShift GPU backend for the public
[`datasight-llm-server`](https://github.com/OmericoN/datasight-llm-server)
CPU gateway.

This repository intentionally contains only the vLLM image and DSRI deployment
manifests. Do not copy the CPU gateway application code into this repository.

## Architecture

```text
Public internet / DataSight client
  -> datasight-llm-server
     CPU-only FastAPI gateway
     public DSRI Route
     API keys, rate limits, usage monitoring

OpenShift internal network
  -> datasight-vllm-gpu
     private vLLM OpenAI-compatible backend
     no public Route
     nvidia.com/gpu: 1 only on this deployment
```

The CPU gateway calls this backend through the OpenShift internal Service:

```text
http://datasight-vllm-gpu:8000
```

The GPU backend is not the public authentication boundary. The public boundary
is `datasight-llm-server`. Backend-side authentication can still be enabled for
defense in depth, but the backend secret must only be configured on the CPU
gateway.

## Files

```text
datasight-vllm-gpu/
├── Dockerfile
├── entrypoint-vllm.sh
├── README.md
└── dsri/
    ├── deployment.yaml
    ├── service.yaml
    └── pvc.yaml
```

No OpenShift Route is provided for `datasight-vllm-gpu` by default.

## Image

The image is based on the official vLLM OpenAI server image:

```dockerfile
FROM vllm/vllm-openai:latest
```

The container listens on `0.0.0.0:8000` and starts:

```bash
python -m vllm.entrypoints.openai.api_server
```

Default model:

```text
Qwen/Qwen2.5-32B-Instruct-AWQ
```

For first DSRI validation, temporarily override the deployment model with:

```text
Qwen/Qwen2.5-0.5B-Instruct
```

Switch to the 32B AWQ model only after image build, service discovery, PVC
mounting, and gateway proxying are confirmed.

## OpenShift Project Namespace

`dsri/deployment.yaml` currently references this internal OpenShift image:

```text
image-registry.openshift-image-registry.svc:5000/datasight/datasight-vllm-gpu:latest
```

If the DSRI project namespace is not `datasight`, replace the namespace segment
before deploying:

```text
image-registry.openshift-image-registry.svc:5000/<project>/datasight-vllm-gpu:latest
```

## DSRI Resources

Apply the PVC, Service, and Deployment:

```bash
oc apply -f dsri/pvc.yaml
oc apply -f dsri/service.yaml
oc apply -f dsri/deployment.yaml
```

The deployment defaults to:

```text
replicas: 0
```

This keeps GPU quota unused while idle. Scaling to `1` is an operational action
during a booked GPU window:

```bash
oc scale deployment/datasight-vllm-gpu --replicas=1
```

After testing:

```bash
oc scale deployment/datasight-vllm-gpu --replicas=0
```

## Required Environment

```text
HOST=0.0.0.0
PORT=8000
VLLM_MODEL=Qwen/Qwen2.5-32B-Instruct-AWQ
SERVED_MODEL_NAME=Qwen/Qwen2.5-32B-Instruct-AWQ
VLLM_DTYPE=auto
HF_HOME=/hf-cache
HUGGINGFACE_HUB_CACHE=/hf-cache/hub
TRANSFORMERS_CACHE=/hf-cache/transformers
```

Optional:

```text
VLLM_EXTRA_ARGS=<additional vLLM CLI flags>
```

## Gateway Integration

In the `datasight-llm-server` deployment, set:

```text
LLM_BACKEND_URL=http://datasight-vllm-gpu:8000
LLM_MODEL=<same served model name>
```

If backend-side auth is added to vLLM, set this only on the CPU gateway:

```text
LLM_BACKEND_API_KEY=<backend-secret>
```

Do not expose this backend secret to public clients.

Never assign `nvidia.com/gpu` to `datasight-llm-server`.

## Operations

Normal idle state:

```text
datasight-llm-server replicas: 1
datasight-vllm-gpu replicas: 0
GPU quota used: 0
```

GPU booked test state:

```text
datasight-llm-server replicas: 1
datasight-vllm-gpu replicas: 1
GPU quota used: 1
```

After the test window:

```text
datasight-vllm-gpu replicas: 0
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
