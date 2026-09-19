#pragma once
//
// Include/Meta/ReturnInfo.hpp
// 
// Details return information rather than using ints, longs or plain bools.
// A shred of indirection is worth for long-term clarity.
//
// SPDX-License-Identifier: MPL-2.0

#include <cstdint>
#include <string_view>

namespace Meta
{
    struct ReturnInfo
    {
        enum class Code : std::uint16_t
        {
            kSuccess = 0,
            kFailure,
            kPartialSuccess,
            kBadArgument,
            kNotImplemented,
            kDeprecated,
            kOutOfMemory,
            kInvalidStateFound,
            kPermissionDenied
        };

        Code code;
        std::string_view message;

        constexpr bool operator ! () const noexcept
        {
            return code == Code::kFailure;
        }
    };

    // Converts a ReturnInfo::Code into a string repr, good for future GUIs and logging
    std::string_view ToString(ReturnInfo::Code code) noexcept;
}