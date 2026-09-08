---
# Qwen-Image-Edit 2511 batch: one input image, up to eight edits of it queued at
# once. The body is a YAML list, not prompt text — one entry per image you want
# back, each with the name its output is saved under. Fewer than eight entries
# prunes the unused branches out of the submitted graph, so they cost no GPU time.
#
# There is no width/height here: the output size follows input_image.
# Add `seed:` to an entry to reproduce it; without one it is randomized.
routine: comfy
subroutine: image-qwen-angles
type: image-qwen-angles
input_image: example.png
# items_file: /workspace/ai/angles.yml   # for a long list, instead of the body
---
- prompt: prompt text
  output: images/example-1
- prompt: prompt text
  output: images/example-2
- prompt: prompt text
  output: images/example-3
