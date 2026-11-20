#include "CaptureBridge.hpp"
#include "Canvas.hpp"
#include "FrameDelivery.hpp"
#include "IdleTask.hpp"
#include "HookLookup.hpp"
#include "Placeholder.hpp"
#include "Indicator.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/permissions/DynamicPermissionManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Context.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/helpers/cm/ColorManagement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/managers/screenshare/WorkspaceCaptureSource.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland-workspace-image-capture-source-v1.hpp>

// Internal access is deliberately isolated to this exact-version bridge.
// Dependencies above are included normally before changing access specifiers.
#define private public
#include <hyprland/src/managers/screenshare/ScreenshareManager.hpp>
#undef private

#include <chrono>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <map>
#include <poll.h>
#include <spawn.h>
#include <stdexcept>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

namespace dynamic_share {
namespace {
using namespace Screenshare;
using Clock = std::chrono::steady_clock;

struct RendererAccess : Render::IHyprRenderer {
    // Return the inherited base member pointer without downcasting the renderer.
    static auto windowRenderer() { return &RendererAccess::renderWindow; }
};

// Resolve relative to THIS module, not the process working directory or PATH.
std::string locateHelper() {
    Dl_info info{};
    if (!dladdr(reinterpret_cast<void*>(&locateHelper), &info) || !info.dli_fname)
        return {};
    return (std::filesystem::absolute(info.dli_fname).parent_path() / "dynamic-share-anchor").string();
}

bool sameExecutable(pid_t pid, const std::string& expected) {
    struct stat actual{}, trusted{};
    return pid > 0 && stat(("/proc/" + std::to_string(pid) + "/exe").c_str(), &actual) == 0 &&
        stat(expected.c_str(), &trusted) == 0 && actual.st_dev == trusted.st_dev && actual.st_ino == trusted.st_ino;
}

void schedule(CScreenshareFrame* frame) {
    const auto monitor = frame->m_session ? frame->m_session->monitor() : nullptr;
    if (!monitor)
        return;
    monitor->scheduleFrame(Aquamarine::IOutput::AQ_SCHEDULE_NEEDS_FRAME);
    g_pHyprRenderer->damageMonitor(monitor);
}
} // namespace

struct CaptureBridge::Impl {
    using Share = eScreenshareError (*)(CScreenshareFrame*, SP<IHLBuffer>, const CRegion&, FScreenshareCallback);
    using RenderFunction = void (*)(CScreenshareFrame*, Render::CRenderContext&);
    using SizeFunction = Vector2D (*)(const CScreenshareSession*);

    struct Peer {
        // First member: Wayland destruction listener has a stable address.
        wl_listener destroyed{};
        Impl* owner = nullptr;
        wl_client* client = nullptr;
        PeerId id = 0;
        ~Peer() { wl_list_remove(&destroyed.link); }
    };
    struct Frame : FrameDelivery {
        WP<CScreenshareFrame> parent;
        WP<CScreenshareFrame> native;
        FScreenshareCallback original;
        IdleTask repair;
        IdleTask retire;
        UP<CScreenshareSession> monitorSession;
        UP<CScreenshareFrame> monitorFrame;
        CHyprSignalListener monitorStopped;
        PHLMONITORREF targetMonitor;
        SourceId targetCookie = 0;
        PHLWORKSPACEREF targetWorkspace;
        SP<Screenshare::CWorkspaceCaptureSource> workspaceSource;
        SP<Render::IFramebuffer> scene;
    };

    SourcePolicy& policy;
    Resolver refresh;
    void* handle = nullptr;
    CFunctionHook* shareHook = nullptr;
    CFunctionHook* renderHook = nullptr;
    CFunctionHook* sizeHook = nullptr;
    const CScreenshareSession* validationSession = nullptr;
    Vector2D validationSize;
    bool sourceSized = true;
    Vector2D lastSize{1280, 720};
    Placeholder empty;
    SP<Render::ITexture> emptyTexture;
    bool emptyDirty = true;
    IndicatorSettings indicatorStyle;
    std::unique_ptr<Indicator> indicator;
    PHLWINDOWREF anchor;
    CHyprSignalListener anchorClosed;
    pid_t helperPID = -1;
    int control = -1;
    std::string executable = locateHelper();
    SourceId anchorCookie = 0;
    PeerId nextPeer = 0;
    SessionId nextSession = 0;
    Clock::time_point lastDelivered{};
    std::map<wl_client*, std::unique_ptr<Peer>> peers;
    std::map<CScreenshareFrame*, std::shared_ptr<Frame>> frames;
    static Impl* running;

    Impl(SourcePolicy& p, Resolver r) : policy(p), refresh(std::move(r)) {}
    ~Impl() { stop(); }

    void drawEmpty(Render::CRenderContext& ctx, const Vector2D& size) {
        if (emptyDirty) {
            emptyTexture.reset();
            auto* surface = empty.rasterize();
            if (cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS)
                emptyTexture = g_pHyprRenderer->createTexture(surface);
            cairo_surface_destroy(surface);
            emptyDirty = false;
        }
        if (!emptyTexture || empty.text().empty())
            return;
        const auto textureSize = emptyTexture->m_size;
        const double wanted = std::clamp(std::min(size.x / 1280.0, size.y / 720.0), 0.25, 4.0);
        const double scale = std::min({wanted, size.x * 0.85 / textureSize.x, size.y * 0.75 / textureSize.y});
        const auto drawn = textureSize * scale;
        const CBox box{(size - drawn) / 2.0, drawn};
        CTexPassElement::SRenderData textData{};
        textData.tex = emptyTexture;
        textData.box = box;
        g_pHyprRenderer->draw(ctx, textData, {0, 0, size.x, size.y});
    }

    bool helperAlive() const {
        if (control < 0)
            return false;
        pollfd descriptor{control, POLLIN | POLLHUP, 0};
        return poll(&descriptor, 1, 0) == 0;
    }

    bool owns(PHLWINDOW window) const {
        if (!window || !helperAlive() || !window->wlSurface() || !window->wlSurface()->resource())
            return false;
        pid_t pid = 0;
        uid_t uid = 0;
        gid_t gid = 0;
        wl_client_get_credentials(window->wlSurface()->resource()->client(), &pid, &uid, &gid);
        return pid == helperPID && uid == geteuid() &&
            window->metadata().appID() == "local.hypr.dynamic-share" && sameExecutable(pid, executable);
    }

    void observe(PHLWINDOW window) {
        if (!owns(window) || anchor.lock() == window)
            return;
        anchorClosed.reset();
        anchor = window;
        ++anchorCookie;
        anchorClosed = window->m_events.unmap.listen([this] {
            anchor.reset();
            if (policy.session())
                policy.detach(policy.session()->session);
            lastDelivered = {};
        });
    }

    PeerId trust(wl_client* client) {
        if (const auto it = peers.find(client); it != peers.end())
            return it->second->id;
        pid_t pid = 0;
        uid_t uid = 0;
        gid_t gid = 0;
        wl_client_get_credentials(client, &pid, &uid, &gid);
        // Do not turn arbitrary screenshot tools or title-spoofing clients into
        // dynamically consented shares. XDPH remains the portal trust boundary.
        if (uid != geteuid() || !sameExecutable(pid, "/usr/lib/xdg-desktop-portal-hyprland"))
            return 0;
        auto peer = std::make_unique<Peer>();
        wl_list_init(&peer->destroyed.link);
        peer->owner = this;
        peer->client = client;
        peer->id = ++nextPeer;
        peer->destroyed.notify = [](wl_listener* listener, void*) {
            auto* peer = reinterpret_cast<Peer*>(listener);
            auto* owner = peer->owner;
            if (owner->policy.session() && owner->policy.session()->peer == peer->id)
                owner->policy.detach(owner->policy.session()->session);
            owner->peers.erase(peer->client);
        };
        const auto id = peer->id;
        wl_client_add_destroy_listener(client, &peer->destroyed);
        peers.emplace(client, std::move(peer));
        return id;
    }

    bool dynamic(CScreenshareFrame* frame) {
        const auto* session = frame->m_session.get();
        return helperAlive() && session && session->m_type == SHARE_WINDOW &&
            session->m_window.lock() == anchor.lock() && !anchor.expired() && trust(session->m_client);
    }

    static Vector2D bufferSize(const CScreenshareSession* session) {
        auto& self = *running;
        if (self.validationSession == session)
            return self.validationSize;
        // Workspace copy() checks its constraints again after share(). Freeze
        // only our privately owned delegated session, never a managed session.
        for (const auto& [_, record] : self.frames)
            if (record->monitorSession.get() == session && !record->native.expired())
                return record->native->m_bufferSize;
        const auto original = reinterpret_cast<SizeFunction>(self.sizeHook->m_original);
        if (!self.sourceSized || session->m_type != SHARE_WINDOW || self.anchor.expired() ||
            session->m_window.lock() != self.anchor.lock() || !self.helperAlive() || !self.trust(session->m_client))
            return original(session);
        const auto target = self.refresh();
        Vector2D requested;
        if (target.monitor)
            requested = target.monitor->m_transformedSize;
        else if (target.workspace && target.workspace->m_monitor)
            requested = target.workspace->m_monitor->m_transformedSize;
        else if (target.window) {
            const auto monitor = target.window->m_monitor.lock();
            if (monitor)
                requested = (target.window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) * monitor->m_scale).round();
        }
        // Keep the last useful canvas for empty streams; some encoders reject
        // 1x1 constraints. Avoid unbounded allocations for pathological geometry.
        if (requested.x >= 1 && requested.y >= 1 && requested.x <= 16384 && requested.y <= 16384)
            self.lastSize = requested;
        return self.lastSize;
    }

    void retire(const std::shared_ptr<Frame>& record) {
        record->retire.arm(g_pCompositor->m_wlEventLoop, [this, weak = std::weak_ptr<Frame>(record)] {
            const auto record = weak.lock();
            if (!record)
                return;
            if (record->native.expired()) {
                std::erase_if(frames, [&](const auto& item) { return item.second == record; });
                return;
            }
            auto* native = record->native.get();
            if (native->m_copyInFlight)
                return; // native completion will request retirement again
            record->repair.cancel();
            native->m_callback = record->original;
            native->m_copied = true;
            const auto it = frames.find(native);
            if (it != frames.end() && it->second == record)
                frames.erase(it);
        });
    }

    bool repairBlank(const std::shared_ptr<Frame>& record) {
        record->forceBlank = true;
        return record->repair.arm(g_pCompositor->m_wlEventLoop, [weak = std::weak_ptr<Frame>(record)] {
            const auto record = weak.lock();
            auto* frame = record && !record->native.expired() ? record->native.get() : nullptr;
            if (!frame || record->parent.expired() || !record->parent->m_session)
                return;
            // The private workspace copy path can reject denied permissions
            // before render(). Use the anchor's native path for the replacement,
            // which our render hook can paint black even while permission-denied.
            frame->m_session = record->parent->m_session;
            if (!frame->m_session->isActive())
                return;
            frame->m_copied = false;
            frame->m_failed = false;
            frame->m_damage = CRegion(0, 0, frame->m_bufferSize.x, frame->m_bufferSize.y);
            auto& pending = Screenshare::mgr()->m_pendingFrames;
            std::erase_if(pending, [&](const auto& item) { return item.expired() || item.get() == frame; });
            pending.emplace_back(record->native);
            schedule(frame);
        });
    }

    static eScreenshareError share(CScreenshareFrame* native, SP<IHLBuffer> buffer, const CRegion& damage, FScreenshareCallback callback) {
        auto& self = *running;
        auto original = reinterpret_cast<Share>(self.shareHook->m_original);
        // A freed dynamic frame's address may be reused for an ordinary share.
        // Weak lifetime identity, not a raw pointer key, decides ownership.
        std::erase_if(self.frames, [](const auto& item) { return item.second->native.expired(); });
        for (const auto& [_, record] : self.frames)
            if (record->parent.expired() && !record->native.expired())
                self.retire(record);
        if (!self.dynamic(native))
            return original(native, std::move(buffer), damage, std::move(callback));

        auto record = std::make_shared<Frame>();
        record->parent = native->m_self;
        record->native = native->m_self;
        record->original = std::move(callback);
        const auto target = self.refresh();
        if ((target.monitor || target.workspace) && !self.policy.locked()) {
            if (target.workspace) {
                record->workspaceSource = makeShared<CWorkspaceCaptureSource>(target.workspace,
                    HYPRLAND_WORKSPACE_IMAGE_CAPTURE_SOURCE_MANAGER_V1_CAPTURE_MODE_WINDOWS_ONLY);
                record->monitorSession = Screenshare::mgr()->newSession(native->m_session->m_client, record->workspaceSource);
                record->targetWorkspace = target.workspace;
            } else
                record->monitorSession = Screenshare::mgr()->newSession(native->m_session->m_client, target.monitor);
            if (record->monitorSession && record->monitorSession->isActive()) {
                // A real native monitor frame requests the monitor mirror FB and
                // uses its normal privacy masks, damage scheduling and fences.
                // Never mutate the shared anchor/ordinary managed sessions.
                record->monitorSession->m_formats = native->m_session->allowedFormats();
                record->monitorFrame = record->monitorSession->nextFrame(native->m_overlayCursor);
                record->monitorFrame->m_bufferSize = native->m_bufferSize;
                record->native = record->monitorFrame->m_self;
                record->targetMonitor = target.monitor;
                record->targetCookie = self.policy.source() ? self.policy.source()->id : 0;
                native->m_damage = CRegion(0, 0, native->m_bufferSize.x, native->m_bufferSize.y);
                record->monitorStopped = record->monitorSession->m_events.stopped.listen([weak = std::weak_ptr<Frame>(record)] {
                    const auto record = weak.lock();
                    if (!record || record->native.expired() || record->parent.expired())
                        return;
                    // A disconnected output must produce an empty frame, not
                    // leave the portal frozen forever waiting on that output.
                    record->forceBlank = true;
                    record->native->m_session = record->parent->m_session;
                    if (!record->native->m_copyInFlight && !record->native->m_copied)
                        schedule(record->native.get());
                });
            } else
                record->forceBlank = true;
        }
        auto* capture = record->native.get();
        self.frames.insert_or_assign(capture, record);
        const auto previousSession = self.validationSession;
        const auto previousSize = self.validationSize;
        self.validationSession = capture->m_session.get();
        self.validationSize = capture->m_bufferSize;
        Render::CScopeGuard restoreConstraints([&] {
            self.validationSession = previousSession;
            self.validationSize = previousSize;
        });
        // Freeze constraints only for validation of THIS already-advertised
        // frame. The following request can renegotiate to the new target size.
        const auto result = original(capture, std::move(buffer), damage, [&self, weak = std::weak_ptr<Frame>(record)](eScreenshareResult result) {
            const auto record = weak.lock();
            if (!record)
                return;
            if (record->parent.expired()) {
                // Timestamp is emitted before copy() starts rendering. A
                // cancelled parent must not keep writing into its old buffer.
                if (!record->native.expired() && !record->native->m_copyInFlight) {
                    record->native->m_copied = true;
                    record->native->m_failed = true;
                }
                self.retire(record);
                return;
            }
            if (result != RESULT_COPIED) {
                if (result == RESULT_NOT_COPIED) {
                    if (record->finished)
                        return;
                    if (record->monitorFrame && !record->forceBlank && self.repairBlank(record))
                        return;
                    record->finished = true;
                }
                record->original(result);
                if (result == RESULT_NOT_COPIED)
                    self.retire(record);
                return;
            }
            self.refresh();
            auto* frame = record->native.expired() ? nullptr : record->native.get();
            if (!frame || !frame->m_session)
                return;
            const auto placeholder = self.anchor.lock();
            const bool permitted = placeholder && placeholder->m_ruleApplicator &&
                !placeholder->m_ruleApplicator->noScreenShare().valueOrDefault() &&
                self.peers.contains(frame->m_session->m_client) && g_pDynamicPermissionManager &&
                g_pDynamicPermissionManager->clientPermissionMode(frame->m_session->m_client, PERMISSION_TYPE_SCREENCOPY) == PERMISSION_RULE_ALLOW_MODE_ALLOW;
            const auto completion = record->complete(self.policy, permitted);
            if (completion == Completion::Ignore)
                return;
            if (completion == Completion::RepairBlank) {
                // Native completion has established explicit/implicit ordering.
                // The replacement uses that same renderer and retained buffer.
                // Do not publish stale pixels or send Failed (stock
                // XDPH can stall on Failed). Reuse this native buffer for black.
                const bool queued = self.repairBlank(record);
                if (!queued) {
                    record->finished = true;
                    record->original(RESULT_NOT_COPIED);
                    self.retire(record);
                }
                return;
            }
            self.lastDelivered = Clock::now();
            if (self.indicator)
                self.indicator->pulse();
            record->original(result);
            self.retire(record); // after the native callback/member returns
        });
        if (result == ERROR_NONE)
            schedule(capture); // request-driven, on the actual monitor for monitor targets
        else
            self.frames.erase(capture);
        return result;
    }

    static void render(CScreenshareFrame* native, Render::CRenderContext& ctx) {
        auto& self = *running;
        const auto it = self.frames.find(native);
        if (it == self.frames.end() || it->second->native.expired() || it->second->native.get() != native) {
            reinterpret_cast<RenderFunction>(self.renderHook->m_original)(native, ctx);
            return;
        }
        const auto record = it->second;
        record->rendered.reset();
        const auto size = native->m_bufferSize;
        // Workspace beginCopy() uses a monitor-sized isolated work buffer.
        // Empty exports must be painted into the actual export canvas too.
        const auto output = ctx.m_data.outFB;
        g_pHyprRenderer->bindFB(ctx, output);
        ctx.m_gl.offloadedFramebuffer = false;
        CRegion full(0, 0, size.x, size.y);
        ctx.m_data.fbSize = size;
        ctx.m_data.transformDamage = false;
        ctx.m_data.noSimplify = true;
        ctx.m_data.renderModif = {};
        ctx.m_data.clipBox = {};
        g_pHyprRenderer->setProjectionType(ctx, Render::RPT_EXPORT);
        g_pHyprRenderer->setViewport(0, 0, size.x, size.y);
        g_pHyprRenderer->draw(ctx, CClearPassElement::SClearData{{0, 0, 0, 1}}, full);
        g_pHyprRenderer->startRenderPass(ctx);
        const auto empty = [&] { self.drawEmpty(ctx, size); };

        // Never replay the native permission snapshot: it contains the anchor,
        // not a revocable ticket for the currently selected dynamic source.
        const auto target = self.refresh();
        const auto* session = native->m_session.get();
        const auto placeholder = self.anchor.lock();
        if (record->parent.expired() || record->forceBlank || !session || (!target.window && !target.monitor && !target.workspace) || self.policy.locked() ||
            !placeholder || !placeholder->m_ruleApplicator || placeholder->m_ruleApplicator->noScreenShare().valueOrDefault() ||
            !self.peers.contains(session->m_client) || !g_pDynamicPermissionManager ||
            g_pDynamicPermissionManager->clientPermissionMode(session->m_client, PERMISSION_TYPE_SCREENCOPY) != PERMISSION_RULE_ALLOW_MODE_ALLOW)
            return empty();
        const auto peer = self.trust(session->m_client);
        if (!self.policy.session())
            self.policy.attach({++self.nextSession, peer, self.anchorCookie});
        const auto decision = self.policy.decide(peer, self.anchorCookie);
        if (decision.action != Action::Capture)
            return empty();
        if (target.monitor && (!record->monitorFrame || record->targetMonitor.lock() != target.monitor ||
                               !self.policy.source() || record->targetCookie != self.policy.source()->id))
            return empty();
        if (target.workspace && (!record->workspaceSource || record->targetWorkspace.lock() != target.workspace ||
                                 !self.policy.source() || record->targetCookie != self.policy.source()->id))
            return empty();
        if (target.window && record->monitorFrame)
            return empty(); // finish an old monitor request empty; next request uses the window
        const auto source = target.window;
        const auto monitor = target.monitor ? target.monitor :
            (target.workspace ? target.workspace->m_monitor.lock() : source->m_monitor.lock());
        if (!monitor || !monitor->m_enabled || (source && (!source->wlSurface() || !source->wlSurface()->resource())))
            return empty();
        const auto sourceSize = !source ? monitor->m_transformedSize :
            source->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) * monitor->m_scale;
        const auto fit = fitCanvas(size.x, size.y, sourceSize.x, sourceSize.y);
        if (!fit || sourceSize.x > 16384 || sourceSize.y > 16384)
            return empty();

        // These flags must survive until the queued render pass is executed by
        // native endRender(). Native finishRender() resets the entire context.
        ctx.m_renderingCapture = true;
        ctx.m_blockSurfaceFeedback = source && g_pHyprRenderer->shouldRenderWindow(source);
        if (!source) {
            // Native monitor painting is immediate and explicitly disables
            // renderModif for its mirror texture; workspace painting queues a
            // monitor-sized scene. Render both unscaled, including privacy masks
            // and cursor, then fit the complete result into the export canvas.
            record->scene = g_pHyprRenderer->createFB("dynamic-share scene");
            if (!record->scene || !record->scene->alloc(sourceSize.x, sourceSize.y, DRM_FORMAT_ARGB8888))
                return empty();
            record->scene->setImageDescription(NColorManagement::DEFAULT_SRGB_IMAGE_DESCRIPTION);
            {
                const auto saved = ctx.saveDrawState();
                const auto bound = g_pHyprRenderer->bindTempFB(ctx, record->scene);
                ctx.m_data.fbSize = sourceSize;
                ctx.m_data.damage = CRegion(0, 0, sourceSize.x, sourceSize.y);
                ctx.m_data.finalDamage = ctx.m_data.damage;
                ctx.m_data.renderModif = {};
                ctx.m_data.transformDamage = false;
                g_pHyprRenderer->setProjectionType(ctx, Render::RPT_EXPORT);
                g_pHyprRenderer->setViewport(0, 0, sourceSize.x, sourceSize.y);
                g_pHyprRenderer->draw(ctx, CClearPassElement::SClearData{{0, 0, 0, 1}}, ctx.m_data.damage);
                Render::CRenderPass scenePass;
                const auto redirected = Render::IHyprRenderer::redirectPass(ctx, &scenePass);
                const auto advertised = native->m_bufferSize;
                native->m_bufferSize = sourceSize;
                const Render::CScopeGuard restoreSize([&] { native->m_bufferSize = advertised; });
                if (target.workspace)
                    native->renderWorkspace(ctx);
                else
                    native->renderMonitor(ctx);
                scenePass.render(ctx, ctx.m_data.damage);
            }
            CTexPassElement::SRenderData composite{};
            composite.tex = record->scene->getTexture();
            composite.box = CBox{{fit->x, fit->y}, sourceSize * fit->scale};
            g_pHyprRenderer->draw(ctx, composite, full);
            record->rendered = decision.frame;
            return;
        }
        Render::SRenderModifData modification;
        modification.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_SCALE, fit->scale);
        modification.modifs.emplace_back(Render::SRenderModifData::RMOD_TYPE_TRANSLATE, Vector2D{fit->x, fit->y});
        auto& pass = Render::IHyprRenderer::currentPass(ctx);
        pass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = modification}));
        // Standalone rendering: no shell, workspace scene, background, or borders.
        // The native renderer also applies capture privacy to window content.
        {
            (g_pHyprRenderer.get()->*RendererAccess::windowRenderer())(
                ctx, source, monitor, Render::SWindowRenderPresentation{}, Time::steadyNow(), false, Render::RENDER_PASS_ALL, true, true);
            if (native->m_overlayCursor && g_pSeatManager && Desktop::focusState()->window() == source) {
                const auto pointerResource = g_pSeatManager->m_state.pointerFocus.lock();
                const auto pointerSurface = pointerResource ? Desktop::View::CWLSurface::fromResource(pointerResource) : nullptr;
                const auto box = pointerSurface ? pointerSurface->getSurfaceBoxGlobal() : std::nullopt;
                if (box && !box->intersection(source->getFullWindowBoundingBox()).empty()) {
                    CRegion cursorDamage(0, 0, INT16_MAX, INT16_MAX);
                    Pointer::mgr()->renderSoftwareCursorsFor(ctx, monitor, Time::steadyNow(), cursorDamage,
                        Pointer::mgr()->untransformedPosition() - source->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT), true, true);
                }
            }
        }
        pass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = Render::SRenderModifData{}}));
        record->rendered = decision.frame;
    }

    CFunctionHook* install(const HookTarget& target, const void* replacement) {
        void* address = resolveHook(target, [this](const std::string& query) {
            return HyprlandAPI::findFunctionsByName(handle, query);
        });
        auto* hook = HyprlandAPI::createFunctionHook(handle, address, replacement);
        if (!hook || !hook->hook()) {
            if (hook)
                HyprlandAPI::removeFunctionHook(handle, hook);
            throw std::runtime_error("could not install capture hook: " + std::string{target.demangledPrefix});
        }
        return hook;
    }

    std::pair<bool, std::string> start(void* owner) {
        if (helperAlive())
            return {true, "Dynamic Share source is already enabled"};
        if (control >= 0)
            stop();
        handle = owner;
        if (executable.empty() || access(executable.c_str(), X_OK))
            return {false, "dynamic-share-anchor is missing beside the plugin"};
        if (!g_pCompositor || !g_pCompositor->m_wlEventLoop || !g_pHyprRenderer || !g_pEventLoopManager ||
            !g_pDynamicPermissionManager || !g_pSessionLockManager)
            return {false, "required compositor managers are unavailable; refusing to enable capture"};
        try {
            if (running && running != this)
                throw std::runtime_error("another Dynamic Share bridge is running");
            running = this;
            if (!sizeHook)
                sizeHook = install(SIZE_HOOK, reinterpret_cast<void*>(&bufferSize));
            if (!renderHook)
                renderHook = install(RENDER_HOOK, reinterpret_cast<void*>(&render));
            if (!shareHook)
                shareHook = install(SHARE_HOOK, reinterpret_cast<void*>(&share));
            if (indicatorStyle.enabled && !indicator) {
                indicator = std::make_unique<Indicator>(handle, policy, refresh);
                indicator->configure(indicatorStyle);
            }

            int sockets[2];
            if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets))
                throw std::runtime_error("could not create helper lifetime socket");
            posix_spawn_file_actions_t actions;
            auto error = posix_spawn_file_actions_init(&actions);
            if (error) {
                close(sockets[0]);
                close(sockets[1]);
                throw std::runtime_error("could not initialize helper spawn actions");
            }
            constexpr int CHILD_FD = 198;
            error = posix_spawn_file_actions_addclose(&actions, sockets[0]);
            if (!error)
                error = posix_spawn_file_actions_adddup2(&actions, sockets[1], CHILD_FD);
            if (!error && sockets[1] != CHILD_FD)
                error = posix_spawn_file_actions_addclose(&actions, sockets[1]);
            char* arguments[] = {executable.data(), const_cast<char*>("--control-fd"), const_cast<char*>("198"), nullptr};
            if (!error)
                error = posix_spawn(&helperPID, executable.c_str(), &actions, nullptr, arguments, environ);
            posix_spawn_file_actions_destroy(&actions);
            close(sockets[1]);
            if (error) {
                close(sockets[0]);
                throw std::runtime_error(std::string("could not spawn helper: ") + std::strerror(error));
            }
            if (control >= 0)
                close(control);
            control = sockets[0];
            return {true, "Dynamic Share enabled; choose its window in the sharing picker"};
        } catch (const std::exception& error) {
            stop();
            return {false, error.what()};
        }
    }

    void stop() {
        indicator.reset();
        // No plugin-owned callback may remain in a native frame after dlclose.
        // Keep native buffers/fences alive, but suppress any later Ready event.
        for (auto& [_, record] : frames) {
            record->repair.cancel();
            record->retire.cancel();
            if (auto* frame = record->native.expired() ? nullptr : record->native.get()) {
                frame->m_copied = true;
                frame->m_failed = true;
                frame->m_callback = record->original;
                if (!record->finished)
                    record->original(RESULT_NOT_COPIED);
            }
        }
        frames.clear();
        peers.clear();
        if (policy.session())
            policy.detach(policy.session()->session);
        anchorClosed.reset();
        anchor.reset();
        if (control >= 0) {
            close(control); // helper exits on HUP; never signal a reusable PID
            control = -1;
        }
        if (helperPID > 0)
            waitpid(helperPID, nullptr, WNOHANG);
        helperPID = -1;
        if (shareHook) {
            HyprlandAPI::removeFunctionHook(handle, shareHook);
            shareHook = nullptr;
        }
        if (renderHook) {
            HyprlandAPI::removeFunctionHook(handle, renderHook);
            renderHook = nullptr;
        }
        if (sizeHook) {
            HyprlandAPI::removeFunctionHook(handle, sizeHook);
            sizeHook = nullptr;
        }
        if (running == this)
            running = nullptr;
        lastDelivered = {};
        emptyTexture.reset();
        emptyDirty = true;
    }
};

CaptureBridge::Impl* CaptureBridge::Impl::running = nullptr;
CaptureBridge::CaptureBridge(SourcePolicy& policy, Resolver resolver) : m_impl(std::make_unique<Impl>(policy, std::move(resolver))) {}
CaptureBridge::~CaptureBridge() = default;
std::pair<bool, std::string> CaptureBridge::start(void* handle) { return m_impl->start(handle); }
void CaptureBridge::stop() { m_impl->stop(); }
void CaptureBridge::observe(PHLWINDOW window) { m_impl->observe(window); }
bool CaptureBridge::isAnchor(PHLWINDOW window) const { return window && m_impl->anchor.lock() == window; }
bool CaptureBridge::available() const { return hookInstalled() && helperRunning() && !m_impl->anchor.expired(); }
bool CaptureBridge::hookInstalled() const { return m_impl->shareHook && m_impl->renderHook && m_impl->sizeHook; }
bool CaptureBridge::active() const { return helperRunning() && Clock::now() - m_impl->lastDelivered < std::chrono::seconds(1); }
bool CaptureBridge::helperRunning() const { return m_impl->helperAlive(); }
std::string CaptureBridge::helperPath() const { return m_impl->executable; }
void CaptureBridge::sourceSizing(bool enabled) {
    if (m_impl->sourceSized != enabled) {
        m_impl->sourceSized = enabled;
        m_impl->policy.invalidateFrames();
    }
}
bool CaptureBridge::sourceSizing() const { return m_impl->sourceSized; }
bool CaptureBridge::placeholder(std::string text, int fontSize) {
    if (!Placeholder::valid(text, fontSize))
        return false;
    if (text != m_impl->empty.text() || fontSize != m_impl->empty.fontSize()) {
        m_impl->empty.configure(std::move(text), fontSize);
        m_impl->emptyDirty = true; // upload/release textures only in a render context
    }
    return true;
}
std::string CaptureBridge::placeholderText() const { return m_impl->empty.text(); }
int CaptureBridge::placeholderFontSize() const { return m_impl->empty.fontSize(); }
std::pair<bool, std::string> CaptureBridge::indicator(const IndicatorSettings& settings) {
    if (!settings.valid())
        return {false, "invalid indicator geometry or opacity"};
    try {
        if (settings.enabled && hookInstalled() && !m_impl->indicator)
            m_impl->indicator = std::make_unique<Indicator>(m_impl->handle, m_impl->policy, m_impl->refresh);
        if (m_impl->indicator)
            m_impl->indicator->configure(settings);
        if (!settings.enabled)
            m_impl->indicator.reset();
        m_impl->indicatorStyle = settings;
        return {true, "indicator settings updated"};
    } catch (const std::exception& error) {
        return {false, error.what()};
    }
}
IndicatorSettings CaptureBridge::indicatorSettings() const { return m_impl->indicatorStyle; }
} // namespace dynamic_share
