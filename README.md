canvasanim
==========

No good idea ever goes un-stolen, and it's in that spirit that I present
CanvasAnim, a simple HTML5 canvas animation player. CanvasAnim uses a 
combination of JS and the HTML5 canvas tag to play back animations stored
as static image files. It's nowhere near as efficient as using an actual
video file, but for short animations or videos, it works well enough, and
more importantly, it works consistently (and inline!) on a wide range of
browsers and devices.

The idea comes from Apple's iPhone 5 website, and the analysis of it [here](https://docs.google.com/document/pub?id=1GWTMLjqQsQS45FWwqNG9ztQTdGF48hQYpjQHR_d1WsI).

## How it works ##
Like most video solutions, the idea here is to take a series of frames and encode them so that
only the differences between successive frames are actually stored. In our case, we chop frames
in to 8x8 pixel blocks, and then compare the blocks in each frame with their corresponding blocks
in the previous frame. Any blocks that differ are stored sequentially in to a single, large image.

To piece things back together at playback, we store a bitmap for each frame, with a 0 for each
block that remains unchanged, and a 1 for each block that differs. These bitmaps are encoded as
hex strings (4 bits per character) and then run-length encoded to keep them (mostly) fairly small.

## Encoding ##

The first step is to convert your video in to the appropriate format, using the
"encode.rb" script -- this requires a JSON parser and ChunkyPNG. Actually, the first
step is probably to convert your video in to the series of PNG images that "encode.rb"
expects. If you have FFMPEG installed, this is a cinch:

    mkdir videoframes
    ffmpeg -i input.avi videoframes/frame%05d.png

Then, run "encode.rb" like so:

    ./encode.rb outputname videoframes

Ruby and ChunkyPNG aren't the fastest tools in the universe, so this may take some time --
for a 480x320 video, expect it to take about 3 minutes per 100 frames. At the end, you'll
get these files:

* outputname_first.png -- a verbatim copy of the first frame of your video
* outputname_blocks.png -- a file containing frame deltas as a series of 8x8 pixel blocks
* outputname_data.js -- a JS script containing the metadata required to turn the above in to an actual animation

The bulk of the "_data.js" file is the frame bitmaps. 

## Usage ##
