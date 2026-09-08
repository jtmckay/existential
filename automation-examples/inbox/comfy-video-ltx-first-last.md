---
# LTX-2.5 first-and-last-frame to video, with audio: the run is anchored to
# input_image at the start and last_image at the end, and the prompt describes
# how it gets from one to the other.
#
# This graph has no ResolutionSelector — width/height are the size knob.
routine: comfy
subroutine: video-ltx-first-last
type: video-ltx-first-last
input_image: example-first.png
last_image: example-last.png
output_prefix: video/example
width: 1280
height: 720
duration: 5
fps: 24
enhance_prompt: true
---
prompt text
