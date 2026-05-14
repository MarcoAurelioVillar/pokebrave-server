#pragma once

#include "battle/BattleJson.h"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <variant>

namespace pokebrave::battle {

// Wire-level constants pinned by Contract v1 §1.
constexpr int kEnvelopeVersion = 1;
constexpr std::size_t kMaxEnvelopeBytes = 32768; // §1.1

enum class Opcode {
  BattleStart,    // S→C
  BattleChoices,  // C→S
  BattleResolve,  // S→C
  BattleSnapshot, // S→C
  BattleEnd,      // S→C
  BattleError,    // both
  BattleAck,      // C→S
};

const char* opcodeTag(Opcode op) noexcept;
std::optional<Opcode> opcodeFromTag(std::string_view tag) noexcept;

struct Envelope {
  int v = kEnvelopeVersion;
  Opcode op = Opcode::BattleStart;
  std::string id;
  std::string session;
  std::int64_t ts = 0;
  json::Value body; // opcode-specific; may be empty object but key is required

  bool operator==(const Envelope& other) const noexcept;
  bool operator!=(const Envelope& other) const noexcept {
    return !(*this == other);
  }
};

// Decode errors mirror Contract v1 §4.2. retriable defaults match §4.2 table.
enum class WireErrorCode {
  BadEnvelope,
  VersionMismatch,
};

struct WireError {
  WireErrorCode code;
  std::string message;       // human readable; safe for logs
  std::string failedAt;      // dotted path of the offending field, "" if N/A
  std::optional<int> sawV;   // populated for VersionMismatch
  std::optional<std::string> sawOp; // populated when op was readable but rejected
  bool retriable() const noexcept;
  std::string codeTag() const noexcept;
};

// Decode result is either Envelope or WireError. We use std::variant for
// clarity over exception-based control flow — decode is a hot path on every
// inbound message and the server must NOT crash a session on malformed input
// (Contract v1 §1.1).
using DecodeResult = std::variant<Envelope, WireError>;

// Decode a single extended-opcode payload string. Enforces:
//   - size <= kMaxEnvelopeBytes (32 KiB)
//   - parseable JSON object at the top level
//   - exact set of top-level keys {v, op, id, session, ts, body}
//   - v is int and equals kEnvelopeVersion (else VersionMismatch)
//   - op is a known Opcode tag string
//   - id is a non-empty string
//   - session is a non-empty string
//   - ts is an int (signed 64-bit)
//   - body is an object (possibly empty)
// Returns WireError on any violation. Unknown body fields are NOT rejected
// here per Contract v1 §9.1 (additive rule); opcode-specific body validation
// is the responsibility of later layers.
DecodeResult decode(std::string_view payload) noexcept;

// Encode an Envelope to a compact JSON string. Output key order is fixed:
// v, op, id, session, ts, body. Throws std::runtime_error if the resulting
// payload would exceed kMaxEnvelopeBytes — callers are expected to size
// snapshot history to stay within the cap before calling encode (Contract
// v1 §3.4 history budget rule).
std::string encode(const Envelope& env);

} // namespace pokebrave::battle
