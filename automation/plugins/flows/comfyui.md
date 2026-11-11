---
machine: plugin
automation: comfyui
name: Images and video on your own card
tagline: ComfyUI workflows a decree message can run, the prompt in its body
docs: /docs/ai/comfyui
services:
  - EXIST_IS_AI_COMFYUI
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - comfy
examples:
  comfy-image-qwen-angles: |
    ---
    # Qwen-Image-Edit 2511 batch: one input image, up to eight edits of it queued at
    # once. The body is a YAML list, not prompt text — one entry per image you want
    # back, each with the name its output is saved under. Fewer than eight entries
    # prunes the unused branches out of the submitted graph, so they cost no GPU time.
    #
    # There is no width/height here: the output size follows input_image.
    # Add `seed:` to an entry to reproduce it; without one it is randomized.
    machine: comfy
    params:
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
  comfy-image-text-image: |
    ---
    # Flux2 image-to-image: the same graph with the reference branch switched on.
    # input_image is a filename ComfyUI already knows — anything under its input/
    # folder, or "subdir/file.png [output]" to reuse something it generated.
    machine: comfy
    params:
      type: image-text-image
      input_image: example.png
      output_prefix: images/example-edit
      width: "1024"
      height: "1024"
      # seed: 12345          # omit to randomize
    ---
    prompt text
  comfy-image-text: |
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
  comfy-video-i2v: |
    ---
    # Wan 2.2 14B image-to-video: input_image is the first frame.
    # `length` is a frame count, not seconds — 133 frames is the workflow's own.
    machine: comfy
    params:
      type: video-i2v
      input_image: example.png
      output_prefix: video/example
      width: "640"
      height: "640"
      length: "133"
    ---
    prompt text
  comfy-video-ltx-first-last: |
    ---
    # LTX-2.5 first-and-last-frame to video, with audio: the run is anchored to
    # input_image at the start and last_image at the end, and the prompt describes
    # how it gets from one to the other.
    #
    # This graph has no ResolutionSelector — width/height are the size knob.
    machine: comfy
    params:
      type: video-ltx-first-last
      input_image: example-first.png
      last_image: example-last.png
      output_prefix: video/example
      width: "1280"
      height: "720"
      duration: "5"
      fps: "24"
      enhance_prompt: "true"
    ---
    prompt text
  comfy-video-ltx-image: |
    ---
    # LTX-2.5 image-to-video, with audio: input_image is the first frame.
    # Size notes as in comfy-video-ltx-text.md.
    machine: comfy
    params:
      type: video-ltx-image
      input_image: example.png
      output_prefix: video/example
      aspect_ratio: "16:9 (Widescreen)"
      megapixels: "0.9"
      duration: "5"
      fps: "24"
      enhance_prompt: "true"
    ---
    prompt text
  comfy-video-ltx-text: |
    ---
    # LTX-2.5 text-to-video, with audio.
    #
    # Size comes from the graph's ResolutionSelector — pick an aspect ratio and a
    # megapixel budget rather than raw pixels. Setting width/height instead replaces
    # the selector with literals.
    #
    # duration is seconds; the frame count is duration x fps.
    # enhance_prompt rewrites the prompt through a local LLM before encoding it.
    machine: comfy
    params:
      type: video-ltx-text
      output_prefix: video/example
      aspect_ratio: "16:9 (Widescreen)"
      megapixels: "0.9"
      duration: "5"
      fps: "24"
      enhance_prompt: "true"
      # width: 1280          # overrides aspect_ratio/megapixels
      # height: 720
    ---
    prompt text
---

ComfyUI ships with no models: each workflow in workspace/.decree/lib/comfy/workflows/ (the comfy plugin's) names the
files it needs and where they go. Already run ComfyUI elsewhere? Set
EXIST_COMFYUI_URL=http://<host>:8188 and EXIST_IS_AI_COMFYUI=false instead. To run one,
drop one of the examples above (examples:) into volumes/workspace_data/.decree/inbox/, or:
  echo 'a lighthouse at dusk' | docker exec -i automation decree emit --machine comfy --param type=image-text-image
