# Odin + Raylib + Hot Reload template

A ffmpeg wrapper to palettize (posterize) and dither images. It's also possible to mask out areas. Useful to creating low-res textures for PS1 and N64 graphics and models. Written in Odin + Raylib.

## How to use
- Drag and drop an image
- Choose the amount of colors, check the desired post effects
- Click "Apply", a new image will be exported with post effects

### Masking
If you want to mask out areas from the posterize and dithering, click "Add Mask" and paint with the left mouse button. When applying the effects the masked areas will not be included (the palette used for the posterize won't have the colors from the masked out area either).

- Left mouse button: paint
- Right mouse button: erase
- Mouse wheel drag: pan the image
- Mouse wheel up and down: zoom in and out

You can also export only the masked areas with "Export Masked Area". Then later you run the posterize and dithering just for them (for that, just drag the exported masked image onto the program and apply the post processing).

## How to run
This is built with the [Odin + Raylib hot reload template](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template), you can run any of the `build_*.bat` and `build_*.sh` scripts.

Example: `./build_hot_reload.sh run`.

The main code is in `source/game.odin`.

## Requirements
`ffmpeg` must be in the `PATH`.