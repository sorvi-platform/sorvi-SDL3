const builtin = @import("builtin");
const std = @import("std");
const build_options = @import("build_options");
const sorvi = @import("sorvi");
const c = @import("c");

pub const std_options: std.Options = .{
    .logFn = sorvi.defaultLog,
    .queryPageSize = sorvi.queryPageSize,
    .page_size_max = sorvi.page_size_max,
};

pub const os = sorvi.os;
pub const panic = std.debug.FullPanic(sorvi.defaultPanic);

const SORVI_bootstrap: c.VideoBootStrap = .{
    .name = "sorvi",
    .desc = "Video driver for the sorvi platform",
    .create = &SORVI_CreateDevice,
    .ShowMessageBox = null,
    .is_preferred = true,
};

const SORVI_audio_bootstrap: c.AudioBootStrap = .{
    .name = "sorvi",
    .desc = "Audio driver for the sorvi platform",
    .init = &SORVI_AudioInit,
    .demand_only = false,
    .is_preferred = true,
};

comptime {
    @export(&SORVI_bootstrap, .{
        .name = "PRIVATE_bootstrap",
        .visibility = .hidden,
    });
    @export(&SORVI_audio_bootstrap, .{
        .name = "PRIVATEAUDIO_bootstrap",
        .visibility = .hidden,
    });
}

const GraphicsApi = enum {
    none,
    raster,
    gles,
    vulkan,
};

const global = struct {
    var configuration: sorvi.video_v1.configuration_t = .{
        .mode = .default,
        .w = 800,
        .h = 480,
        .flags = .{ .border = true },
        .presentation = .dont_care,
    };
    var api: union (GraphicsApi) {
        none,
        raster,
        gles: sorvi.gles_v1.init_result_t,
        vulkan: sorvi.vulkan_v1.init_result_t,
    } = .none;
    var render_w: u16 = 800;
    var render_h: u16 = 480;
    var window: ?*c.SDL_Window = null;
    var audio_device: ?*c.SDL_AudioDevice = null;
    var audio_buffer: []u8 = &.{};
    var relative_mode: bool = false;
};

fn SORVI_CreateDevice() callconv(.c) ?*c.SDL_VideoDevice {
    const device = sorvi.default_allocator.create(c.SDL_VideoDevice) catch return null;
    device.* = .{
        .name = "sorvi",
        .VideoInit = SORVI_VideoInit,
        .VideoQuit = SORVI_VideoQuit,
        .SetDisplayMode = SORVI_SetDisplayMode,
        .PumpEvents = SORVI_PumpEvents,
        .CreateSDLWindow = SORVI_CreateWindow,
        .SetWindowSize = SORVI_SetWindowSize,
        .GetWindowSizeInPixels = SORVI_GetWindowSizeInPixels,
        .SetWindowResizable = SORVI_SetWindowResizable,
        .SetWindowFullscreen = SORVI_SetWindowFullscreen,
        .DestroyWindow = SORVI_DestroyWindow,
        .CreateWindowFramebuffer = SORVI_CreateWindowFramebuffer,
        .UpdateWindowFramebuffer = SORVI_UpdateWindowFramebuffer,
        .DestroyWindowFramebuffer = SORVI_DestroyWindowFramebuffer,
        .GL_LoadLibrary = SORVI_GL_LoadLibrary,
        .GL_UnloadLibrary = SORVI_GL_UnloadLibrary,
        .GL_GetProcAddress = SORVI_GL_GetProcAddress,
        .GL_CreateContext = SORVI_GL_CreateContext,
        .GL_MakeCurrent = SORVI_GL_MakeCurrent,
        .GL_SwapWindow = SORVI_GL_SwapWindow,
        .GL_DestroyContext = SORVI_GL_DestroyContext,
        .Vulkan_LoadLibrary = SORVI_VK_LoadLibrary,
        .Vulkan_UnloadLibrary = SORVI_VK_UnloadLibrary,
        .Vulkan_GetInstanceExtensions = SORVI_VK_GetInstanceExtensions,
        .Vulkan_CreateSurface = SORVI_VK_CreateSurface,
        .Vulkan_DestroySurface = SORVI_VK_DestroySurface,
        .free = SORVI_DeleteDevice,
        .system_theme = c.SDL_SYSTEM_THEME_UNKNOWN,
    };
    return device;
}

fn SORVI_SetRelativeMouseMode(enabled: bool) callconv(.c) bool {
    if (enabled) {
        sorvi.kbm_v1.lock_pointer();
    } else {
        sorvi.kbm_v1.unlock_pointer();
    }
    global.relative_mode = enabled;
    return true;
}

fn SORVI_VideoInit(_: ?*c.SDL_VideoDevice) callconv(.c) bool {
    for (sorvi.video_v1.query_display_modes()) |mode| {
        const ret = c.SDL_AddBasicVideoDisplay(&.{
            .displayID = @intCast(@intFromEnum(mode.id)),
            .w = mode.w,
            .h = mode.h,
            .pixel_density = mode.scale,
            .refresh_rate = mode.refresh_rate,
            .refresh_rate_numerator = @intCast(mode.refresh_rate_numerator),
            .refresh_rate_denominator = @intCast(mode.refresh_rate_denominator),
            .format = c.SDL_PIXELFORMAT_BGRA32,
        });
        if (ret == 0) return false;
    }
    if (c.SDL_GetMouse()) |mouse| {
        mouse[0].SetRelativeMouseMode = &SORVI_SetRelativeMouseMode;
    }
    return true;
}

fn SORVI_VideoQuit(device: ?*c.SDL_VideoDevice) callconv(.c) void {
    if (global.window) |window| SORVI_DestroyWindow(device, window);
}

fn SORVI_SetDisplayMode(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_VideoDisplay, mode: ?*c.SDL_DisplayMode) callconv(.c) bool {
    var cpy = global.configuration;
    cpy.mode = @enumFromInt(mode.?.displayID);
    sorvi.video_v1.configure(cpy) catch return false;
    return true;
}

fn SORVI_PumpEvents(_: ?*c.SDL_VideoDevice) callconv(.c) void {}

fn SORVI_CreateWindow(_: ?*c.SDL_VideoDevice, window: ?*c.SDL_Window, _: c.SDL_PropertiesID) callconv(.c) bool {
    global.window = window;
    return true;
}

fn initialConfiguration() void {
    var cpy = global.configuration;
    cpy.w = @intCast(global.window.?.w);
    cpy.h = @intCast(global.window.?.h);
    sorvi.video_v1.configure(cpy) catch {};
}

fn SORVI_SetWindowSize(_: ?*c.SDL_VideoDevice, window: ?*c.SDL_Window) callconv(.c) void {
    var cpy = global.configuration;
    cpy.w = @intCast(window.?.pending.w);
    cpy.h = @intCast(window.?.pending.h);
    sorvi.video_v1.configure(cpy) catch return;
}

fn SORVI_GetWindowSizeInPixels(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, w: ?*c_int, h: ?*c_int) callconv(.c) void {
    w.?.* = global.render_w;
    h.?.* = global.render_h;
}

fn SORVI_DestroyWindow(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window) callconv(.c) void {
    switch (global.api) {
        .vulkan => sorvi.vulkan_v1.deinit(),
        .gles => sorvi.gles_v1.deinit(),
        .raster => sorvi.raster_v1.deinit(),
        .none => {},
    }
    global.api = .none;
    global.window = null;
}

fn SORVI_SetWindowResizable(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, resizable: bool) callconv(.c) void {
    var cpy = global.configuration;
    cpy.presentation = if (resizable) .dont_care else .fixed;
    sorvi.video_v1.configure(cpy) catch {};
}

fn SORVI_SetWindowFullscreen(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, _: ?*c.SDL_VideoDisplay, fullscreen: c.SDL_FullscreenOp) callconv(.c) c.SDL_FullscreenResult {
    var cpy = global.configuration;
    cpy.presentation = if (fullscreen != 0) .fullscreen else .dont_care;
    sorvi.video_v1.configure(cpy) catch return c.SDL_FULLSCREEN_FAILED;
    return c.SDL_FULLSCREEN_SUCCEEDED;
}

fn SORVI_CreateWindowFramebuffer(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, format: ?*c.SDL_PixelFormat, pixels: ?*?*anyopaque, pitch: ?*c_int) callconv(.c) bool {
    format.?.* = c.SDL_PIXELFORMAT_BGRA32;
    pixels.?.* = null;
    pitch.?.* = 0;
    if (!sorvi.raster_v1.available) return false;
    if (global.api == .raster) return true;
    if (global.api != .none) return false;
    sorvi.raster_v1.init(.{
        .format = .argb8888,
        .scaling = null,
        .direct = false,
    }) catch return false;
    global.api = .raster;
    initialConfiguration();
    return true;
}

fn SORVI_UpdateWindowFramebuffer(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, sdl_rects: ?[*]const c.SDL_Rect, ilen: c_int) callconv(.c) bool {
    const len: usize = @intCast(ilen);
    var rects_left: usize = @intCast(len);
    while (rects_left > 0) {
        var rects: [16]sorvi.raster_v1.rect_t = undefined;
        const chunk: usize = @min(rects_left, rects.len);
        for (rects[0..chunk], sdl_rects.?[len - rects_left..][0..chunk]) |*a, *b| {
            a.* = .{
                .x = @intCast(b.x),
                .y = @intCast(b.y),
                .w = @intCast(b.w),
                .h = @intCast(b.h),
            };
        }
        sorvi.raster_v1.damage(rects[0..chunk]);
        rects_left -= chunk;
    }
    return true;
}

fn SORVI_DestroyWindowFramebuffer(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window) callconv(.c) void {
    if (global.api != .raster) return;
    sorvi.raster_v1.deinit();
    global.api = .none;
}

fn SORVI_GL_LoadLibrary(_: ?*c.SDL_VideoDevice, _: ?[*:0]const u8) callconv(.c) bool {
    return sorvi.gles_v1.available;
}

fn SORVI_GL_UnloadLibrary(_: ?*c.SDL_VideoDevice) callconv(.c) void {}

fn SORVI_GL_GetProcAddress(_: ?*c.SDL_VideoDevice, proc: ?[*:0]const u8) callconv(.c) ?*const fn() callconv(.c) void {
    const fun: *const fn ([*:0]const u8) callconv(sorvi.abi.ccv) usize = @ptrFromInt(global.api.gles.proc_addr_fn);
    return @ptrFromInt(fun(proc.?));
}

fn SORVI_GL_CreateContext(device: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window) callconv(.c) ?*c.SDL_GLContextState {
    if (!sorvi.gles_v1.available) return null;
    if (global.api == .gles) return @ptrFromInt(0xDEADBEEF);
    if (global.api != .none) return null;
    global.api = .{
        .gles = sorvi.gles_v1.init(.{
            .required_extensions = .wrap(&.{}),
            .context_major_version = @intCast(device.?.gl_config.major_version),
            .context_minor_version = @intCast(device.?.gl_config.minor_version),
            .red_size = @intCast(device.?.gl_config.red_size),
            .green_size = @intCast(device.?.gl_config.green_size),
            .blue_size = @intCast(device.?.gl_config.blue_size),
            .alpha_size = @intCast(device.?.gl_config.alpha_size),
            .depth_size = @intCast(device.?.gl_config.depth_size),
            .stencil_size = @intCast(device.?.gl_config.stencil_size),
            .multi_sample_buffers = @intCast(device.?.gl_config.multisamplebuffers),
            .multi_sample_samples = @intCast(device.?.gl_config.multisamplesamples),
            .srgb_capable = switch (device.?.gl_config.framebuffer_srgb_capable) {
                -1 => .dont_care,
                0 => .no,
                else => .yes,
            },
            .context_no_error = device.?.gl_config.no_error != 0,
            .float_buffers = device.?.gl_config.floatbuffers != 0,
        }) catch return null,
    };
    initialConfiguration();
    return @ptrFromInt(0xDEADBEEF);
}

fn SORVI_GL_MakeCurrent(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, _: c.SDL_GLContext) callconv(.c) bool {
    return true;
}

fn SORVI_GL_SwapWindow(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window) callconv(.c) bool {
    sorvi.gles_v1.swap();
    return true;
}

fn SORVI_GL_DestroyContext(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_GLContextState) callconv(.c) bool {
    if (global.api != .gles) return false;
    sorvi.gles_v1.deinit();
    global.api = .none;
    return true;
}

const VkVersion = packed struct(u32) {
    patch: u12,
    minor: u10,
    major: u7,
    variant: u3,
};

const VkApplicationInfo = extern struct {
    type: u32,
    next: ?*anyopaque,
    name: [*:0]const u8,
    version: u32,
    engine_name: [*:0]const u8,
    engine_version: u32,
    api_version: u32,
};

const VkInstanceCreateInfo = extern struct {
    type: u32,
    next: ?*anyopaque,
    flags: u32,
    app: *VkApplicationInfo,
    enabled_layer_count: u32,
    enabled_layer_names: [*]const [*:0]const u8,
    enabled_extension_count: u32,
    enabled_extension_names: [*]const [*:0]const u8,
};

fn vkCreateInstance(info: *const VkInstanceCreateInfo, _: *const anyopaque, instance: *c.VkInstance) callconv(.c) i32 {
    global.api = .{
        .vulkan = sorvi.vulkan_v1.init(.{
            .required_extensions = .wrap(info.enabled_extension_names[0..info.enabled_extension_count]),
            .optional_extensions = .wrap(&.{}),
            .required_layers = .wrap(info.enabled_layer_names[0..info.enabled_layer_count]),
            .optional_layers = .wrap(&.{}),
            .engine_name = info.app.engine_name,
            .engine_version = info.app.engine_version,
            .api_version = info.app.api_version,
        }) catch return -3, // VK_ERROR_INITIALIZATION_FAILED
    };
    instance.* = @ptrCast(global.api.vulkan.instance);
    initialConfiguration();
    return 0; // VK_SUCCESS
}

fn vkDestroyInstance(_: c.VkInstance, _: *const anyopaque) callconv(.c) void {
    if (global.api != .vulkan) return;
    sorvi.vulkan_v1.deinit();
    global.api = .none;
}

fn vkEnumerateInstanceExtensionProperties(_: [*:0]const u8, count: *u32, _: *anyopaque) callconv(.c) i32 {
    count.* = 0;
    return 0;
}

fn vkEnumerateInstanceLayerProperties(count: *u32, _: *anyopaque) callconv(.c) i32 {
    count.* = 0;
    return 0;
}

fn fake_vk_instance_proc_addr_fn(instance: c.VkInstance, raw_name: [*:0]const u8) callconv(.c) usize {
    const name = std.mem.span(raw_name);
    if (std.mem.eql(u8, name, "vkGetInstanceProcAddr")) {
        if (global.api == .vulkan) {
            return global.api.vulkan.instance_proc_addr_fn;
        } else {
            @panic("sorvi_SDL3: recursion in vkGetInstanceProcAddr");
        }
    } else if (std.mem.eql(u8, name, "vkCreateInstance")) {
        return @intFromPtr(&vkCreateInstance);
    } else if (std.mem.eql(u8, name, "vkDestroyInstance")) {
        return @intFromPtr(&vkDestroyInstance);
    } else if (std.mem.eql(u8, name, "vkEnumerateInstanceExtensionProperties")) {
        return @intFromPtr(&vkEnumerateInstanceExtensionProperties);
    } else if (std.mem.eql(u8, name, "vkEnumerateInstanceLayerProperties")) {
        return @intFromPtr(&vkEnumerateInstanceLayerProperties);
    } else {
        if (global.api == .vulkan) {
            const real: *const fn (c.VkInstance, [*:0]const u8) callconv(.c) usize = @ptrFromInt(global.api.vulkan.instance_proc_addr_fn);
            return real(instance, raw_name);
        } else {
            return 0;
        }
    }
}

fn SORVI_VK_LoadLibrary(device: ?*c.SDL_VideoDevice, _: ?[*:0]const u8) callconv(.c) bool {
    if (!sorvi.vulkan_v1.available) return false;
    device.?.vulkan_config.vkGetInstanceProcAddr = @ptrCast(&fake_vk_instance_proc_addr_fn);
    return true;
}

fn SORVI_VK_UnloadLibrary(device: ?*c.SDL_VideoDevice) callconv(.c) void {
    device.?.vulkan_config.vkGetInstanceProcAddr = null;
}

fn SORVI_VK_GetInstanceExtensions(_: ?*c.SDL_VideoDevice, count: ?*u32) callconv(.c) ?[*]const [*:0]const u8 {
    count.?.* = 0;
    return null;
}

fn SORVI_VK_CreateSurface(_: ?*c.SDL_VideoDevice, _: ?*c.SDL_Window, _: c.VkInstance, _: ?*const c.VkAllocationCallbacks, surface: ?*c.VkSurfaceKHR) callconv(.c) bool {
    if (!sorvi.vulkan_v1.available) return false;
    if (global.api != .vulkan) return false;
    surface.?.* = switch (builtin.target.cpu.arch) {
        .wasm32, .wasm64 => @intFromPtr(global.api.vulkan.surface),
        else => @ptrCast(global.api.vulkan.surface),
    };
    return true;
}

fn SORVI_VK_DestroySurface(_: ?*c.SDL_VideoDevice, _: c.VkInstance, _: c.VkSurfaceKHR, _: ?*const c.VkAllocationCallbacks) callconv(.c) void {}

fn SORVI_DeleteDevice(device: ?*c.SDL_VideoDevice) callconv(.c) void {
    sorvi.default_allocator.destroy(device.?);
}

fn SORVI_AL_OpenDevice(device: ?*c.SDL_AudioDevice) callconv(.c) bool {
    var changed: bool = false;
    _ = sorvi.audio_v1.init(.{
        .format = switch (device.?.spec.format) {
            c.SDL_AUDIO_S16LE => .s16le,
            else => D: {
                changed = true;
                device.?.spec.format = c.SDL_AUDIO_S16LE;
                break :D .s16le;
            },
        },
        .layout = switch (device.?.spec.channels) {
            1 => .mono,
            2 => .stereo,
            6 => .surround_5_1,
            8 => .surround_7_1,
            else => D: {
                changed = true;
                device.?.spec.channels = 2;
                break :D .stereo;
            },
        },
        .sample_rate = @intCast(device.?.spec.freq),
        .buffer_size = @intCast(device.?.sample_frames),
        .direct = false,
    }) catch return false;
    global.audio_device = device;
    global.audio_buffer = &.{};
    if (changed) c.SDL_UpdatedAudioDeviceFormat(device);
    device.?.simple_copy = !changed;
    sorvi.audio_v1.cmd(.@"resume") catch return false;
    return true;
}

fn SORVI_AL_GetDeviceBuf(_: ?*c.SDL_AudioDevice, buffer_size: ?*c_int) callconv(.c) ?[*]u8 {
    buffer_size.?.* = @intCast(global.audio_buffer.len);
    if (global.audio_buffer.len == 0) return null;
    return global.audio_buffer.ptr;
}

fn SORVI_AL_CloseDevice(_: ?*c.SDL_AudioDevice) callconv(.c) void {
    sorvi.audio_v1.deinit();
    global.audio_device = null;
    global.audio_buffer = &.{};
}

fn SORVI_AudioInit(driver: ?*c.SDL_AudioDriverImpl) callconv(.c) bool {
    driver.?.* = .{
        .OpenDevice = SORVI_AL_OpenDevice,
        .GetDeviceBuf = SORVI_AL_GetDeviceBuf,
        .CloseDevice = SORVI_AL_CloseDevice,
        .ProvidesOwnCallbackThread = true,
        .OnlyHasDefaultPlaybackDevice = true,
    };
    return true;
}

export fn SDL_EnterAppMainCallbacks(
    argc: c_int,
    argv: [*]const [*:0]const u8,
    app_init: c.SDL_AppInit_func,
    app_iter: c.SDL_AppIterate_func,
    app_event: c.SDL_AppEvent_func,
    app_quit: c.SDL_AppQuit_func,
) c_int {
    const res = c.SDL_InitMainCallbacks(argc, @constCast(@ptrCast(argv)), app_init, app_iter, app_event, app_quit);
    if (res != c.SDL_APP_CONTINUE) {
        c.SDL_QuitMainCallbacks(res);
    }
    return switch (res) {
        c.SDL_APP_FAILURE => 1,
        else => 0,
    };
}

export fn SDL_RunApp(
    argc: c_int,
    argv: [*]const [*:0]const u8,
    main: c.SDL_main_func,
    _: *anyopaque,
) c_int {
    return c.SDL_CallMainFunction(argc, @constCast(@ptrCast(argv)), main);
}

comptime {
    sorvi.init(@This(), .{
        .id = undefined,
        .name = undefined,
        .version = undefined,
        .core_extensions = &.{.core_v1, .kbm_v1, .audio_v1, .video_v1},
        .frontend_extensions = &.{.core_v1, .mem_v1, .video_v1},
    });
}

pub fn sorvi_core_v1_get_str_core(key: sorvi.core_v1.str_key_core_t) callconv(sorvi.abi.ccv) ?[*:0]const u8 {
    return switch (key) {
        .id => @extern([*:0]const u8, .{ .name = "SDL_SORVI_app_id", .visibility = .hidden }),
        .name => @extern([*:0]const u8, .{ .name = "SDL_SORVI_app_name", .visibility = .hidden }),
        .version => @extern([*:0]const u8, .{ .name = "SDL_SORVI_app_version", .visibility = .hidden }),
        _ => null,
    };
}

pub fn init(_: *@This()) !void {
    const argv: [*]const ?[*:0]const u8 = &.{"SDL3_app", null};
    switch (c.SDL_main(1, @constCast(@ptrCast(argv)))) {
        0 => {},
        else => |rc| std.debug.panic("SDL_main returned non-zero exit code: {}", .{rc}),
    }
}

pub fn deinit(_: *@This()) void {
    c.SDL_SendAppEvent(c.SDL_EVENT_TERMINATING);
}

fn sorviModifiersToSdl(sorvi_mods: sorvi.kbm_v1.modifiers_t) c.SDL_Keymod {
    var mods: c.SDL_Keymod = 0;
    if (sorvi_mods.lshift) mods |= c.SDL_KMOD_LSHIFT;
    if (sorvi_mods.rshift) mods |= c.SDL_KMOD_RSHIFT;
    if (sorvi_mods.lctrl) mods |= c.SDL_KMOD_LCTRL;
    if (sorvi_mods.rctrl) mods |= c.SDL_KMOD_RCTRL;
    if (sorvi_mods.lalt) mods |= c.SDL_KMOD_LALT;
    if (sorvi_mods.ralt) mods |= c.SDL_KMOD_RALT;
    if (sorvi_mods.lgui) mods |= c.SDL_KMOD_LGUI;
    if (sorvi_mods.rgui) mods |= c.SDL_KMOD_RGUI;
    if (sorvi_mods.num_lock) mods |= c.SDL_KMOD_NUM;
    if (sorvi_mods.caps_lock) mods |= c.SDL_KMOD_CAPS;
    if (sorvi_mods.scroll_lock) mods |= c.SDL_KMOD_SCROLL;
    return mods;
}

pub fn kbmKeyPress(
    _: *@This(),
    ts: u64,
    _: sorvi.kbm_v1.absolute_t,
    sorvi_mods: sorvi.kbm_v1.modifiers_t,
    sorvi_scancode: sorvi.kbm_v1.scancode_t
) !void {
    const mods = sorviModifiersToSdl(sorvi_mods);
    c.SDL_SetModState(mods);
    const scancode: c.SDL_Scancode = @intFromEnum(sorvi_scancode);
    const keycode = c.SDL_GetKeyFromScancode(scancode, mods, true);
    if (keycode != c.SDLK_UNKNOWN) {
        _ = c.SDL_SendKeyboardKeyAndKeycode(ts, c.SDL_DEFAULT_KEYBOARD_ID, 0, scancode, keycode, true);
    } else {
        _ = c.SDL_SendKeyboardKey(ts, c.SDL_DEFAULT_KEYBOARD_ID, 0, scancode, true);
    }
}

pub fn kbmKeyRelease(
    _: *@This(),
    ts: u64,
    _: sorvi.kbm_v1.absolute_t,
    sorvi_mods: sorvi.kbm_v1.modifiers_t,
    sorvi_scancode: sorvi.kbm_v1.scancode_t
) !void {
    const mods = sorviModifiersToSdl(sorvi_mods);
    c.SDL_SetModState(mods);
    const scancode: c.SDL_Scancode = @intFromEnum(sorvi_scancode);
    const keycode = c.SDL_GetKeyFromScancode(scancode, mods, true);
    if (keycode != c.SDLK_UNKNOWN) {
        _ = c.SDL_SendKeyboardKeyAndKeycode(ts, c.SDL_DEFAULT_KEYBOARD_ID, 0, scancode, keycode, false);
    } else {
        _ = c.SDL_SendKeyboardKey(ts, c.SDL_DEFAULT_KEYBOARD_ID, 0, scancode, false);
    }
}

fn sorviButtonToSdl(button: sorvi.kbm_v1.button_t) ?u8 {
    return switch (button) {
        .left => c.SDL_BUTTON_LEFT,
        .right => c.SDL_BUTTON_RIGHT,
        .middle => c.SDL_BUTTON_MIDDLE,
        .nav_previous => c.SDL_BUTTON_X1,
        .nav_next => c.SDL_BUTTON_X2,
        else => null,
    };
}

pub fn kbmButtonPress(
    _: *@This(),
    ts: u64,
    _: sorvi.kbm_v1.absolute_t,
    sorvi_mods: sorvi.kbm_v1.modifiers_t,
    sorvi_button: sorvi.kbm_v1.button_t
) !void {
    const mods = sorviModifiersToSdl(sorvi_mods);
    c.SDL_SetModState(mods);
    const button = sorviButtonToSdl(sorvi_button) orelse return;
    c.SDL_SendMouseButton(ts, global.window, c.SDL_DEFAULT_MOUSE_ID, button, true);
}

pub fn kbmButtonRelease(
    _: *@This(),
    ts: u64,
    _: sorvi.kbm_v1.absolute_t,
    sorvi_mods: sorvi.kbm_v1.modifiers_t,
    sorvi_button: sorvi.kbm_v1.button_t
) !void {
    const mods = sorviModifiersToSdl(sorvi_mods);
    c.SDL_SetModState(mods);
    const button = sorviButtonToSdl(sorvi_button) orelse return;
    c.SDL_SendMouseButton(ts, global.window, c.SDL_DEFAULT_MOUSE_ID, button, false);
}

pub fn kbmMouseMotion(
    _: *@This(),
    ts: u64,
    abs: sorvi.kbm_v1.absolute_t,
    sorvi_mods: sorvi.kbm_v1.modifiers_t,
    rel: sorvi.kbm_v1.relative_t,
) !void {
    const mods = sorviModifiersToSdl(sorvi_mods);
    c.SDL_SetModState(mods);
    if (global.relative_mode) {
        c.SDL_SendMouseMotion(ts, global.window, c.SDL_DEFAULT_MOUSE_ID, true, rel.x, rel.y);
    } else {
        c.SDL_SendMouseMotion(ts, global.window, c.SDL_DEFAULT_MOUSE_ID, false, @floatFromInt(abs.x), @floatFromInt(abs.y));
    }
}

pub fn kbmMouseScroll(
    _: *@This(),
    ts: u64,
    _: sorvi.kbm_v1.absolute_t,
    sorvi_mods: sorvi.kbm_v1.modifiers_t,
    delta: sorvi.kbm_v1.relative_t,
) !void {
    const mods = sorviModifiersToSdl(sorvi_mods);
    c.SDL_SetModState(mods);
    c.SDL_SendMouseWheel(ts, global.window, c.SDL_DEFAULT_MOUSE_ID, delta.x, delta.y, c.SDL_MOUSEWHEEL_NORMAL);
}

// SDL2 does not have equivalent of SDL3 app callbacks
// To port a SDL2 application, this function needs to be implemented!
extern fn SDL2_iterate() callconv(.c) c_int;

pub fn videoTick(_: *@This(), _: sorvi.video_v1.frame_t) !u64 {
    if (!build_options.sdl2_compat) {
        std.debug.assert(c.SDL_HasMainCallbacks()); // your SDL3 app is setup wrong
        switch (c.SDL_IterateMainCallbacks(true)) {
            c.SDL_APP_CONTINUE => {},
            else => |rc| {
                c.SDL_QuitMainCallbacks(rc);
                sorvi.core_v1.exit();
            },
        }
    } else {
        switch (SDL2_iterate()) {
            c.SDL_APP_CONTINUE => {},
            else => |_| sorvi.core_v1.exit(),
        }
    }
    // TODO: handle callback rate
    return 0;
}

pub fn videoConfiguration(_: *@This(), new: sorvi.video_v1.configuration_t, rw: u16, rh: u16) !void {
    const old = global.configuration;
    global.configuration = new;
    global.render_w = rw;
    global.render_h = rh;
    const window = global.window orelse return;
    if (new.w != old.w or new.h != old.h) {
        _ = c.SDL_SendWindowEvent(window, c.SDL_EVENT_WINDOW_RESIZED, new.w, new.h);
    }
    if (new.presentation != old.presentation) {
        switch (new.presentation) {
            .fullscreen => {
                _ = c.SDL_SendWindowEvent(window, c.SDL_EVENT_WINDOW_ENTER_FULLSCREEN, 0, 0);
                _ = c.SDL_UpdateFullscreenMode(window, 1, false);
            },
            .fixed,
            .dont_care,
            _ => {
                if (old.presentation == .fullscreen) {
                    _ = c.SDL_SendWindowEvent(window, c.SDL_EVENT_WINDOW_LEAVE_FULLSCREEN, 0, 0);
                    _ = c.SDL_UpdateFullscreenMode(window, 0, false);
                }
            },
        }
    }
}

pub fn audioTick(_: *@This(), buffer: []u8) !void {
    global.audio_buffer = buffer;
    _ = c.SDL_PlaybackAudioThreadIterate(global.audio_device);
    global.audio_buffer = &.{};
}
