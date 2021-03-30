const std = @import("std");
const input = @embedFile("words_med.txt");
const stdin = std.io.getStdIn().reader();
const print = std.debug.print;

// escape codes used for printing

const ansiCyan = "\x1b[36;1m";
const ansiGreen = "\x1b[32;1m";
const ansiRed = "\x1b[31;1m";
const ansiEnd = "\x1b[0m";

pub fn main() !void {

    print("Starting Alec's {s}word-chain-finder{s}. Press Ctrl-C to exit.\n", .{ ansiCyan, ansiEnd });
    print("Usage: type in a start word and an end word to find the shortest path between them.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var galloc = &gpa.allocator;

    // also works with page_allocator

    var arena = std.heap.ArenaAllocator.init(galloc);
    defer arena.deinit();
    var aalloc = &arena.allocator;

    // build graph of words/neighbors

    var graph = try buildGraph(aalloc);
    defer graph.deinit();

    // main loop

    while (true) {

        // get user input and convert to lowercase
        // check if the words are in the dicitonary before starting search

        print("\nEnter start word: ", .{});

        var start_buf: [20]u8 = undefined;
        const start_raw = try stdin.readUntilDelimiterOrEof(&start_buf, '\n');
        const start = try std.ascii.allocLowerString(aalloc, start_raw.?);
        // defer galloc.free(start);

        // check if input is in graph

        if (graph.get(start) == null) {
            print("{s}Error:{s} {s} is not in the dictionary.", .{ ansiRed, ansiEnd, start });
            continue;
        }

        print("Enter end word: ", .{});
        var end_buf: [20]u8 = undefined;
        const end_raw = try stdin.readUntilDelimiterOrEof(&end_buf, '\n');
        const end = try std.ascii.allocLowerString(aalloc, end_raw.?);
        // defer galloc.free(end);

        if (graph.get(end) == null) {
            print("{s}Error:{s} {s} is not in the dictionary.", .{ ansiRed, ansiEnd, end });
            continue;
        }

        // check if the two words are the same

        if (std.mem.eql(u8, start, end)) {
            print("{s}Error:{s} {s} and {s} are the same word.", .{ ansiRed, ansiEnd, start, end });
            continue;
        }

        try breadthFirstSearch(aalloc, graph, start, end);
    }
}

fn buildGraph(allocator: *std.mem.Allocator) !std.StringHashMap(std.ArrayList([]const u8)) {

    var graph = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    // initialize list of words and put them in array
    // note: wordlist contains no duplicates

    var words = std.ArrayList([]const u8).init(allocator);
    defer words.deinit();

    // read the words from the file and put them into the graph (graph)
    // and the words list (words)
    // also: initialize the graph with empty arrays

    var file_it = std.mem.tokenize(input, "\n");
    while (file_it.next()) |word| {
        try words.append(word);
        var empty_arr = std.ArrayList([]const u8).init(allocator);
        try graph.put(word, empty_arr);
    }

    // fast graph-building algorithm
    // ------------------------------
    // if we know that the strings are at most distance one apart
    // we can sort the strings, and compare only the strings that
    // are at most one letter different in length

    // start by sorting the words by length. we can use the 
    // bucket sort algorithm (implemented below). this runs 
    // in O(N) time. 

    const words_sorted = try bucketSortString(allocator, words);

    // k keeps track of the first word in the sorted array
    // which is one less (in length) than the current (long) word.
    // this changes as the long word grows

    var k: usize = 0; 

    for (words_sorted) |long_word, i| {

        // j starts at k and finishes at i-1. a word is compared
        // only with the words of equal length or of length one
        // less than it, not including itself. this avoids a complete
        // double for-loop.

        var j = k;

        // perc is percent complete, used to tell the user
        // how far along the graph is to being built

        const perc: usize = i * 100 / words_sorted.len;
        if (i % 1000 == 0) {
           print("Calculating word distances: {d}%\r", .{perc});
        }

        while (j < i) : (j += 1) {

            const short_word = words_sorted[j];

            // if the long word is more than 1 longer than the
            // short word, keep increasing k (continuing through
            // this loop also increases j).

            if (long_word.len - short_word.len > 1) {
                k += 1;
            }

            // if the len(long_word) = len(short_word) (+1) 
            // then check if they're one edit distance apart.
            // if so, add to the graph.

            else if (unitEditDistance(long_word, short_word)) {

                var longEntry = graph.getEntry(long_word).?;
                try longEntry.value.append(short_word);

                var shortEntry = graph.getEntry(short_word).?;
                try shortEntry.value.append(long_word);
            }
        }
    }
    
    print("Calculating word distances: {s}DONE!{s}\r", .{ ansiGreen, ansiEnd });

    return graph;
}

fn breadthFirstSearch(allocator: *std.mem.Allocator, graph: std.StringHashMap(std.ArrayList([]const u8)), start: []const u8, end: []const u8) !void {

    // initialize a queue datastructure

    const Q = std.TailQueue(std.ArrayList([]const u8));
    var queue = Q{};

    var start_array = std.ArrayList([]const u8).init(allocator);
    defer start_array.deinit();

    try start_array.append(start);

    var initial_node = try allocator.create(Q.Node);
    initial_node.data = start_array;
    queue.append(initial_node);

    var explored = std.BufSet.init(allocator);
    defer explored.deinit();

    defer {
        var it = queue.first;
        while (it) |node| : (it = node.next) {
            node.data.deinit();
            allocator.destroy(node);
        }
    }

    while (queue.len > 0) {

        const path = queue.popFirst().?.data;

        // get the last item in the path
        const node = path.items[path.items.len - 1];

        if (!explored.exists(node)) {
            const neighbors = graph.get(node).?;

            for (neighbors.items) |neighbor| {

                var new_path = std.ArrayList([]const u8).init(allocator);

                for (path.items) |item| {
                    try new_path.append(item);
                }
                try new_path.append(neighbor);

                var new_path_node = try allocator.create(Q.Node);

                new_path_node.data = new_path;
                queue.append(new_path_node);

                if (std.mem.eql(u8, neighbor, end)) {
                    print("Found the shortest path:\n\n", .{});
                    for (new_path.items) |word| {
                        print("{s}{s}{s}\n", .{ ansiGreen, word, ansiEnd });
                    }
                    return;
                }
            }
        }
        try explored.put(node);
    }
    print("{s}No path found.{s}", .{ ansiRed, ansiEnd });
}

fn strLenComp(context: void, stra: []const u8, strb: []const u8) bool {

    // used for sorting the list of words

    if (strb.len > stra.len) {
        return true;
    } else {
        return false;
    }
}

fn unitEditDistance(start: []const u8, end: []const u8) bool {

    // fast unit edit distance resolver
    // -----------------------------------
    // returns true if long and short are
    // one edit apart (levenshtein).
    // assumptions:
    // 1) long.len >= short.len
    // 2) long.len - short.len <= 1
    // 3) long != short (at least one difference exists)
    // (1), (2), and (3) are imposed by the sorting
    // condition and while loop in buildGraph()

    var diff: u8 = 0;
    var i: usize = 0;
    var j: usize = 0;

    while (i < start.len and j < end.len) : (i += 1) {
        if (start[i] != end[j]) {
            diff += 1;
            if (diff > 1) {
                return false;
            }
            if (start.len == end.len) {
                j += 1;
            }
        } else {
            j += 1;
        }
    }
    return true;
}

fn bucketSortString(allocator: *std.mem.Allocator, words: std.ArrayList([]const u8)) ![][]const u8 {

    // takes a list of strings and sorts them by length
    // uses the Bucket Sort algorithm

    // get the maximum length in the array

    var maxlen: usize = 1; 
    for (words.items) |word| {
        if (word.len > maxlen) {
            maxlen = word.len;
        }
    }

    var buckets = try allocator.alloc(std.ArrayList([]const u8), maxlen);
    defer {
        for (buckets) |arrlist| {
            arrlist.deinit();
        }
        allocator.free(buckets);
    }

    // bucket 0 corresponds to length 1 and so on.
    // initialize each ArrayList

    var i: usize = 0;
    while (i < maxlen) : (i +=1 ) {
        var arrayList = std.ArrayList([]const u8).init(std.testing.allocator);
        buckets[i] = arrayList;
    }

    // put the words in the buckets

    for (words.items) |word| {
        try buckets[word.len - 1].append(word);
    }

    var sorted_words = try allocator.alloc([]const u8, words.items.len);

    i = 0;
    for (buckets) |arrayList| {
        for (arrayList.items) |word| {
            sorted_words[i] = word;
            i += 1;
        }
    }

    return sorted_words;
}