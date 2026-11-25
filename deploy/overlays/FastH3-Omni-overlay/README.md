---
license: other
tags:
  - sglang
  - overlay
---

# FastH3 Omni overlay for SGLang

SGLang model overlay for
[FastVideo/FastVideo-FastH3-Omni-8-Step-V1](https://huggingface.co/FastVideo/FastVideo-FastH3-Omni-8-Step-V1)
(revision `53e0d26a1691aa473b6262d8196a8feb2c297df0`).

The materializer maps the release's `transformer_ref/` into the base MiniMax-H3
layout, fuses its 32 PDD interval heads into 8 per-step heads under `pdd/`, and
links the Ref2VA text encoder and VAEs from `MiniMaxAI/MiniMax-H3` at the revision
pinned by `fastvideo_inference.json`. SGLang then serves the model with the
existing MiniMax-H3 pipeline, PDD head loading, and VSA-H3 attention.

```bash
sglang generate --model-path FastVideo/FastVideo-FastH3-Omni-8-Step-V1 ...
```

No weights live in this repository.
