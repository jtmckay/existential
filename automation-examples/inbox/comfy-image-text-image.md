---
# Flux2 image-to-image: the same graph with the reference branch switched on.
# input_image is a filename ComfyUI already knows — anything under its input/
# folder, or "subdir/file.png [output]" to reuse something it generated.
routine: comfy
subroutine: image-text-image
type: image-text-image
input_image: example.png
output_prefix: images/example-edit
width: 1024
height: 1024
# seed: 12345          # omit to randomize
---
prompt text
