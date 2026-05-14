#include "battle/BattleWire.h"

#include <array>
#include <limits>
#include <stdexcept>
#include <string_view>

namespace pokebrave::battle {

namespace {

struct OpcodeMapping {
  Opcode op;
  std::string_view tag;
};

constexpr std::array<OpcodeMapping, 7> kOpcodes = {{
    {Opcode::BattleStart, "battle:start"},
    {Opcode::BattleChoices, "battle:choices"},
    {Opcode::BattleResolve, "battle:resolve"},
    {Opcode::BattleSnapshot, "battle:snapshot"},
    {Opcode::BattleEnd, "battle:end"},
    {Opcode::BattleError, "battle:error"},
    {Opcode::BattleAck, "battle:ack"},
}};

// Allowed top-level envelope keys, exact and case-sensitive (§1.2).
constexpr std::array<std::string_view, 6> kEnvelopeKeys = {
    "v", "op", "id", "session", "ts", "body"};

WireError makeBad(std::string message, std::string failedAt = "") {
  WireError e;
  e.code = WireErrorCode::BadEnvelope;
  e.message = std::move(message);
  e.failedAt = std::move(failedAt);
  return e;
}

WireError makeVersion(int sawV) {
  WireError e;
  e.code = WireErrorCode::VersionMismatch;
  e.message = "envelope schema version not implemented by receiver";
  e.failedAt = "v";
  e.sawV = sawV;
  return e;
}

} // namespace

const char* opcodeTag(Opcode op) noexcept {
  for (const auto& m : kOpcodes) {
    if (m.op == op) return m.tag.data();
  }
  return "battle:unknown";
}

std::optional<Opcode> opcodeFromTag(std::string_view tag) noexcept {
  for (const auto& m : kOpcodes) {
    if (m.tag == tag) return m.op;
  }
  return std::nullopt;
}

bool WireError::retriable() const noexcept {
  switch (code) {
    case WireErrorCode::BadEnvelope:
      return false; // §4.2: bad_envelope is not retriable
    case WireErrorCode::VersionMismatch:
      return false; // §4.2: version_mismatch is not retriable
  }
  return false;
}

std::string WireError::codeTag() const noexcept {
  switch (code) {
    case WireErrorCode::BadEnvelope: return "bad_envelope";
    case WireErrorCode::VersionMismatch: return "version_mismatch";
  }
  return "internal";
}

bool Envelope::operator==(const Envelope& other) const noexcept {
  return v == other.v && op == other.op && id == other.id &&
         session == other.session && ts == other.ts && body == other.body;
}

DecodeResult decode(std::string_view payload) noexcept {
  if (payload.size() > kMaxEnvelopeBytes) {
    return makeBad("payload exceeds 32768-byte cap", "");
  }
  json::Value root;
  try {
    root = json::parse(payload);
  } catch (const json::ParseError& e) {
    return makeBad(std::string("JSON parse error: ") + e.what(), "");
  } catch (const std::exception& e) {
    return makeBad(std::string("unexpected JSON error: ") + e.what(), "");
  } catch (...) {
    return makeBad("unknown JSON error", "");
  }
  if (!root.isObject()) {
    return makeBad("envelope must be a JSON object", "");
  }
  const auto& obj = root.asObject();

  // Strict top-level key set per §1.2.
  for (const auto& kv : obj) {
    bool allowed = false;
    for (const auto& k : kEnvelopeKeys) {
      if (k == kv.first) {
        allowed = true;
        break;
      }
    }
    if (!allowed) {
      return makeBad("unknown top-level envelope field '" + kv.first + "'",
                     kv.first);
    }
  }
  // Required fields.
  for (const auto& k : kEnvelopeKeys) {
    bool present = false;
    for (const auto& kv : obj) {
      if (kv.first == k) {
        present = true;
        break;
      }
    }
    if (!present) {
      return makeBad(std::string("missing required field '") +
                         std::string(k) + "'",
                     std::string(k));
    }
  }

  Envelope env;

  // v: int, must equal kEnvelopeVersion.
  const json::Value* vField = root.find("v");
  if (!vField->isInt()) {
    return makeBad("field 'v' must be an integer", "v");
  }
  std::int64_t vi = vField->asInt();
  if (vi < std::numeric_limits<int>::min() ||
      vi > std::numeric_limits<int>::max()) {
    return makeBad("field 'v' out of int range", "v");
  }
  env.v = static_cast<int>(vi);
  if (env.v != kEnvelopeVersion) {
    return makeVersion(env.v);
  }

  // op: string, must be a known tag.
  const json::Value* opField = root.find("op");
  if (!opField->isString()) {
    return makeBad("field 'op' must be a string", "op");
  }
  auto op = opcodeFromTag(opField->asString());
  if (!op) {
    WireError e = makeBad(
        "unknown opcode '" + opField->asString() + "'", "op");
    e.sawOp = opField->asString();
    return e;
  }
  env.op = *op;

  // id: non-empty string.
  const json::Value* idField = root.find("id");
  if (!idField->isString()) {
    return makeBad("field 'id' must be a string", "id");
  }
  if (idField->asString().empty()) {
    return makeBad("field 'id' must be non-empty", "id");
  }
  env.id = idField->asString();

  // session: non-empty string.
  const json::Value* sField = root.find("session");
  if (!sField->isString()) {
    return makeBad("field 'session' must be a string", "session");
  }
  if (sField->asString().empty()) {
    return makeBad("field 'session' must be non-empty", "session");
  }
  env.session = sField->asString();

  // ts: int64.
  const json::Value* tsField = root.find("ts");
  if (!tsField->isInt()) {
    return makeBad("field 'ts' must be an integer", "ts");
  }
  env.ts = tsField->asInt();

  // body: object.
  const json::Value* bField = root.find("body");
  if (!bField->isObject()) {
    return makeBad("field 'body' must be an object", "body");
  }
  env.body = *bField;

  return env;
}

std::string encode(const Envelope& env) {
  // Build the envelope object with fixed key order.
  json::ObjectT obj;
  obj.emplace_back("v", json::Value(static_cast<std::int64_t>(env.v)));
  obj.emplace_back("op", json::Value(std::string(opcodeTag(env.op))));
  obj.emplace_back("id", json::Value(env.id));
  obj.emplace_back("session", json::Value(env.session));
  obj.emplace_back("ts", json::Value(env.ts));
  obj.emplace_back("body", env.body);
  std::string out = json::serialize(json::Value(std::move(obj)));
  if (out.size() > kMaxEnvelopeBytes) {
    throw std::runtime_error(
        "BattleWire::encode: encoded payload " + std::to_string(out.size()) +
        " bytes exceeds 32768-byte cap (op=" + opcodeTag(env.op) +
        ", session=" + env.session + ")");
  }
  return out;
}

} // namespace pokebrave::battle
