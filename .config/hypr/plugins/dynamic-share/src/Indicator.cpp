#include "Indicator.hpp"
#include "HookLookup.hpp"
#include "IndicatorGeometry.hpp"
#include <GLES3/gl32.h>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Context.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <map>
#include <stdexcept>

namespace dynamic_share {
namespace {
CHyprColor color(std::uint32_t rgba) {
    return {((rgba >> 24) & 255) / 255.F, ((rgba >> 16) & 255) / 255.F,
            ((rgba >> 8) & 255) / 255.F, (rgba & 255) / 255.F};
}
}

struct Indicator::Impl {
    using End = void (*)(Render::GL::CHyprOpenGLImpl*, Render::CRenderContext&);
    using Scanout = bool (*)(const Monitor::CMonitor*);
    struct Last {
        PHLMONITORREF monitor;
        std::optional<CBox> box;
    };
    struct Outline {
        CBox box;
        IndicatorStyle style;
    };
    void* owner;
    SourcePolicy& policy;
    std::function<CaptureTarget()> resolve;
    IndicatorSettings settings;
    CFunctionHook* hook = nullptr;
    CFunctionHook* scanoutHook = nullptr;
    CHyprSignalListener renderStage;
    wl_event_source* expiry = nullptr;
    std::map<const Monitor::CMonitor*, Last> last;
    bool active = false;
    SourceId paintedSource = 0;
    static Impl* running;

    Impl(void* owner_, SourcePolicy& p, std::function<CaptureTarget()> r) : owner(owner_), policy(p), resolve(std::move(r)) {
        if (running)
            throw std::runtime_error("another shared-target indicator is already active");
        running = this;
        try {
            auto* address = resolveHook(END_HOOK, [this](const std::string& query) { return HyprlandAPI::findFunctionsByName(owner, query); });
            hook = HyprlandAPI::createFunctionHook(owner, address, reinterpret_cast<void*>(&end));
            if (!hook || !hook->hook())
                throw std::runtime_error("could not install local-only indicator post-render hook");
            address = resolveHook(SCANOUT_HOOK, [this](const std::string& query) { return HyprlandAPI::findFunctionsByName(owner, query); });
            scanoutHook = HyprlandAPI::createFunctionHook(owner, address, reinterpret_cast<void*>(&scanout));
            if (!scanoutHook || !scanoutHook->hook())
                throw std::runtime_error("could not install indicator scanout guard");
            expiry = wl_event_loop_add_timer(g_pCompositor->m_wlEventLoop, [](void* data) {
                auto& self = *static_cast<Impl*>(data);
                self.active = false;
                self.damage();
                return 0;
            }, this);
            if (!expiry)
                throw std::runtime_error("could not create indicator cleanup deadline");
            renderStage = Event::bus()->m_events.render.stage.listen([this](const Event::SRenderStageEvent& event) {
                if (event.stage != RENDER_BEGIN || !event.context)
                    return;
                auto& ctx = event.context->get();
                if (ctx.m_mode != Render::RENDER_MODE_NORMAL || ctx.readOnlyEffects())
                    return;
                std::erase_if(last, [](const auto& item) { return item.second.monitor.expired(); });
                auto& previous = last[event.monitor.get()];
                previous.monitor = event.monitor;
                // Repaint clean scene pixels beneath the old AND new outline
                // before the mirror copy. This avoids glow alpha accumulation.
                if (previous.box) {
                    ctx.m_data.damage.add(*previous.box);
                    ctx.m_data.finalDamage.add(*previous.box);
                }
                const auto next = outline(event.monitor);
                if (next) {
                    const auto expanded = expand(*next, event.monitor->m_scale);
                    ctx.m_data.damage.add(expanded);
                    ctx.m_data.finalDamage.add(expanded);
                }
            });
        } catch (...) {
            cleanup();
            throw;
        }
    }
    ~Impl() { cleanup(); }
    CBox expand(const Outline& outline, double scale) const {
        const double margin = (outline.style.glowSize + outline.style.borderWidth + 4) * scale;
        return {outline.box.pos() - Vector2D{margin, margin}, outline.box.size() + Vector2D{2 * margin, 2 * margin}};
    }
    std::optional<Outline> outline(PHLMONITOR monitor) {
        if (!monitor || !monitor->m_enabled)
            return {};
        const auto target = resolve();
        if (!active || !settings.enabled || policy.locked() || !policy.source() || policy.source()->privateContent)
            return {};
        const auto style = settings.style(policy.source()->kind);
        if (!style.borderWidth && (!style.glowSize || style.glowOpacity == 0))
            return {}; // do not inhibit scanout for an invisible indicator
        if (target.window) {
            if (!settings.windows || !g_pHyprRenderer->shouldRenderWindow(target.window, monitor))
                return {};
            const auto presentation = target.window->presentation().renderPresentation();
            auto result = target.window->geometricBox(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            result.translate(presentation.workspaceOffset + presentation.floatingOffset - monitor->m_position).scale(monitor->m_scale);
            return Outline{result, style};
        }
        if (target.workspace) {
            if (!settings.workspaces || target.workspace->m_monitor.lock() != monitor ||
                (monitor->m_activeWorkspace != target.workspace && monitor->m_activeSpecialWorkspace != target.workspace))
                return {};
        } else if (!target.monitor || !settings.monitors || target.monitor != monitor)
            return {};
        // Workspace capture is windows-only: outline its usable work area, not
        // reserved shell panels/bars. Whole-monitor capture keeps the full edge.
        const auto& reserved = monitor->m_reservedArea;
        const auto area = indicatorOutputBox(monitor->m_transformedSize.x, monitor->m_transformedSize.y, monitor->m_scale,
            style.borderWidth, target.workspace ? IndicatorInsets{reserved.left(), reserved.top(), reserved.right(), reserved.bottom()} : IndicatorInsets{});
        if (!area)
            return {};
        return Outline{CBox{area->x, area->y, area->width, area->height}, style};
    }
    void damage() {
        for (const auto& [_, previous] : last)
            if (const auto monitor = previous.monitor.lock())
                g_pHyprRenderer->damageMonitor(monitor);
        const auto target = resolve();
        const auto monitor = target.monitor ? target.monitor :
            (target.window ? target.window->m_monitor.lock() : (target.workspace ? target.workspace->m_monitor.lock() : nullptr));
        if (monitor)
            g_pHyprRenderer->damageMonitor(monitor);
    }
    static bool scanout(const Monitor::CMonitor* monitor) {
        auto& self = *running;
        const auto previous = self.last.find(monitor);
        // A local overlay cannot be painted over a directly scanned-out client
        // buffer. Block only outputs with an outline or pending outline cleanup.
        if (self.outline(monitor->m_self.lock()) || (previous != self.last.end() && previous->second.box))
            return false;
        return reinterpret_cast<Scanout>(self.scanoutHook->m_original)(monitor);
    }
    static void end(Render::GL::CHyprOpenGLImpl* gl, Render::CRenderContext& ctx) {
        auto& self = *running;
        const auto monitor = ctx.m_data.pMonitor.lock();
        const auto output = ctx.m_data.outFB;
        const bool eligible = ctx.m_mode == Render::RENDER_MODE_NORMAL && !ctx.readOnlyEffects() &&
            !ctx.m_gl.fakeFrame && ctx.m_gl.offloadedFramebuffer;
        reinterpret_cast<End>(self.hook->m_original)(gl, ctx);
        if (!eligible || !monitor || !output)
            return;
        auto& previous = self.last[monitor.get()];
        previous.monitor = monitor;
        const auto outline = self.outline(monitor);
        previous.box = outline ? std::optional<CBox>{self.expand(*outline, monitor->m_scale)} : std::nullopt;
        if (!outline)
            return;
        const auto dirty = *previous.box;
        GLint drawFB = 0, readFB = 0, viewport[4]{};
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFB);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFB);
        glGetIntegerv(GL_VIEWPORT, viewport);
        const Render::CScopeGuard restoreGL([&] {
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFB);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, readFB);
            glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
        });
        {
            const auto saved = ctx.saveDrawState();
            g_pHyprRenderer->bindFB(ctx, output);
            ctx.m_data.fbSize = monitor->m_transformedSize;
            ctx.m_data.renderModif = {};
            ctx.m_data.clipBox = {};
            ctx.m_data.damage = CRegion(0, 0, monitor->m_transformedSize.x, monitor->m_transformedSize.y);
            ctx.m_data.transformDamage = true;
            g_pHyprRenderer->setViewport(0, 0, monitor->m_pixelSize.x, monitor->m_pixelSize.y);
            g_pHyprRenderer->setProjectionType(ctx, Render::RPT_OUTPUT);
            const auto& style = outline->style;
            const int radius = static_cast<int>(style.radius * monitor->m_scale);
            if (style.glowSize && style.glowOpacity > 0) {
                const Config::CGradientValueData glow{color(style.glowColor)};
                gl->renderInnerGlow(ctx, outline->box, radius, 2.F, static_cast<int>(style.glowSize * monitor->m_scale),
                                    glow, 2, static_cast<float>(style.glowOpacity));
            }
            if (style.borderWidth) {
                const Config::CGradientValueData border{color(style.borderColor)};
                Render::GL::CHyprOpenGLImpl::SBorderRenderData data;
                data.round = radius;
                data.borderSize = std::max(1, static_cast<int>(style.borderWidth * monitor->m_scale));
                gl->renderBorder(ctx, outline->box, border, data);
            }
        }
        ctx.m_data.damage.add(dirty);
        ctx.m_data.finalDamage.add(dirty);
        // Intended capture exclusion: paint only the final output after native
        // mirror/MRT copies. Still requires live GPU/capture-path validation.
    }
    void pulse() {
        const auto source = policy.source() ? policy.source()->id : 0;
        const bool changed = !active || source != paintedSource;
        active = true;
        paintedSource = source;
        wl_event_source_timer_update(expiry, 1000); // one-shot, not an idle poll
        if (changed)
            damage();
    }
    void cleanup() {
        active = false;
        if (g_pHyprRenderer)
            damage();
        renderStage.reset();
        if (expiry) {
            wl_event_source_remove(expiry);
            expiry = nullptr;
        }
        if (hook) {
            HyprlandAPI::removeFunctionHook(owner, hook);
            hook = nullptr;
        }
        if (scanoutHook) {
            HyprlandAPI::removeFunctionHook(owner, scanoutHook);
            scanoutHook = nullptr;
        }
        if (running == this)
            running = nullptr;
    }
};
Indicator::Impl* Indicator::Impl::running = nullptr;
Indicator::Indicator(void* owner, SourcePolicy& policy, std::function<CaptureTarget()> resolver) :
    m_impl(std::make_unique<Impl>(owner, policy, std::move(resolver))) {}
Indicator::~Indicator() = default;
void Indicator::configure(const IndicatorSettings& settings) {
    m_impl->damage(); // invalidate old geometry before changing glow extent
    m_impl->settings = settings;
    m_impl->damage();
}
void Indicator::pulse() { m_impl->pulse(); }
} // namespace dynamic_share
