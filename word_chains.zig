const std = @import("std");
const input = @embedFile("words_med.txt");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const print = std.debug.print;
const eql = std.mem.eql;
const ansiCyan = "\x1b[36;1m";
const ansiGreen = "\x1b[32;1m";
const ansiRed = "\x1b[31;1m";
const ansiEnd = "\x1b[0m";

pub fn main() !void {

    print("Starting Alec's {s}word-chain-finder{s}. Press Ctrl-C to exit.\n", .{ ansiCyan, ansiEnd });
    print("Usage: type in a start word and an end word to find the shortest path between them.\n", .{});

    // instantiate allocator and then retrieve it

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var galloc = &gpa.allocator;

    // build graph of words/neighbors

    var graph = try buildGraph(galloc);
    defer graph.deinit();

    // main loop

    while (true) {

        // get user input and convert to lowercase
        // check if the words are in the dicitonary before starting search

        print("\nEnter start word: ", .{});

        var start_buf: [20]u8 = undefined;
        const start_raw = try stdin.readUntilDelimiterOrEof(&start_buf, '\n');
        const start = try std.ascii.allocLowerString(galloc, start_raw.?);
        defer galloc.free(start);

        // check if input is in graph

        if (graph.get(start) == null) {
            print("{s}Error:{s} {s} is not in the dictionary.", .{ ansiRed, ansiEnd, start });
            continue;
        }

        print("Enter end word: ", .{});
        var end_buf: [20]u8 = undefined;
        const end_raw = try stdin.readUntilDelimiterOrEof(&end_buf, '\n');
        const end = try std.ascii.allocLowerString(galloc, end_raw.?);
        defer galloc.free(end);

        if (graph.get(end) == null) {
            print("{s}Error:{s} {s} is not in the dictionary.", .{ ansiRed, ansiEnd, end });
            continue;
        }

        // check if the two words are the same

        if (eql(u8, start, end)) {
            print("{s}Error:{s} {s} and {s} are the same word.", .{ ansiRed, ansiEnd, start, end });
            continue;
        }

        try breadthFirstSearch(galloc, graph, start, end);
    }
}

fn buildGraph(allocator: *std.mem.Allocator) !std.StringHashMap(std.ArrayList([]const u8)) {

    // initialize graph

    var graph = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    // initialize list of words and put them in array

    var words = std.ArrayList([]const u8).init(allocator);
    defer words.deinit();

    // read the words from the file and put them into the graph (graph)
    // and the words list (words)

    var file_it = std.mem.tokenize(input, "\n");
    while (file_it.next()) |word| {
        try words.append(word);
        var empty_arr = std.ArrayList([]const u8).init(allocator);
        try graph.put(word, empty_arr);
    }

    // fast string comparison algorithm
    // if we know that the strings are at most distance one apart
    // we can sort the strings and keep track of their distances
    // only comparing strings that are at most one letter different
    // in length

    var words_sorted = words.toOwnedSlice();
    std.sort.sort([]const u8, words_sorted, {}, strLenComp);
    var k: usize = 0;
    for (words_sorted) |long_word, i| {
        var j = k;
        if (i % 1000 == 0) {
            print("Calculating word distances: {d}%\r", .{i * 100 / words_sorted.len});
        }
        while (j < i) : (j += 1) {
            const short_word = words_sorted[j];
            if (long_word.len - short_word.len > 1) {
                k += 1;
            }
            else if (unitEditDistance(long_word, short_word)) {

                var longEntry = graph.getEntry(long_word).?;
                try longEntry.value.append(short_word);

                var shortEntry = graph.getEntry(short_word).?;
                try shortEntry.value.append(long_word);
            }
        }
    }
    print("Calculating word distances: {s}DONE{s}\r", .{ ansiGreen, ansiEnd });
    return graph;
}

fn breadthFirstSearch(allocator: *std.mem.Allocator, graph: std.StringHashMap(std.ArrayList([]const u8)), start: []const u8, end: []const u8) !void {

    // initialize a queue datastructure

    const Q = std.TailQueue(std.ArrayList([]const u8));
    var queue = Q{};

    var start_array = std.ArrayList([]const u8).init(allocator);
    try start_array.append(start);
    var initial_node = try allocator.create(Q.Node);
    initial_node.data = start_array;
    queue.append(initial_node);

    var explored = std.BufSet.init(allocator);
    defer explored.deinit();

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

                if (eql(u8, neighbor, end)) {
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

    // fast unit edit distance calculation
    // returns true if long and short are
    // one edit apart (levenshtein).
    // assumptions:
    // 1) long.len >= short.len
    // and
    // 2) long.len - short.len <= 1
    // (1) and (2) are imposed by the sorting
    // condition and while loop in buildGraph()

    var diff: u8 = 0;
    var i: usize = 0;
    var j: usize = 0;

    while (i < start.len) : (i += 1) {
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