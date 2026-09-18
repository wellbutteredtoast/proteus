// proteus/Math.hpp
//
// Math! Very important, this mostly wraps over GLMath (glm) since re-implementing this much
// math all at once would drive me insane. This also wraps some GLM functions and makes its own
// math funcs. 
//
// SPDX-License-Identifier: GPLv3-only

#ifndef PROTEUS_MATH_HPP
#define PROTEUS_MATH_HPP

#include "glm/glm.hpp"

namespace Proteus::Math {

using Vec2   = glm::vec2;
using Vec3   = glm::vec3;
using Vec4   = glm::vec<4, float, glm::defaultp>;
using Mat2x2 = glm::mat2x2;
using Mat2x3 = glm::mat2x3;
using Mat3x3 = glm::mat3x3;
using Mat3x4 = glm::mat3x4;
using Mat4x4 = glm::mat4x4;

Vec2 Vec2Add(Vec2 a, Vec2 b);

Vec2 Vec2Multiply(Vec2 a, Vec2 b);

Vec2 Vec2Subtract(Vec2 a, Vec2 b);

Vec3 Vec3Add(Vec3 a, Vec3 b);

Vec3 Vec3Multiply(Vec3 a, Vec3 b);

Vec3 Vec3Subtract(Vec3 a, Vec3 b);

}

#endif /* PROTEUS_MATH_HPP */