#pragma once
#include "IndicatorSettings.hpp"
#include "Selection.hpp"
#include <functional>
#include <memory>

namespace dynamic_share {
class __attribute__((visibility("hidden"))) Indicator {
  public:
    Indicator(void* owner, SourcePolicy&, std::function<CaptureTarget()>);
    ~Indicator();
    void configure(const IndicatorSettings&);
    void pulse();
  private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};
} // namespace dynamic_share
