const std = @import("std");
const c = @cImport({
    @cInclude("vpx/vpx_encoder.h");
    @cInclude("vpx/vp8cx.h");
});

pub const VP8Enc = struct {
    width: u32,
    height: u32,
    framerate_num: u32,
    framerate_den: u32,
    bitrate: u32,
    keyframe_interval: u32,
    codec: c.vpx_codec_ctx_t,
    img: c.struct_vpx_image,

    const Self = @This();

    pub fn init(
        width: u32,
        height: u32,
        framerate_num: u32,
        framerate_den: u32,
        bitrate: u32,
        keyframe_interval: u32,
        yuv_buf: []u8,
    ) !VP8Enc {
        var self = VP8Enc{
            .width = width,
            .height = height,
            .framerate_num = framerate_num,
            .framerate_den = framerate_den,
            .bitrate = bitrate,
            .keyframe_interval = keyframe_interval,
            .codec = undefined,
            .img = undefined,
        };
        var cfg: c.vpx_codec_enc_cfg_t = undefined;
        if (c.vpx_codec_enc_config_default(c.vpx_codec_vp8_cx(), &cfg, 0) != 0) {
            std.debug.print("Error getting default configuration\n", .{});
            return error.DefaultConfigurationError;
        }

        cfg.rc_target_bitrate = bitrate;
        cfg.g_w = width;
        cfg.g_h = height;
        cfg.g_timebase.num = @intCast(framerate_den);
        cfg.g_timebase.den = @intCast(framerate_num);
        cfg.g_error_resilient = 1;
        cfg.kf_min_dist = keyframe_interval;
        cfg.kf_max_dist = keyframe_interval;

        if (c.vpx_codec_enc_init(&self.codec, c.vpx_codec_vp8_cx(), &cfg, 0) != 0) {
            std.debug.print("Error initializing codec\n", .{});
            return error.CodecInitializationError;
        }
        _ = c.vpx_img_wrap(&self.img, c.VPX_IMG_FMT_I420, width, height, 1, @as([*c]u8, @ptrCast(yuv_buf)));
        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = c.vpx_codec_destroy(&self.codec);
    }

    pub fn encode(self: *Self, frame_count: u32) ![]const u8 {
        if (c.vpx_codec_encode(&self.codec, &self.img, frame_count, 1, 0, c.VPX_DL_REALTIME) != 0) {
            std.debug.print("Error encoding frame\n", .{});
            return error.EncodingError;
        }

        var iter: ?*usize = null;
        while (true) {
            const pkt = c.vpx_codec_get_cx_data(&self.codec, @as([*c]?*const anyopaque, @ptrCast(&iter)));
            if (pkt == null) break;

            const p = pkt.*;
            if (p.kind != c.VPX_CODEC_CX_FRAME_PKT) {
                continue;
            }
            const frame_size = p.data.frame.sz;
            // If you need keyframe
            // const keyframe = (p.data.frame.flags & c.VPX_FRAME_IS_KEY) != 0;
            return @as([*]const u8, @ptrCast(p.data.frame.buf))[0..frame_size];
        }
        unreachable;
    }
};
