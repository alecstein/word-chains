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
    var gpa_alloc = &gpa.allocator;

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();

    var arena_alloc = &arena.allocator;

    var graph = try buildGraph(arena_alloc);
    defer {
        var it = graph.iterator();
        while (it.next()) |kv| {
            kv.value.deinit();
        }
        graph.deinit();
    }

    // main loop

    while (true) {

        // get user input and convert to lowercase
        // check if the words are in the dicitonary before starting search

        print("\nEnter start word: ", .{});

        var start_buf: [20]u8 = undefined;
        const start_raw = try stdin.readUntilDelimiterOrEof(&start_buf, '\n');
        
        const start = try std.ascii.allocLowerString(gpa_alloc, start_raw.?);
        defer gpa_alloc.free(start);

        // check if input is in graph

        if (graph.get(start) == null) {
            print("{s}Error:{s} {s} is not in the dictionary.", .{ ansiRed, ansiEnd, start });
            continue;
        }

        print("Enter end word: ", .{});

        var end_buf: [20]u8 = undefined;
        const end_raw = try stdin.readUntilDelimiterOrEof(&end_buf, '\n');

        const end = try std.ascii.allocLowerString(gpa_alloc, end_raw.?);
        defer gpa_alloc.free(end);

        if (graph.get(end) == null) {
            print("{s}Error:{s} {s} is not in the dictionary.", .{ ansiRed, ansiEnd, end });
            continue;
        }

        if (std.mem.eql(u8, start, end)) {
            print("{s}Error:{s} {s} and {s} are the same word.", .{ ansiRed, ansiEnd, start, end });
            continue;
        }

        // the arena allocator works fastest for the search algorithm.
        // i'm not sure why.

        try breadthFirstSearch(arena_alloc, graph, start, end);
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
    defer allocator.free(words_sorted);

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

fn QueueFIFO(comptime T: type) type {

    // simple FIFO queue largely copied from TailQueue in linked_list.zig.
    // basic usage is with two functions: addFirst and popLast. 
    // addFirst puts a Node at the front of the queue, and popLast
    // returns and removes the last element of the queue. 

    return struct {
        const Self = @This();

        pub const Node = struct {
            prev: ?*Node = null,
            next: ?*Node = null,
            data: comptime T,
        };

        first: ?*Node = null,
        last: ?*Node = null,
        len: usize = 0,

        pub fn insertBefore(list: *Self, node: *Node, new_node: *Node) void {
            new_node.next = node;
            if (node.prev) |prev_node| {
                // Intermediate node.
                new_node.prev = prev_node;
                prev_node.next = new_node;
            } else {
                // First element of the list.
                new_node.prev = null;
                list.first = new_node;
            }
            node.prev = new_node;

            list.len += 1;
        }

        pub fn remove(list: *Self, node: *Node) void {
            if (node.prev) |prev_node| {
                // Intermediate node.
                prev_node.next = node.next;
            } else {
                // First element of the list.
                list.first = node.next;
            }

            if (node.next) |next_node| {
                // Intermediate node.
                next_node.prev = node.prev;
            } else {
                // Last element of the list.
                list.last = node.prev;
            }

            list.len -= 1;
            std.debug.assert(list.len == 0 or (list.first != null and list.last != null));
        }

        pub fn addFirst(list: *Self, new_node: *Node) void {
            if (list.first) |first| {
                // Insert before first.
                list.insertBefore(first, new_node);
            } else {
                // Empty list.
                list.first = new_node;
                list.last = new_node;
                new_node.prev = null;
                new_node.next = null;

                list.len = 1;
            }
        }
        
        pub fn popLast(list: *Self) ?*Node {
            const last = list.last orelse return null;
            list.remove(last);
            return last;
        }
    };
}

fn breadthFirstSearch(allocator: *std.mem.Allocator, graph: std.StringHashMap(std.ArrayList([]const u8)), start: []const u8, end: []const u8) !void {

    const Q = QueueFIFO([][]const u8);
    var queue = Q{};

    var init_path = try allocator.alloc([]const u8, 1);
    defer allocator.free(init_path);

    var init_node = try allocator.create(Q.Node);
    defer allocator.destroy(init_node);

    init_path[0] = start;

    init_node.data = init_path;
    queue.addFirst(init_node);

    var explored = std.BufSet.init(allocator);
    defer explored.deinit();

    defer {
        var it = queue.first;
        while (it) |node| : (it = node.next) {
            allocator.free(node.data);
            allocator.destroy(node);
        }
    }

    while (queue.len > 0) {

        const path = queue.popLast().?.data;
        const plen = path.len;
        const end_node = path[plen - 1];

        if (!explored.exists(end_node)) {

            const neighbors = graph.get(end_node).?;

            for (neighbors.items) |neighbor| {

                var new_path = try allocator.alloc([]const u8, plen + 1);

                for (path) |node, i| {  
                    new_path[i] = node;
                }

                new_path[plen] = neighbor;

                var new_path_node = try allocator.create(Q.Node);

                new_path_node.data = new_path;
                queue.addFirst(new_path_node);

                if (std.mem.eql(u8, neighbor, end)) {
                    print("Found the shortest path:\n\n", .{});

                    for (new_path) |word| {
                        print("{s}{s}{s}\n", .{ ansiGreen, word, ansiEnd });
                    }
                    return;
                }
            }
        }
        try explored.put(end_node);
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

    // takes a list of strings and sorts them by length.
    // uses the Bucket Sort algorithm

    // start by getting the maximum string length (maxlen)

    var maxlen: usize = 1; 
    for (words.items) |word| {
        if (word.len > maxlen) {
            maxlen = word.len;
        }
    }

    // then make the buckets. each one is a variable-length
    // array.

    var buckets = try allocator.alloc(std.ArrayList([]const u8), maxlen);
    defer {
        for (buckets) |arrlist| {
            arrlist.deinit();
        }
        allocator.free(buckets);
    }

    // bucket 0 corresponds to length 1 and so on.
    // each std.ArrayList needs to be initialized with
    // an allocator.

    var i: usize = 0;
    while (i < maxlen) : (i += 1 ) {
        var arrayList = std.ArrayList([]const u8).init(allocator);
        buckets[i] = arrayList;
    }

    // put the words in the buckets

    for (words.items) |word| {
        try buckets[word.len - 1].append(word);
    }

    var words_sorted = try allocator.alloc([]const u8, words.items.len);

    i = 0;
    for (buckets) |arrayList| {
        for (arrayList.items) |word| {
            words_sorted[i] = word;
            i += 1;
        }
    }

    return words_sorted;
}

test "buildGraph" {
    var graph = try buildGraph(std.testing.allocator);
    defer graph.deinit();

    var it = graph.iterator();
    while (it.next()) |kv| {
        kv.value.deinit();
    }
}