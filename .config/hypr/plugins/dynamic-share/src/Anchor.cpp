#define _GNU_SOURCE 1
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <sys/mman.h>
#include <unistd.h>

namespace {
volatile std::sig_atomic_t running = 1;
constexpr int WIDTH = 1280, HEIGHT = 720, STRIDE = WIDTH * 4;

struct Anchor {
    wl_display* display = nullptr;
    wl_compositor* compositor = nullptr;
    wl_shm* shm = nullptr;
    xdg_wm_base* wm = nullptr;
    wl_surface* surface = nullptr;
    xdg_surface* xsurface = nullptr;
    xdg_toplevel* toplevel = nullptr;
    wl_buffer* buffer = nullptr;
    void* memory = MAP_FAILED;

    ~Anchor() {
        if (toplevel) xdg_toplevel_destroy(toplevel);
        if (xsurface) xdg_surface_destroy(xsurface);
        if (surface) wl_surface_destroy(surface);
        if (buffer) wl_buffer_destroy(buffer);
        if (wm) xdg_wm_base_destroy(wm);
        if (shm) wl_shm_destroy(shm);
        if (compositor) wl_compositor_destroy(compositor);
        if (display) wl_display_disconnect(display);
        if (memory != MAP_FAILED) munmap(memory, STRIDE * HEIGHT);
    }
};

const xdg_wm_base_listener wmListener{
    .ping = [](void*, xdg_wm_base* wm, uint32_t serial) { xdg_wm_base_pong(wm, serial); },
};
const wl_registry_listener registryListener{
    .global = [](void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t) {
        auto& anchor = *static_cast<Anchor*>(data);
        if (std::strcmp(interface, "wl_compositor") == 0)
            anchor.compositor = static_cast<wl_compositor*>(wl_registry_bind(registry, name, &wl_compositor_interface, 4));
        else if (std::strcmp(interface, "wl_shm") == 0)
            anchor.shm = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
        else if (std::strcmp(interface, "xdg_wm_base") == 0) {
            anchor.wm = static_cast<xdg_wm_base*>(wl_registry_bind(registry, name, &xdg_wm_base_interface, 1));
            xdg_wm_base_add_listener(anchor.wm, &wmListener, nullptr);
        }
    },
    .global_remove = [](void*, wl_registry*, uint32_t) {},
};
const xdg_surface_listener surfaceListener{
    .configure = [](void* data, xdg_surface* surface, uint32_t serial) {
        auto& anchor = *static_cast<Anchor*>(data);
        xdg_surface_ack_configure(surface, serial);
        xdg_surface_set_window_geometry(surface, 0, 0, WIDTH, HEIGHT);
        wl_surface_attach(anchor.surface, anchor.buffer, 0, 0);
        wl_surface_damage_buffer(anchor.surface, 0, 0, WIDTH, HEIGHT);
        wl_surface_commit(anchor.surface);
        // No frame callback, animation timer, source capture, or mirror loop.
    },
};
const xdg_toplevel_listener toplevelListener{
    .configure = [](void*, xdg_toplevel*, int32_t, int32_t, wl_array*) {},
    .close = [](void*, xdg_toplevel*) { running = 0; },
    .configure_bounds = [](void*, xdg_toplevel*, int32_t, int32_t) {},
    .wm_capabilities = [](void*, xdg_toplevel*, wl_array*) {},
};
} // namespace

int main(int argc, char** argv) {
    if (argc != 3 || std::strcmp(argv[1], "--control-fd") != 0) {
        std::fprintf(stderr, "This idle placeholder is launched by the Dynamic Share plugin, not directly.\n");
        return 2;
    }
    char* end = nullptr;
    const long value = std::strtol(argv[2], &end, 10);
    if (!end || *end || value < 3 || value > 1048576 || fcntl(value, F_GETFD) < 0)
        return 2;
    const int control = static_cast<int>(value);
    std::signal(SIGTERM, [](int) { running = 0; });
    std::signal(SIGINT, [](int) { running = 0; });
    Anchor anchor;
    anchor.display = wl_display_connect(nullptr);
    if (!anchor.display) {
        std::fprintf(stderr, "dynamic-share-anchor: cannot connect to Wayland\n");
        return 1;
    }
    auto* registry = wl_display_get_registry(anchor.display);
    wl_registry_add_listener(registry, &registryListener, &anchor);
    const int roundtrip = wl_display_roundtrip(anchor.display);
    wl_registry_destroy(registry);
    if (roundtrip < 0 || !anchor.compositor || !anchor.shm || !anchor.wm)
        return 1;

    const int fd = memfd_create("dynamic-share-placeholder", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, STRIDE * HEIGHT))
        return 1;
    anchor.memory = mmap(nullptr, STRIDE * HEIGHT, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (anchor.memory == MAP_FAILED) {
        close(fd);
        return 1;
    }
    std::memset(anchor.memory, 0, STRIDE * HEIGHT);
    auto* pool = wl_shm_create_pool(anchor.shm, fd, STRIDE * HEIGHT);
    anchor.buffer = wl_shm_pool_create_buffer(pool, 0, WIDTH, HEIGHT, STRIDE, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    anchor.surface = wl_compositor_create_surface(anchor.compositor);
    auto* input = wl_compositor_create_region(anchor.compositor);
    wl_surface_set_input_region(anchor.surface, input); // never consume pointer input
    wl_region_destroy(input);
    anchor.xsurface = xdg_wm_base_get_xdg_surface(anchor.wm, anchor.surface);
    xdg_surface_add_listener(anchor.xsurface, &surfaceListener, &anchor);
    anchor.toplevel = xdg_surface_get_toplevel(anchor.xsurface);
    xdg_toplevel_add_listener(anchor.toplevel, &toplevelListener, nullptr);
    xdg_toplevel_set_app_id(anchor.toplevel, "local.hypr.dynamic-share");
    xdg_toplevel_set_title(anchor.toplevel, "Dynamic Share (switchable window)");
    xdg_toplevel_set_min_size(anchor.toplevel, WIDTH, HEIGHT);
    xdg_toplevel_set_max_size(anchor.toplevel, WIDTH, HEIGHT);
    wl_surface_commit(anchor.surface);

    // Block on Wayland/control FDs. Closing the plugin's control socket also
    // terminates the helper after unload or a compositor crash, with no pid kill.
    while (running) {
        while (wl_display_prepare_read(anchor.display)) {
            if (wl_display_dispatch_pending(anchor.display) < 0)
                return 1;
        }
        const int flush = wl_display_flush(anchor.display);
        if (flush < 0 && errno != EAGAIN) {
            wl_display_cancel_read(anchor.display);
            break;
        }
        pollfd descriptors[] = {
            {wl_display_get_fd(anchor.display), static_cast<short>(POLLIN | ((flush < 0) ? POLLOUT : 0)), 0},
            {control, POLLIN | POLLHUP, 0},
        };
        const int result = poll(descriptors, 2, -1);
        if (result < 0 || descriptors[1].revents || (descriptors[0].revents & (POLLERR | POLLHUP | POLLNVAL))) {
            wl_display_cancel_read(anchor.display);
            if (result < 0 && errno == EINTR)
                continue;
            break;
        }
        if (descriptors[0].revents & POLLIN) {
            if (wl_display_read_events(anchor.display) < 0)
                break;
        } else
            wl_display_cancel_read(anchor.display);
        if (wl_display_dispatch_pending(anchor.display) < 0)
            break;
    }
    close(control);
}
