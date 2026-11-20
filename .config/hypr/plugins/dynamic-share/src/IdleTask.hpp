#pragma once

#include <wayland-server-core.h>
#include <functional>
#include <utility>

namespace dynamic_share {

// Own the real Wayland source, not a closure in Hyprland's doLater batch.
// Cancelling one pending task must still work from another idle callback.
class IdleTask {
  public:
    IdleTask() = default;
    ~IdleTask() { cancel(); }
    IdleTask(const IdleTask&) = delete;
    IdleTask& operator=(const IdleTask&) = delete;

    bool arm(wl_event_loop* loop, std::function<void()> callback) {
        cancel();
        m_callback = std::move(callback);
        m_source = wl_event_loop_add_idle(loop, dispatch, this);
        if (!m_source)
            m_callback = {};
        return m_source != nullptr;
    }

    void cancel() {
        if (m_source) {
            wl_event_source_remove(m_source);
            m_source = nullptr;
        }
        m_callback = {};
    }

  private:
    static void dispatch(void* data) {
        auto* task = static_cast<IdleTask*>(data);
        task->m_source = nullptr; // Wayland removes this one-shot after dispatch.
        auto callback = std::move(task->m_callback);
        if (callback)
            callback();
    }

    wl_event_source* m_source = nullptr;
    std::function<void()> m_callback;
};

} // namespace dynamic_share
