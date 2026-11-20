#pragma once

#include "SourcePolicy.hpp"

namespace dynamic_share {

enum class Completion { Publish, RepairBlank, Ignore };

// A rendered frame is not permission to publish it later. Native completion
// must validate the ticket again, after GPU writes have been ordered/completed.
struct FrameDelivery {
    std::optional<FrameTicket> rendered;
    bool forceBlank = false;
    bool finished = false;

    Completion complete(const SourcePolicy& policy, bool permitted) {
        if (finished)
            return Completion::Ignore;
        if (rendered && (!policy.accepts(*rendered) || !permitted)) {
            forceBlank = true;
            return Completion::RepairBlank;
        }
        // A real black render has no sensitive ticket and may be published
        // while locked, private, or permission-denied.
        finished = true;
        return Completion::Publish;
    }
};

} // namespace dynamic_share
