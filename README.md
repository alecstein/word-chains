# How to use this software

To build, do:

> zig build-exe word_chains.zig -O ReleaseFast

# What does it do?

A friend asked me to solve the following puzzle: how do you get from the word "war" to "peace" by either adding, deleting, or changing a letter, and after each move, making a new English word. The solution is:

war
par
pare
pace
peace

`word_chains` finds chains of words each connected by one letter differences. In other words, it solves the general case of the war/peace puzzle.