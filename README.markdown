FINF Is Not Forth
=================

What is it?
-----------

FINF is a simple implementation for a FORTH-like language for the Arduino platform. It is free software, released under GNU GPL version 2.

Current version weighs about 7kB of object code, making it suitable even for less beefier Arduinos, such as the ones based on the Atmega168 microcontrollers (even though it runs out of memory quickly and starts to behave weirdly).

FINF is not meant to support a significant amount of the standard FORTH library; it is more of a programming exercise than a implementation of a real language and programming environment. It was coded mostly in a couple of hours, with quick tests here and there. Expect it to be unstable and give erroneous results.

Screenshot
----------

This screenshot demonstrates a build with TERMINAL defined. This adds primitive support to use FINF over a VT100-compatible serial terminal, including some commonly used shortcut keys, like Ctrl+W to erase the last word, Ctrl+L to clear the screen, or Ctrl+C to abort current line. It also adds some color to help understand better the output.

![screenshot!](http://i.imgur.com/TorgV.png)
