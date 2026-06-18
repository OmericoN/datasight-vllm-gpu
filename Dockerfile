FROM vllm/vllm-openai:latest

ENV HF_HOME=/hf-cache
ENV HUGGINGFACE_HUB_CACHE=/hf-cache/hub
ENV TRANSFORMERS_CACHE=/hf-cache/transformers
ENV XDG_CACHE_HOME=/hf-cache/xdg
ENV VLLM_CACHE_ROOT=/hf-cache/vllm
ENV TRITON_CACHE_DIR=/hf-cache/triton
ENV TORCHINDUCTOR_CACHE_DIR=/hf-cache/torchinductor
ENV HOME=/tmp
ENV VLLM_MODEL=Qwen/Qwen2.5-0.5B-Instruct
ENV SERVED_MODEL_NAME=Qwen/Qwen2.5-0.5B-Instruct
ENV HOST=0.0.0.0
ENV PORT=8000
ENV VLLM_DTYPE=auto
ENV VLLM_START_MODE=serve

COPY entrypoint-vllm.sh /entrypoint-vllm.sh
RUN mkdir -p /hf-cache /tmp/hf-cache /tmp/xdg-cache /tmp/vllm-cache \
  && chmod 0777 /hf-cache /tmp/hf-cache /tmp/xdg-cache /tmp/vllm-cache \
  && chmod +x /entrypoint-vllm.sh

EXPOSE 8000

ENTRYPOINT ["/entrypoint-vllm.sh"]
