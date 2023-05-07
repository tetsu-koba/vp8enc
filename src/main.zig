const std = @import("std");
const IVF = @import("ivf.zig");
const VP8Enc = @import("vp8enc.zig").VP8Enc;

pub fn main() !void {
    const alc = std.heap.page_allocator;

    var yuv_file = try std.fs.cwd().openFile("input.yuv", .{});
    defer yuv_file.close();

    var outfile = try std.fs.cwd().createFile("output.ivf", .{});
    defer outfile.close();

    const width: u32 = 160;
    const height: u32 = 120;
    const bitrate: u32 = 1000;
    const framerate: u32 = 15;
    const time_scale: u32 = 1;
    const keyframe_interval: u32 = 60;

    const ivf_header = IVF.IVFHeader{
        .signature = .{ 'D', 'K', 'I', 'F' },
        .version = 0,
        .header_size = 32,
        .fourcc = .{ 'V', 'P', '8', '0' }, //"VP80",
        .width = width,
        .height = height,
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
        try ivf_writer.writeIVFFrame(buf, frame_count);
        frame_count += 1;
    }
}
