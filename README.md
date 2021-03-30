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

Then follow the prompts. Try typing in "war" and then "peace" for example:
    $ ./word_chains
    Starting Alec's **word-chain-finder**. Press Ctrl-C to exit.
    Usage: type in a start word and an end word to find the shortest path between them.
    Calculating word distances: **DONE!**
    Enter start word: war  
    Enter end word: peace
    Found the shortest path:
    **war**
    **par**
    **pare**
    **pace**
    **peace**

# How does it work?

Each time you run `word_chains` it builds a graph. Each node in the graph is a word, and each word is connected to all the other words that it's distance 1 away from. Then, `word_chains` does a breadth-first search to go from the start word `start` to the target word `end`. It prints the first result it finds (necessarily the shortest path). It will run exhaustively, which means if no path exists, `word_chains` will figure that out too.

By changing the `words_{size}.txt` files you can use any words you like. You can add words, or delete all of the them and change the language. `words_med.txt` contains about 40k American English words, including some proper nouns. By using a smaller dictionary you can make the program run faster.

# Why?

For fun. This is my first time writing code in a compiled language with manual memory management and I thought it might be more straightforward than learning C.

In the end, getting through the Zig docs was a challenge and I had to rely on friends and the #zig freenode channel for help. I definitely couldn't have built this basic application by myself and I owe a lot to my friends (Matt and Sam) who patiently learned with me.

This took me about 30-40 hours. I had to learn what an allocator was, how to allocate memory efficiently, how to use pointers, and how to read the Zig source. 

For comparison, the python version took me less than 30 minutes. 

# What next?

It would be nice to have the option to pre-build the graph at compile time so that you don't have to build it on every run.

Unfortunately I was not able to take advantage of Zig's `comptime` to freeze the graph building into the binary because there's no compile-time hashmap available. Writing the graph to file is an option, perhaps sometime down the line. 

Once I figured out the basics memory management I was able to get pretty far, and it turned out that speeding up the program came down to good memory management. I still think there's room to speed up the program, maybe by using a more efficient memory allocator. 

# Have suggestions?

Let me know. I'd love to make this code faster, more efficient, simpler, and more beautiful.