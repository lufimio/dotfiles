#pragma once

#include <cstdint>
#include <optional>

namespace dynamic_share {

using SourceId = std::uint64_t;
using PeerId = std::uint64_t;
using SessionId = std::uint64_t;
enum class SourceKind { Window, Monitor, Workspace };

struct Source {
    // Lifetime/selection cookie, not a window title, PID, or reusable address.
    SourceId id = 0;
    bool privateContent = false;
    SourceKind kind = SourceKind::Window;
};

struct ConsentGrant {
    // A future trusted capture bridge must establish BOTH portal consent and
    // explicit dynamic-mode opt-in. No Lua function creates these grants.
    SessionId session = 0;
    PeerId peer = 0;
    SourceId anchor = 0;
};

enum class Action { PassThrough, Blank, Capture };
enum class Reason { NoDynamicSession, WrongSession, NoSource, Locked, Private, Ready };

struct FrameTicket {
    SessionId session = 0;
    SourceId source = 0;
    std::uint64_t generation = 0;
};

struct Decision {
    Action action = Action::PassThrough;
    Reason reason = Reason::NoDynamicSession;
    std::optional<FrameTicket> frame;
};

// Compositor-thread state, not a thread-safe capture queue. A future bridge must
// revalidate tickets at delivery and handle already-submitted buffers separately.
class SourcePolicy {
  public:
    bool select(Source source);
    void clearSource();
    void invalidate(SourceId source);
    void setPrivate(SourceId source, bool value);
    void setLocked(bool value);
    void invalidateFrames();
    void reset();

    // Internal bridge API only. Never expose attach() as a consent-bypass bind.
    bool attach(ConsentGrant grant);
    void detach(SessionId session);

    [[nodiscard]] Decision decide(PeerId peer, SourceId anchor) const;
    [[nodiscard]] bool accepts(const FrameTicket& frame) const;
    [[nodiscard]] const std::optional<Source>& source() const { return m_source; }
    [[nodiscard]] const std::optional<ConsentGrant>& session() const { return m_session; }
    [[nodiscard]] std::uint64_t generation() const { return m_generation; }
    [[nodiscard]] bool locked() const { return m_locked; }

  private:
    std::optional<Source> m_source;
    std::optional<ConsentGrant> m_session;
    std::uint64_t m_generation = 1;
    bool m_locked = false;
};

} // namespace dynamic_share
