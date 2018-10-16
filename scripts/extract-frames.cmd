::  Given a video file (e.g. file.mov), extract the video frames and merge the frames into one long image file timeline.jpg.
::  Requires ImageMagick to be installed (with the ffmpeg option selected).
::  This script produces many .jpg files, so best to run this in a folder:
::  mkdir video
::  cd video
::  ..\scripts\extract-frames file.mov

::  Number of frames per second to extract from the video file.  If the video is long, reduce the frames per second e.g. 0.5.
set frames_per_second=1

::  Increase the value of overlap to merge the frames closer.  If the frames are too close and the LEDs are not visible, decrease the overlap.
set overlap=1000

::  Delete previous frames.
del frame-???????.jpg

::  Extract the frames into frame-8888888.jpg.
ffmpeg -i %1 -vf fps=%frames_per_second% frame-%%07d.jpg -hide_banner

::  Overlap and merge the frames into timeline.jpg.
magick frame-*.jpg -set page "+%%[fx:u[t-1]page.x+u[t-1].w-%overlap%]+%%[fx:u[t-1]page.y+0]" -background none -layers merge +repage timeline.jpg

::  Delete extracted frames.
del frame-???????.jpg

::  Preview timeline.jpg.
magick timeline.jpg win:
