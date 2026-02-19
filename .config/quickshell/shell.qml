import Quickshell
import qs.Core
import qs.Modules.Bar
import qs.Modules.Lock
import qs.Modules.Overlays

ShellRoot {
    id: root

    Context {
        id: ctx
    }

    // Lock {
    //     context: ctx
    // }
    //
    // Overlay {
    //     context: ctx
    // }
    //
    // ActivateOS {
    //     os: "Linux"
    // }

    BarWindow {
        context: ctx
    }
}
