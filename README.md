# What does this do?

A friend asked me to solve the following puzzle: 

> Get from the word "war" to "peace" by making a sequence of moves: either adding, deleting, or changing a letter. Each move must result in a new English word.

The shortest solution (path from "war" to "peace") is: 

`war --> par --> pare --> pace --> peace.`

`word_chains` finds chains of words each connected by one letter differences. In other words, it solves the general case of the war/peace puzzle.

# How do I run the program?

If you want to compile `word_chains` yourself, you need to have `zig` installed:

```
$ brew install zig
```

Then to build, open the terminal and type

```
$ zig build-exe word_chains.zig -O ReleaseFast
```

Then follow the prompts. Try typing in "war" and then "peace" for example. 

# How does it work?

Each time you run `word_chains` it builds a graph. Each node in the graph is a word, and each word is connected to all the other words that it's distance 1 away from. Then, `word_chains` does a breadth-first search to go from the start word `start` to the target word `end`. It prints the first result it finds (necessarily the shortest path). It will run exhaustively, which means if no path exists, `word_chains` will figure that out too.

By changing the `words.txt` file you can use any words you like, in any language. `words.txt` contains about 80k American English words. By using a smaller dictionary you can make the program run faster. 

# Why?

For fun.