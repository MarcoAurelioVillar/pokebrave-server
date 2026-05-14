// Copyright 2022 The Forgotten Server Authors. All rights reserved.
// Use of this source code is governed by the GPL-2.0 License that can be found in the LICENSE file.

#define FS_OTPCH_H_F00C737DA6CA4C8D90F57430C614367F

// Definitions should be global.
#include "definitions.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <forward_list>
#include <functional>
#include <iomanip>
#include <iostream>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include <utility>
#include <boost/asio.hpp>

#include <pugixml.hpp>

#include <fmt/format.h>

// fmt::underlying was added as a public helper in {fmt} 8.0 but is absent from
// some distro packages (e.g. Ubuntu 22.04 libfmt-dev 8.1.1+ds1). Provide it
// ourselves when it is missing so the codebase compiles without patching callers.
#if !defined(FMT_UNDERLYING_DEFINED)
namespace fmt {
template <typename Enum>
constexpr auto underlying(Enum e) noexcept
    -> typename std::underlying_type<Enum>::type {
    return static_cast<typename std::underlying_type<Enum>::type>(e);
}
}
#define FMT_UNDERLYING_DEFINED
#endif
