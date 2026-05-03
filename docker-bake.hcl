variable "DOCKERHUB_REPO" {
  default = "jmendapara"
}

variable "DOCKERHUB_IMG" {
  default = "10eros-runpod-worker"
}

variable "RELEASE_VERSION" {
  default = "latest"
}

variable "COMFYUI_VERSION" {
  default = "latest"
}

variable "BASE_IMAGE" {
  default = "nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
}

variable "CUDA_VERSION_FOR_COMFY" {
  default = "12.6"
}

variable "ENABLE_PYTORCH_UPGRADE" {
  default = "true"
}

variable "PYTORCH_INDEX_URL" {
  default = "https://download.pytorch.org/whl/cu126"
}

variable "MODEL_VARIANT" {
  default = "fp8"
}

variable "HUGGINGFACE_ACCESS_TOKEN" {
  default = ""
}

group "default" {
  targets = ["10eros-fp8"]
}

target "10eros-fp8" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "final"
  platforms  = ["linux/amd64"]
  args = {
    BASE_IMAGE               = "${BASE_IMAGE}"
    COMFYUI_VERSION          = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY   = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE   = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL        = "${PYTORCH_INDEX_URL}"
    MODEL_VARIANT            = "fp8"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-fp8"]
}

target "10eros-bf16" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "final"
  platforms  = ["linux/amd64"]
  args = {
    BASE_IMAGE               = "${BASE_IMAGE}"
    COMFYUI_VERSION          = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY   = "${CUDA_VERSION_FOR_COMFY}"
    ENABLE_PYTORCH_UPGRADE   = "${ENABLE_PYTORCH_UPGRADE}"
    PYTORCH_INDEX_URL        = "${PYTORCH_INDEX_URL}"
    MODEL_VARIANT            = "bf16"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-bf16"]
}

# Blackwell variant (RTX PRO 6000 96 GB, sm_120): CUDA 12.8 + PyTorch cu128.
target "10eros-fp8-blackwell" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "final"
  platforms  = ["linux/amd64"]
  args = {
    BASE_IMAGE               = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
    COMFYUI_VERSION          = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY   = ""
    ENABLE_PYTORCH_UPGRADE   = "true"
    PYTORCH_INDEX_URL        = "https://download.pytorch.org/whl/cu128"
    MODEL_VARIANT            = "fp8"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-fp8-blackwell"]
}

target "10eros-bf16-blackwell" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "final"
  platforms  = ["linux/amd64"]
  args = {
    BASE_IMAGE               = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
    COMFYUI_VERSION          = "${COMFYUI_VERSION}"
    CUDA_VERSION_FOR_COMFY   = ""
    ENABLE_PYTORCH_UPGRADE   = "true"
    PYTORCH_INDEX_URL        = "https://download.pytorch.org/whl/cu128"
    MODEL_VARIANT            = "bf16"
    HUGGINGFACE_ACCESS_TOKEN = "${HUGGINGFACE_ACCESS_TOKEN}"
  }
  tags = ["${DOCKERHUB_REPO}/${DOCKERHUB_IMG}:${RELEASE_VERSION}-bf16-blackwell"]
}
