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

# How does it work?

Each time you run the program `word_chains` builds a graph. Each node in the graph is a word, and each word is connected to all the other words that it's distance 1 away from. Then, `word_chains` does a breadth-first search to go from the start word `start` to the target word `end`.

By changing the `words.txt` file you can use any words you like, in any language. `words.txt` contains about 80k American English words. By using a smaller dictionary you can make the program run faster. 