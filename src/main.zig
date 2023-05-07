const std = @import("std");
const vpx = @cImport({
    @cInclude("vpx/vpx_encoder.h");
    @cInclude("vpx/vp8cx.h");
});
const IVF = @import("ivf.zig");

const FILE = std.os.FILE;

pub fn main() !void {
    //const allocator = std.heap.page_allocator;

    var yuv_file = try std.fs.cwd().openFile("input.yuv", .{});
    defer yuv_file.close();

    var outfile = try std.fs.cwd().createFile("output.ivf", .{});
    defer outfile.close();

    const width: u32 = 160;
    const height: u32 = 120;
    const bitrate: u32 = 1000;
    const fps: u32 = 15;
    const keyframe_interval: u32 = 60;

    const ivf_header = IVF.IVFHeader{
        .signature = .{ 'D', 'K', 'I', 'F' },
        .version = 0,
        .header_size = 32,
        .fourcc = .{ 'V', 'P', '8', '0' }, //"VP80",
        .width = width,
        .height = height,
        .frame_rate = fps,
        .time_scale = 1,
        .num_frames = 0,
        .unused = 0,
    };
    var ivf_writer = try IVF.IVFWriter.init(outfile, &ivf_header);
    defer ivf_writer.deinit();

    var cfg: vpx.vpx_codec_enc_cfg_t = undefined;
    if (vpx.vpx_codec_enc_config_default(vpx.vpx_codec_vp8_cx(), &cfg, 0) != 0) {
        std.debug.print("Error getting default configuration\n", .{});
        return error.DefaultConfigurationError;
    }

    cfg.rc_target_bitrate = bitrate;
    cfg.g_w = width;
    cfg.g_h = height;
    cfg.g_timebase.num = 1;
    cfg.g_timebase.den = fps;
    cfg.g_error_resilient = 1;
    cfg.kf_min_dist = keyframe_interval;
    cfg.kf_max_dist = keyframe_interval;

    var codec: vpx.vpx_codec_ctx_t = undefined;
    if (vpx.vpx_codec_enc_init(&codec, vpx.vpx_codec_vp8_cx(), &cfg, 0) != 0) {
        std.debug.print("Error initializing codec\n", .{});
        return error.CodecInitializationError;
    }
    defer _ = vpx.vpx_codec_destroy(&codec);

    var raw = vpx.vpx_img_alloc(null, vpx.VPX_IMG_FMT_I420, width, height, 1);
    defer _ = vpx.vpx_img_free(raw);

    var frame_count: u32 = 0;
    while (true) {
        if (!try read_yuv(raw, yuv_file)) {
            break;
        }

        if (vpx.vpx_codec_encode(&codec, raw, frame_count, 1, 0, vpx.VPX_DL_REALTIME) != 0) {
            std.debug.print("Error encoding frame\n", .{});
            return error.EncodingError;
        }

        var iter: ?*usize = null;
        while (true) {
            const pkt = vpx.vpx_codec_get_cx_data(&codec, @ptrCast([*c]?*const anyopaque, &iter));
            if (pkt == null) break;

            const p = pkt.*;
            if (p.kind == vpx.VPX_CODEC_CX_FRAME_PKT) {
                const frame_size = p.data.frame.sz;
                // If you need keyframe
                // const keyframe = (p.data.frame.flags & vpx.VPX_FRAME_IS_KEY) != 0;
                try ivf_writer.writeIVFFrame(@ptrCast([*]const u8, p.data.frame.buf)[0..frame_size], frame_count);
                frame_count += 1;
            }
        }
    }
}

fn read_yuv(raw: *vpx.struct_vpx_image, yuv_file: std.fs.File) !bool {
    const r = raw.*;
    const y_size = @intCast(usize, r.stride[0]) * @intCast(usize, r.d_h);
    const u_size = @intCast(usize, r.stride[1]) * @intCast(usize, r.d_h) / 2;
    const v_size = @intCast(usize, r.stride[2]) * @intCast(usize, r.d_h) / 2;
    if (y_size != try yuv_file.readAll(@ptrCast([*]u8, r.planes[0])[0..y_size])) {
        return false;
    }
    if (u_size != try yuv_file.readAll(@ptrCast([*]u8, r.planes[1])[0..u_size])) {
        return false;
    }
    if (v_size != try yuv_file.readAll(@ptrCast([*]u8, r.planes[2])[0..v_size])) {
        return false;
    }
    return true;
}
