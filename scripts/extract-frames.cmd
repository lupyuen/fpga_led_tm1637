::ffmpeg -i img_4044.mov -vf fps=1 frame-%%07d.jpg -hide_banner

::  Increase the value of overlap to merge the frames closer.  If the frames are too close and the LEDs are not visible, decrease the overlap.
set overlap=800

magick frame-*.jpg -set page "+%%[fx:u[t-1]page.x+u[t-1].w-%overlap%]+%%[fx:u[t-1]page.y+0]" -background none -layers merge +repage timeline.jpg

magick timeline.jpg win:
