#include "SourcePolicy.hpp"

namespace dynamic_share {

bool SourcePolicy::select(Source source) {
    if (source.id == 0)
        return false;
    m_source = source;
    ++m_generation;
    return true;
}

void SourcePolicy::clearSource() {
    if (!m_source)
        return;
    m_source.reset();
    ++m_generation;
}

void SourcePolicy::invalidate(SourceId source) {
    if (m_source && m_source->id == source)
        clearSource();
}

void SourcePolicy::setPrivate(SourceId source, bool value) {
    if (!m_source || m_source->id != source || m_source->privateContent == value)
        return;
    m_source->privateContent = value;
    ++m_generation;
}

void SourcePolicy::setLocked(bool value) {
    if (m_locked == value)
        return;
    m_locked = value;
    ++m_generation;
}

void SourcePolicy::invalidateFrames() {
    ++m_generation;
}

void SourcePolicy::reset() {
    m_source.reset();
    m_session.reset();
    ++m_generation;
    // Reset must not clear the compositor's lock state.
}

bool SourcePolicy::attach(ConsentGrant grant) {
    if (m_locked || m_session || grant.session == 0 || grant.peer == 0 || grant.anchor == 0)
        return false;
    m_session = grant;
    ++m_generation;
    return true;
}

void SourcePolicy::detach(SessionId session) {
    if (!m_session || m_session->session != session)
        return;
    m_session.reset();
    ++m_generation;
}

Decision SourcePolicy::decide(PeerId peer, SourceId anchor) const {
    if (!m_session)
        return {};
    if (peer != m_session->peer || anchor != m_session->anchor)
        return {Action::PassThrough, Reason::WrongSession, {}};
    if (m_locked)
        return {Action::Blank, Reason::Locked, {}};
    if (!m_source)
        return {Action::Blank, Reason::NoSource, {}};
    if (m_source->privateContent)
        return {Action::Blank, Reason::Private, {}};
    return {Action::Capture, Reason::Ready, FrameTicket{m_session->session, m_source->id, m_generation}};
}

bool SourcePolicy::accepts(const FrameTicket& frame) const {
    return m_session && m_source && !m_locked && !m_source->privateContent &&
        frame.session == m_session->session && frame.source == m_source->id && frame.generation == m_generation;
}

} // namespace dynamic_share
