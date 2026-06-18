#!/usr/bin/env bash
set -e

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
VLLM_MODEL="${VLLM_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${VLLM_MODEL}}"
VLLM_DTYPE="${VLLM_DTYPE:-auto}"
VLLM_DEVICE="${VLLM_DEVICE:-cuda}"
VLLM_START_MODE="${VLLM_START_MODE:-serve}"

export HF_HOME="${HF_HOME:-/hf-cache}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-${HF_HOME}/hub}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-${HF_HOME}/transformers}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HF_HOME}/xdg}"
export VLLM_CACHE_ROOT="${VLLM_CACHE_ROOT:-${HF_HOME}/vllm}"
export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-${HF_HOME}/triton}"
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-${HF_HOME}/torchinductor}"
export HOME="${HOME:-/tmp}"
export USER="${USER:-datasight}"
export LOGNAME="${LOGNAME:-${USER}}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/pycache}"

ensure_writable_cache() {
  local cache_root="$1"

  mkdir -p "${cache_root}" \
    "${cache_root}/hub" \
    "${cache_root}/transformers" \
    "${cache_root}/xdg" \
    "${cache_root}/vllm" \
    "${cache_root}/triton" \
    "${cache_root}/torchinductor" || return 1

  local probe_file="${cache_root}/.write-test"
  touch "${probe_file}" || return 1
  rm -f "${probe_file}" || return 1
}

if ! ensure_writable_cache "${HF_HOME}"; then
  echo "WARNING: ${HF_HOME} is not writable by uid $(id -u). Falling back to /tmp/hf-cache."
  echo "WARNING: model cache will not persist until the PVC permissions are fixed."
  export HF_HOME="/tmp/hf-cache"
  export HUGGINGFACE_HUB_CACHE="${HF_HOME}/hub"
  export TRANSFORMERS_CACHE="${HF_HOME}/transformers"
  export XDG_CACHE_HOME="${HF_HOME}/xdg"
  export VLLM_CACHE_ROOT="${HF_HOME}/vllm"
  export TRITON_CACHE_DIR="${HF_HOME}/triton"
  export TORCHINDUCTOR_CACHE_DIR="${HF_HOME}/torchinductor"
  ensure_writable_cache "${HF_HOME}"
fi

mkdir -p "${HOME}" "${PYTHONPYCACHEPREFIX}"

echo "Starting DataSight vLLM GPU backend..."
echo "HOST=${HOST}"
echo "PORT=${PORT}"
echo "VLLM_MODEL=${VLLM_MODEL}"
echo "SERVED_MODEL_NAME=${SERVED_MODEL_NAME}"
echo "HF_HOME=${HF_HOME}"
echo "HUGGINGFACE_HUB_CACHE=${HUGGINGFACE_HUB_CACHE}"
echo "TRANSFORMERS_CACHE=${TRANSFORMERS_CACHE}"
echo "XDG_CACHE_HOME=${XDG_CACHE_HOME}"
echo "VLLM_CACHE_ROOT=${VLLM_CACHE_ROOT}"
echo "TRITON_CACHE_DIR=${TRITON_CACHE_DIR}"
echo "TORCHINDUCTOR_CACHE_DIR=${TORCHINDUCTOR_CACHE_DIR}"
echo "HOME=${HOME}"
echo "USER=${USER}"
echo "LOGNAME=${LOGNAME}"
echo "VLLM_DTYPE=${VLLM_DTYPE}"
echo "VLLM_DEVICE=${VLLM_DEVICE}"
echo "VLLM_START_MODE=${VLLM_START_MODE}"

if [[ "${VLLM_START_MODE}" == "hold" ]]; then
  echo "VLLM_START_MODE=hold: keeping container alive without starting vLLM."
  exec tail -f /dev/null
fi

if [[ "${VLLM_START_MODE}" != "serve" ]]; then
  echo "ERROR: VLLM_START_MODE must be either 'hold' or 'serve'. Got '${VLLM_START_MODE}'."
  exit 2
fi

args=(
  --host "${HOST}"
  --port "${PORT}"
  --model "${VLLM_MODEL}"
  --served-model-name "${SERVED_MODEL_NAME}"
  --dtype "${VLLM_DTYPE}"
  --device "${VLLM_DEVICE}"
  --download-dir "${HF_HOME}/models"
)

if [[ -n "${VLLM_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<< "${VLLM_EXTRA_ARGS}"
  args+=("${extra_args[@]}")
fi

python_bin="$(command -v python || command -v python3 || true)"
if [[ -z "${python_bin}" ]]; then
  echo "ERROR: neither python nor python3 is available on PATH."
  exit 127
fi

exec "${python_bin}" -m vllm.entrypoints.openai.api_server "${args[@]}"
