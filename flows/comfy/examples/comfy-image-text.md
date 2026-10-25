---
# Flux2 text-to-image. Copy to volumes/workspace_data/.decree/inbox/ to run it.
# The body is the prompt; replace "prompt text" with your own.
machine: comfy
params:
  type: image-text
  output_prefix: images/example
  width: "1024"
  height: "1024"
  # seed: 12345          # omit to randomize
---
prompt text
