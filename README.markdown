FINF Is Not Forth
=================

*** This project needs to be rewritten so it's easier to read and extend. If you're up to the task, contact the author, as he already has some ideas that might help you ***


What is it?
-----------

FINF is a simple implementation for a FORTH-like language for the Arduino platform. It is free software, released under GNU GPL version 2.

Current version weighs about 8kB of object code (8.8kB if built with TERMINAL defined), making it suitable even for less beefier Arduinos, such as the ones based on the Atmega168 microcontrollers (even though it runs out of memory quickly and starts to behave weirdly).

FINF is not meant to support a significant amount of the standard FORTH library; it is more of a programming exercise than a implementation of a real language and programming environment. It was coded mostly in a couple of hours, with quick tests here and there. Expect it to be unstable and give erroneous results.

Screenshot
----------

This screenshot demonstrates a build with TERMINAL defined. This adds primitive support to use FINF over a VT100-compatible serial terminal, including some commonly used shortcut keys, like Ctrl+W to erase the last word, Ctrl+L to clear the screen, or Ctrl+C to abort current line. It also adds some color to help understand better the output.

![terminal mode screenshot!](http://i.imgur.com/TorgV.png)

Without TERMINAL defined, it is really only usable on a client-buffered terminal emulator, such as Arduino's Serial Monitor; even then, it is not so pleasant to use:

![serial monitor screenshot!](http://i.imgur.com/U2itX.png)

Example
-------

The blinking example can be cut and pasted from the code below. The word 'blinkf' will blink the LED forever (or until the user presses ^C).

    1 13 pinmode
    : led 13 digwrite;
    : on 1 led;
    : off 0 led;
    : w 100 delay;
    : blink 0 begin on w off w 1 + dup 10 = negate until;
    : blinkf begin on w off w 1 until;
    blink
