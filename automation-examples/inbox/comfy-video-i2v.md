---
# Wan 2.2 14B image-to-video: input_image is the first frame.
# `length` is a frame count, not seconds — 133 frames is the workflow's own.
routine: comfy
subroutine: video-i2v
type: video-i2v
input_image: example.png
output_prefix: video/example
width: 640
height: 640
length: 133
---
prompt text
