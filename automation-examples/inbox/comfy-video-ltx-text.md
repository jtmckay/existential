---
# LTX-2.5 text-to-video, with audio.
#
# Size comes from the graph's ResolutionSelector — pick an aspect ratio and a
# megapixel budget rather than raw pixels. Setting width/height instead replaces
# the selector with literals.
#
# duration is seconds; the frame count is duration x fps.
# enhance_prompt rewrites the prompt through a local LLM before encoding it.
routine: comfy
subroutine: video-ltx-text
type: video-ltx-text
output_prefix: video/example
aspect_ratio: "16:9 (Widescreen)"
megapixels: 0.9
duration: 5
fps: 24
enhance_prompt: true
# width: 1280          # overrides aspect_ratio/megapixels
# height: 720
---
prompt text
