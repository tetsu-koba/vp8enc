const std = @import("std");
const IVF = @import("ivf.zig");
const VP8Enc = @import("vp8enc.zig").VP8Enc;

pub fn I4202Vp8(input_file: []const u8, output_file: []const u8, width: u32, height: u32, framerate: u32, bitrate: u32, keyframe_interval: u32) !void {
    const alc = std.heap.page_allocator;

    var yuv_file = try std.fs.cwd().openFile(input_file, .{});
    defer yuv_file.close();

    var outfile = try std.fs.cwd().createFile(output_file, .{});
    defer outfile.close();

    const time_scale: u32 = 1;
    const ivf_header = IVF.IVFHeader{
        .signature = .{ 'D', 'K', 'I', 'F' },
        .version = 0,
        .header_size = 32,
        .fourcc = .{ 'V', 'P', '8', '0' }, //"VP80",
        .width = @intCast(u16, width),
        .height = @intCast(u16, height),
        .frame_rate = framerate,
        .time_scale = time_scale,
        .num_frames = 0,
        .unused = 0,
    };
    var ivf_writer = try IVF.IVFWriter.init(outfile, &ivf_header);
    defer ivf_writer.deinit();

    const yuv_size = width * height * 3 / 2;
    var yuv_buf = try alc.alloc(u8, yuv_size);
    defer alc.free(yuv_buf);

    var vp8enc = try VP8Enc.init(width, height, framerate, time_scale, bitrate, keyframe_interval, yuv_buf);
    defer vp8enc.deinit();

    var frame_count: u32 = 0;
    while (true) {
        if (yuv_size != try yuv_file.readAll(yuv_buf)) {
            break;
        }
        const buf = try vp8enc.encode(frame_count);
        ivf_writer.writeIVFFrame(buf, frame_count) catch |err| {
            switch (err) {
                error.BrokenPipe => {},
                else => {
                    std.log.err("frameHandle: {s}", .{@errorName(err)});
                },
            }
            break;
        };
        frame_count += 1;
    }
}

pub fn main() !void {
    const usage = "Usage: {s} input_file output_file width height framerate kbps keyframe_interval\n";
    const alc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alc);
    defer std.process.argsFree(alc, args);

    if (args.len < 8) {
        std.debug.print(usage, .{args[0]});
        std.os.exit(1);
    }
    const input_file = args[1];
    const output_file = args[2];
    const width = try std.fmt.parseInt(u32, args[3], 10);
    const height = try std.fmt.parseInt(u32, args[4], 10);
    const framerate = try std.fmt.parseInt(u32, args[5], 10);
    const bitrate = try std.fmt.parseInt(u32, args[6], 10) * 1000;
    const keyframe_interval = try std.fmt.parseInt(u32, args[7], 10);

    try I4202Vp8(input_file, output_file, width, height, framerate, bitrate, keyframe_interval);
}
