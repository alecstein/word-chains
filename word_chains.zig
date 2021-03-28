const std = @import("std");
const input = @embedFile("words.txt");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const print = std.debug.print;
const eql = std.mem.eql;

pub fn main() !void {

    print("Starting Alec's\x1b[36m word-chain-finder\x1b[0m. Press Ctrl-C to exit.\n", .{});
    print("Usage: type in a start word and an end word to find the shortest path between them.\n", .{});


    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // instantiate allocator
    var galloc = &gpa.allocator; // retrieves the created allocator.

    var graph = try buildGraph(galloc); // build graph of words/neighbors
    defer graph.deinit();
    print("\nGraph built.", .{});

    while (true) { // main program

        print("\nEnter start word: ", .{}); // get user input
        var start_buf: [20]u8 = undefined; // and convert to lowercase
        const start_raw = try stdin.readUntilDelimiterOrEof(&start_buf, '\n');
        const start = try std.ascii.allocLowerString(galloc, start_raw.?);
        defer galloc.free(start);

        if (graph.get(start) == null) { // check if input is in graph
            print("\x1b[31mError:\x1b[0m {s} is not in the wordlist.", .{start});
            continue;
        }

        print("Enter end word: ", .{});
        var end_buf: [20]u8 = undefined;
        const end_raw = try stdin.readUntilDelimiterOrEof(&end_buf, '\n');
        const end = try std.ascii.allocLowerString(galloc, end_raw.?);
        defer galloc.free(end);

        if (graph.get(end) == null) {
            print("\x1b[31mError:\x1b[0m {s} is not in the wordlist.", .{end});
            continue;
        }

        // check if the two words are the same
        if (eql(u8, start, end)) {
            print("\x1b[31mError:\x1b[0m {s} and {s} are the same word.", .{start, end});
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

    // if words are distance == 1 apart, make them neighbors of each other
    for (words.items) |outer_word, i| {
        if (i % 1000 == 0) {
            print("Building graph of word distances: {d}%...\r", .{i*100/words.items.len}); 
            }
        for (words.items) |inner_word, j| {
            if (j == i) break;
            if (unitEditDistance(inner_word, outer_word)) {
                var outerEntry = graph.getEntry(outer_word).?;
                var innerEntry = graph.getEntry(inner_word).?;
                try outerEntry.value.append(inner_word);
                try innerEntry.value.append(outer_word);
            }
        }
    }
    print("Building graph of word distances: 100%...\r", .{});
    return graph;
}

fn breadthFirstSearch(allocator: *std.mem.Allocator, graph: std.StringHashMap(std.ArrayList([]const u8)), start: []const u8, end: []const u8) !void {

    // initialize a queue datastructure
    const Q = std.TailQueue(std.ArrayList([]const u8));
    var queue = Q{};

    var start_array = std.ArrayList([]const u8).init(allocator);
    try start_array.append(start);
    // var start_pos = Q.Node{ .data = start_array };
    // queue.append(&start_pos);
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
                        print("\x1b[32m{s}\x1b[0m\n", .{word});
                    }
                    return;
                }
            }
        }
        try explored.put(node);
    }
    print("\nDid not find path.\n", .{});
}

fn unitEditDistance(start: []const u8, end: []const u8) bool {

    // mafiaboss absolute value calculation
    // if strings are greater than distance 2 apart, return false

    if (std.math.max(start.len, end.len) - std.math.min(start.len, end.len) > 1) {
        return false;
    }

    var diff: u8 = 0;
    var i: usize = 0;
    var j: usize = 0;

    while (i < start.len and j < end.len) {
        if (start[i] != end[j]) {
            diff += 1;
            if (diff > 1) {
                return false;
            }
            if (start.len > end.len) {
                i += 1;
            } else if (start.len < end.len) {
                j += 1;
            } else {
                i += 1;
                j += 1;
            }
        } else {
            i += 1;
            j += 1;
        }
    }
    return true;
}