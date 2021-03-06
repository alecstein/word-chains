const std = @import("std");
const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();
const print = stdout.writer().print;

// Store words in variable "input"
const input = @embedFile("words_short.txt"); 

// Escape codes used for printing
const ansiCyan = "\x1b[36;1m";
const ansiGreen = "\x1b[32;1m";
const ansiRed = "\x1b[31;1m";
const ansiEnd = "\x1b[0m";

pub fn main() !void {
    try print("Starting Alec's {s}word-chain-finder{s}. Press Ctrl-C to exit.\n", .{ ansiCyan, ansiEnd });
    try print("Usage: type in a start word and an end word to find the shortest path between them.\n", .{});
    try print("Note: A 'path' is a sequence that consists of either adding, removing, or changing a letter.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var gpa_alloc = &gpa.allocator;

    var graph = try buildGraph(gpa_alloc);
    defer {
        var it = graph.iterator();
        while (it.next()) |kv| {
            kv.value.deinit();
        }
        graph.deinit();
    }

    // Main loop
    // NOTE: Arena allocator can be initialized inside the loop to free
    // everything at once. Is this the right idea? Seems to simplify
    // a lot.

    while (true) {
        try print("\nEnter start word: ", .{});

        var start_buf: [20]u8 = undefined;
        const start_raw = try stdin.reader().readUntilDelimiterOrEof(&start_buf, '\n');

        const start = try std.ascii.allocLowerString(gpa_alloc, start_raw.?);
        defer gpa_alloc.free(start);

        if (graph.get(start) == null) {
            try print("{s}Error:{s} {s} is not in the wordlist.", .{ ansiRed, ansiEnd, start });
            continue;
        }

        try print("Enter end word: ", .{});

        var end_buf: [20]u8 = undefined;
        const end_raw = try stdin.reader().readUntilDelimiterOrEof(&end_buf, '\n');

        const end = try std.ascii.allocLowerString(gpa_alloc, end_raw.?);
        defer gpa_alloc.free(end);

        if (graph.get(end) == null) {
            try print("{s}Error:{s} {s} is not in the wordlist.", .{ ansiRed, ansiEnd, end });
            continue;
        }

        if (std.mem.eql(u8, start, end)) {
            try print("{s}Error:{s} {s} and {s} are the same word.", .{ ansiRed, ansiEnd, start, end });
            continue;
        }

        // Not sure why the arena allocator works better than the GPA.
        var arena = std.heap.ArenaAllocator.init(gpa_alloc);
        defer arena.deinit();

        try breadthFirstSearch(&arena.allocator, graph, start, end);
    }
}

fn buildSortedWordList(allocator: *std.mem.Allocator) ![][]const u8 {
    var words = std.ArrayList([]const u8).init(allocator);
    defer words.deinit();

    var file_it = std.mem.tokenize(input, "\n");
    while (file_it.next()) |word| {
        try words.append(word);
    }

    const wordlist = try bucketSortString(allocator, words);
    return wordlist;
}

fn buildGraph(allocator: *std.mem.Allocator) !std.StringHashMap(std.ArrayList([]const u8)) {
    const wordlist = try buildSortedWordList(allocator);
    defer allocator.free(wordlist);

    var graph = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    for (wordlist) |word| {
        var empty_arraylist = std.ArrayList([]const u8).init(allocator);
        try graph.put(word, empty_arraylist);
    }

    // If you want to build the graph quickly... you need a
    // Fast Graph-Building Algorithm (or "FigBA")
    // ------------------------------------------
    // Doing a double-for loop over ~50k variables is painfully slow.
    // If we know that the strings are at most distance one apart
    // we can sort the strings, and compare only the strings that
    // are at most one letter different in length.

    // Start by sorting the words by length. We can use the
    // bucket sort algorithm (implemented below). This runs
    // in O(N) time.

    // Then introduct a variable "k" to keep track of the smallest
    // word that's length one away from the current word being tested.

    var k: usize = 0;

    for (wordlist) |long_word, i| {

        // j starts at k and finishes at i-1. a word is compared
        // only with the words of equal length or of length one
        // less than it, not including itself. this avoids a complete
        // double for-loop.
        var j = k;

        // perc is percent complete, used to tell the user
        // how far along the graph is to being built

        const perc: usize = i * 100 / wordlist.len;
        if (i % 1000 == 0) {
            try print("Calculating word distances: {d}%\r", .{perc});
        }

        while (j < i) : (j += 1) {
            const short_word = wordlist[j];

            // If the long word is more than 1 longer than the
            // short word, keep increasing k (continuing through
            // this loop also increases j).

            if (long_word.len - short_word.len > 1) {
                k += 1;
            }

            // If len(long_word) = len(short_word) (or +1)
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

    try print("Calculating word distances: {s}DONE!{s}\r", .{ ansiGreen, ansiEnd });

    return graph;
}

fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            next: ?*Node = null,
            data: T,
        };

        first: ?*Node = null,
        last: ?*Node = null,
        len: usize = 0,

        pub fn insert(list: *Self, node: *Node) void {
            if (list.len == 0) {
                list.first = node;
            } else {
                list.last.?.next = node;
            }
            list.last = node;
            list.len += 1;
        }

        pub fn pop(list: *Self) ?*Node {
            const first = list.first orelse return null;
            if (list.len == 1) {
                list.first = null;
                list.last = null;
            } else {
                list.first = first.next;
            }
            list.len -= 1;
            return first;
        }
    };
}

fn breadthFirstSearch(allocator: *std.mem.Allocator, graph: std.StringHashMap(std.ArrayList([]const u8)), start: []const u8, end: []const u8) !void {
    const Q = Queue([][]const u8);
    var queue = Q{};
    defer {
        while (queue.pop()) |node| {
            allocator.free(node.data);
            allocator.destroy(node);
        }
    }

    var init_path = try allocator.alloc([]const u8, 1);
    init_path[0] = start;

    var init_node = try allocator.create(Q.Node);
    init_node.data = init_path;

    // There's no need to free/destroy the initial data/node,
    // because the For loop takes care of it on the first pass
    // through. So these two lines are unnecessary:
    // defer allocator.free(init_path);
    // defer allocator.destroy(init_node);

    queue.insert(init_node);

    var explored = std.BufSet.init(allocator);
    defer explored.deinit();

    while (queue.len > 0) {
        const node = queue.pop().?;
        defer {
            allocator.free(node.data);
            allocator.destroy(node);
        }

        const path = node.data;
        const last_vertex = path[path.len - 1];

        if (!explored.exists(last_vertex)) {
            const neighbors = graph.get(last_vertex).?;

            for (neighbors.items) |neighbor| {
                var new_path = try allocator.alloc([]const u8, path.len + 1);

                for (path) |vertex, i| {
                    new_path[i] = vertex;
                }

                new_path[path.len] = neighbor;

                var new_path_node = try allocator.create(Q.Node);

                new_path_node.data = new_path;
                queue.insert(new_path_node);

                if (std.mem.eql(u8, neighbor, end)) {
                    try print("Found the shortest path. Length: {s}{}{s}\n\n", .{ ansiGreen, new_path.len, ansiEnd });

                    for (new_path) |word| {
                        try print("{s}{s}{s}\n", .{ ansiGreen, word, ansiEnd });
                    }
                    return;
                }
            }
        }
        try explored.put(last_vertex);
    }
    try print("{s}No path found.{s}", .{ ansiRed, ansiEnd });
}

fn unitEditDistance(long: []const u8, short: []const u8) bool {

    // Fast Unit Edit Distance Decider (F.E.U.D(d))
    // -----------------------------------
    // Returns true if long and short are
    // one (Levenshtein) edit apart.
    // Assumptions:
    // 1) long.len >= short.len
    // 2) long.len - short.len <= 1
    // 3) long != short (at least one difference exists)
    // (1), (2), and (3) are imposed by the sorting
    // condition and while loop in buildGraph()
    var diff: u8 = 0;
    var i: usize = 0;
    var j: usize = 0;

    while (i < long.len and j < short.len) : (i += 1) {
        if (long[i] != short[j]) {
            diff += 1;
            if (diff > 1) {
                return false;
            }
            if (long.len == short.len) {
                j += 1;
            }
        } else {
            j += 1;
        }
    }
    return true;
}

fn bucketSortString(allocator: *std.mem.Allocator, words: std.ArrayList([]const u8)) ![][]const u8 {

    // Takes a list of strings and sorts them by length.

    // Start by getting the maximum string length (maxlen)
    var maxlen: usize = 1;
    for (words.items) |word| {
        if (word.len > maxlen) {
            maxlen = word.len;
        }
    }

    // Then make the buckets. each one is a variable-length
    // array.

    var buckets = try allocator.alloc(std.ArrayList([]const u8), maxlen);
    defer {
        for (buckets) |arrlist| {
            arrlist.deinit();
        }
        allocator.free(buckets);
    }

    // Bucket 0 corresponds to length 1 and so on.

    var i: usize = 0;
    while (i < maxlen) : (i += 1) {
        var arrayList = std.ArrayList([]const u8).init(allocator);
        buckets[i] = arrayList;
    }

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

// test "pop on an empty queue returns null" {
//     const Q = Queue(u8);
//     var queue = Q{};
//     std.testing.expect(queue.pop() == null);
// }
// test "pop on a queue with one element returns that element" {
//     const Q = Queue(u8);
//     var queue = Q{};
//     var node = try std.testing.allocator.create(Q.Node);
//     defer std.testing.allocator.destroy(node);
//     node.data = 9;
//     queue.insert(node);
//     const x = queue.pop();
//     std.testing.expect(x == node);
//     std.testing.expect(x.?.data == 9);
// }
// test "size of an empty queue is 0" {
//     const Q = Queue(u8);
//     var queue = Q{};
//     std.testing.expect(queue.len == 0);
// }
// test "size of queue with one element inserted is one" {
//     const Q = Queue(u8);
//     var queue = Q{};
//     var node = try std.testing.allocator.create(Q.Node);
//     defer std.testing.allocator.destroy(node);
//     node.data = 9;
//     queue.insert(node);
//     std.testing.expect(queue.len == 1);
// }
// test "first in is first out" {
//     const Q = Queue(u8);
//     var queue = Q{};
//     var node1 = try std.testing.allocator.create(Q.Node);
//     defer std.testing.allocator.destroy(node1);
//     var node2 = try std.testing.allocator.create(Q.Node);
//     defer std.testing.allocator.destroy(node2);
//     var node3 = try std.testing.allocator.create(Q.Node);
//     defer std.testing.allocator.destroy(node3);
//     node1.data = 1;
//     node2.data = 2;
//     node3.data = 3;
//     queue.insert(node1);
//     queue.insert(node2);
//     queue.insert(node3);
//     std.testing.expect(queue.pop() == node1);
//     print("ok1", .{});
//     std.testing.expect(queue.pop() == node2);
//     print("ok2", .{});
//     std.testing.expect(queue.pop() == node3);
//     print("ok3", .{});
//     std.testing.expect(queue.pop() == null);
// }

// test "memory leak" {
//     const Q = Queue(u8);
//     var queue = Q{};
//     var node1 = try std.testing.allocator.create(Q.Node);
//     // defer std.testing.allocator.destroy(node1);
//     var node2 = try std.testing.allocator.create(Q.Node);
//     // defer std.testing.allocator.destroy(node2);
//     var node3 = try std.testing.allocator.create(Q.Node);
//     // defer std.testing.allocator.destroy(node3);
//     node1.data = 1;
//     node2.data = 2;
//     node3.data = 3;
//     queue.insert(node1);
//     queue.insert(node2);
//     queue.insert(node3);
//     while (queue.pop()) |node| {
//         std.testing.allocator.destroy(node);
//     }
// }

// test "buildGraph memory leak" {
//     var graph = try buildGraph(std.testing.allocator);
//     defer {
//         var it = graph.iterator();
//         while (it.next()) |kv| {
//             kv.value.deinit();
//         }
//         graph.deinit();
//     }

//     try breadthFirstSearch(std.testing.allocator, graph, "test", "end");
// }

// test "building the word list" {
//     const x = try buildSortedWordList(std.testing.allocator);
//     defer std.testing.allocator.free(x);
// }

// test "memory leak with arena allocator" {
//     try main();
// }

test "copy a slice" {
    const tst_string = "string";
    const byte_arr = [_]u8{1,2,3};
    var tst_str_array = [_][]const u8{"string1", "string2"}; // length 2 array of strings
    var tst_empty_str_array = [_][]const u8{}; // length 0 array of strings    
    const tst_empty_str_array_slice = tst_empty_str_array[0..];
    // std.debug.print("{}", tst_empty_str_array[0]);  // error
    tst_str_array[0] = "helloman";
    for (tst_str_array) |x| {
        std.debug.print("{s}\n", .{x});
    }
    var tst_empty_slice_arr: [][]const u8 = undefined;
    tst_empty_slice_arr = tst_str_array[0..];
    // var x = tst_empty_str_array_slice + 1;
    var tst_empty_array: [_][]const u8 = undefined;

}