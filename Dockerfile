FROM lmsysorg/sglang:dev

WORKDIR /sgl-workspace/sglang

RUN pip install -e "python[diffusion]"

RUN pip install \
    huggingface_hub \
    accelerate \
    hf_transfer

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*