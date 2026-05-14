#include "battle/BattleWire.h"
#include "test_framework.h"

#include <string>
#include <string_view>

// Fixtures: the Contract v1 §8 round-trip examples, compacted (no whitespace).
// "Byte-identical to §8 examples modulo `ts` and ULID `id`/`session`" — these
// strings are the canonical compact form; values for `ts`, `id`, `session`
// match the contract verbatim so reviewers can diff against the spec.

namespace {

using namespace pokebrave::battle;

const std::string kStart_8_1 =
    R"({"v":1,"op":"battle:start","id":"01HZA0","session":"S1","ts":1715623200000,)"
    R"("body":{)"
    R"("session":"S1","turn":1,)"
    R"("you":{"slot":"A","userId":12345},)"
    R"("opponent":{"slot":"B","kind":"npc","label":"Trainer Joey","userId":null},)"
    R"("arena":{"id":"arena_pewter_gym","lockTeleport":true},)"
    R"("participants":[)"
    R"({"slot":"A","active":{"pid":"p_A_0","speciesId":25,"speciesName":"Pikachu","level":50,"hp":{"current":145,"max":145},"status":null,"fainted":false,"moves":[{"moveId":"thunderbolt","name":"Thunderbolt","pp":{"current":15,"max":15},"priority":0,"target":"opponent_active"},{"moveId":"quick_attack","name":"Quick Attack","pp":{"current":30,"max":30},"priority":1,"target":"opponent_active"}]},"bench":[]},)"
    R"({"slot":"B","active":{"pid":"p_B_0","speciesId":19,"speciesName":"Rattata","level":14,"hp":{"current":50,"max":50},"status":null,"fainted":false},"bench":[]})"
    R"(],)"
    R"("rules":{"format":"1v1","turnTimeoutMs":30000,"forcedSwitchTimeoutMs":15000,"reconnectGraceMs":60000,"allowSurrender":true,"maxTurns":200},)"
    R"("choiceWindow":{"turn":1,"deadline":1715623230000,"valid":{"slot":"A","actions":["move","switch","surrender"]}})"
    R"(}})";

const std::string kChoices_8_1 =
    R"({"v":1,"op":"battle:choices","id":"01HZA1","session":"S1","ts":1715623205000,)"
    R"("body":{"session":"S1","turn":1,"slot":"A",)"
    R"("choice":{"kind":"move","moveId":"thunderbolt","target":"B:active"},)"
    R"("clientNonce":"c_0001"}})";

const std::string kResolve_8_1 =
    R"({"v":1,"op":"battle:resolve","id":"01HZA2","session":"S1","ts":1715623206500,)"
    R"("body":{"session":"S1","turn":1,"ordered":true,)"
    R"("events":[)"
    R"({"seq":0,"kind":"choices_locked","bySlot":{"A":{"kind":"move","moveId":"thunderbolt","target":"B:active","clientNonce":"c_0001"},"B":{"kind":"move","moveId":"tackle","target":"A:active","clientNonce":null}},"order":[{"slot":"A","priority":0,"effectiveSpeed":90},{"slot":"B","priority":0,"effectiveSpeed":60}],"tieBreak":null},)"
    R"({"seq":1,"kind":"action_start","slot":"A","action":{"kind":"move","moveId":"thunderbolt","target":"B:active"}},)"
    R"({"seq":2,"kind":"damage","source":"A:active","target":"B:active","amount":32,"after":{"hp":18},"crit":false,"effectiveness":1.0},)"
    R"({"seq":3,"kind":"status_inflict","target":"B:active","status":{"name":"paralysis","stacks":1,"remainingTurns":null}},)"
    R"({"seq":4,"kind":"action_start","slot":"B","action":{"kind":"move","moveId":"tackle","target":"A:active"}},)"
    R"({"seq":5,"kind":"action_skipped","slot":"B","reason":"paralysis_full"},)"
    R"({"seq":6,"kind":"turn_end_tick","slot":"B","effect":"status:paralysis","delta":null})"
    R"(],)"
    R"("publicState":{)"
    R"("A:active":{"hp":{"current":145,"max":145},"status":null,"fainted":false},)"
    R"("B:active":{"hp":{"current":18,"max":50},"status":{"name":"paralysis","stacks":1,"remainingTurns":null},"fainted":false})"
    R"(},)"
    R"("next":{"kind":"awaiting_choices","choiceWindow":{"turn":2,"deadline":1715623236500,"valid":{"slot":"A","actions":["move","switch","surrender"]}}})"
    R"(}})";

const std::string kAck_8_1 =
    R"({"v":1,"op":"battle:ack","id":"01HZA3","session":"S1","ts":1715623207000,)"
    R"("body":{"session":"S1","ref":"01HZA2","kind":"applied"}})";

const std::string kResolveTerminal_8_2 =
    R"({"v":1,"op":"battle:resolve","id":"01HZB0","session":"S1","ts":1715623260000,)"
    R"("body":{"session":"S1","turn":4,"ordered":true,)"
    R"("events":[)"
    R"({"seq":0,"kind":"choices_locked","bySlot":{"A":{"kind":"move","moveId":"thunderbolt","target":"B:active","clientNonce":"c_0004"},"B":{"kind":"move","moveId":"tackle","target":"A:active","clientNonce":null}},"order":[{"slot":"A","priority":0,"effectiveSpeed":90},{"slot":"B","priority":0,"effectiveSpeed":60}],"tieBreak":null},)"
    R"({"seq":1,"kind":"action_start","slot":"A","action":{"kind":"move","moveId":"thunderbolt","target":"B:active"}},)"
    R"({"seq":2,"kind":"damage","source":"A:active","target":"B:active","amount":18,"after":{"hp":0},"crit":false,"effectiveness":1.0},)"
    R"({"seq":3,"kind":"faint","target":"B:active","reason":"hp_zero"})"
    R"(],)"
    R"("publicState":{)"
    R"("A:active":{"hp":{"current":87,"max":145},"status":null,"fainted":false},)"
    R"("B:active":{"hp":{"current":0,"max":50},"status":null,"fainted":true})"
    R"(},)"
    R"("next":{"kind":"battle_end"}}})";

const std::string kEnd_8_2 =
    R"({"v":1,"op":"battle:end","id":"01HZB1","session":"S1","ts":1715623260500,)"
    R"("body":{"session":"S1","turn":4,)"
    R"("outcome":{"winner":"A"},)"
    R"("reason":"ko",)"
    R"("finalState":{)"
    R"("A:active":{"hp":{"current":87,"max":145},"status":null,"fainted":false},)"
    R"("B:active":{"hp":{"current":0,"max":50},"status":null,"fainted":true})"
    R"(},)"
    R"("rewards":{"xp":{"A":1200,"B":0}},)"
    R"("logRef":"battle:S1"}})";

const std::string kSnapshot_8_3 =
    R"({"v":1,"op":"battle:snapshot","id":"01HZC0","session":"S1","ts":1715623240000,)"
    R"("body":{"session":"S1","snapshotId":"snap_01","turn":2,"state":"awaiting_choices",)"
    R"("you":{"slot":"A","userId":12345},)"
    R"("opponent":{"slot":"B","kind":"npc","label":"Trainer Joey","userId":null},)"
    R"("arena":{"id":"arena_pewter_gym","lockTeleport":true},)"
    R"("rules":{"format":"1v1","turnTimeoutMs":30000,"forcedSwitchTimeoutMs":15000,"reconnectGraceMs":60000,"allowSurrender":true,"maxTurns":200},)"
    R"("participants":[)"
    R"({"slot":"A","active":{"pid":"p_A_0","speciesId":25,"speciesName":"Pikachu","level":50,"hp":{"current":145,"max":145},"status":null,"fainted":false,"moves":[{"moveId":"thunderbolt","name":"Thunderbolt","pp":{"current":14,"max":15},"priority":0,"target":"opponent_active"},{"moveId":"quick_attack","name":"Quick Attack","pp":{"current":30,"max":30},"priority":1,"target":"opponent_active"}]},"bench":[]},)"
    R"({"slot":"B","active":{"pid":"p_B_0","speciesId":19,"speciesName":"Rattata","level":14,"hp":{"current":18,"max":50},"status":{"name":"paralysis","stacks":1,"remainingTurns":null},"fainted":false},"bench":[]})"
    R"(],)"
    R"("publicState":{)"
    R"("A:active":{"hp":{"current":145,"max":145},"status":null,"fainted":false},)"
    R"("B:active":{"hp":{"current":18,"max":50},"status":{"name":"paralysis","stacks":1,"remainingTurns":null},"fainted":false})"
    R"(},)"
    R"("history":{"from":1,"to":1,"truncated":false,"items":[]},)"
    R"("choiceWindow":{"turn":2,"deadline":1715623270000,"valid":{"slot":"A","actions":["move","switch","surrender"]}},)"
    R"("specVersion":"1"}})";

const std::string kBadChoices_8_4 =
    R"({"v":1,"op":"battle:choices","id":"01HZD0","session":"S1","ts":1715623210000,)"
    R"("body":{"session":"S1","turn":2,"slot":"A",)"
    R"("choice":{"kind":"move","moveId":"hyper_beam","target":"B:active"},)"
    R"("clientNonce":"c_bad"}})";

const std::string kError_8_4 =
    R"({"v":1,"op":"battle:error","id":"01HZD1","session":"S1","ts":1715623210100,)"
    R"("body":{"session":"S1","ref":"01HZD0","code":"invalid_choice","message":"Move 'hyper_beam' not in current moveset for p_A_0","retriable":false,)"
    R"("details":{"reason":"unknown_move","moveId":"hyper_beam","knownMoves":["thunderbolt","quick_attack"]}}})";

const std::string kSurrender_8_5 =
    R"({"v":1,"op":"battle:choices","id":"01HZE0","session":"S1","ts":1715623215000,)"
    R"("body":{"session":"S1","turn":3,"slot":"A",)"
    R"("choice":{"kind":"surrender"}}})";

// Helper: decode and require Envelope (test fails otherwise).
Envelope mustDecode(const std::string& s) {
  auto r = decode(s);
  if (std::holds_alternative<WireError>(r)) {
    const auto& e = std::get<WireError>(r);
    ::pokebrave::test::failAssertion(
        "decode() returned WireError", __FILE__, __LINE__,
        e.codeTag() + ": " + e.message + " (at " + e.failedAt + ")");
  }
  return std::get<Envelope>(r);
}

// Helper: decode and require WireError (test fails if it parses).
WireError mustReject(const std::string& s) {
  auto r = decode(s);
  if (std::holds_alternative<Envelope>(r)) {
    ::pokebrave::test::failAssertion("decode() should have rejected", __FILE__,
                                     __LINE__,
                                     "but it accepted: " + s.substr(0, 120));
  }
  return std::get<WireError>(r);
}

} // namespace

// ===== Positive round-trips =====

TEST(WireEnvelope, RoundTrip_8_1_Start) {
  Envelope env = mustDecode(kStart_8_1);
  EXPECT_EQ(env.v, 1);
  EXPECT_TRUE(env.op == Opcode::BattleStart);
  EXPECT_STREQ(env.id, "01HZA0");
  EXPECT_STREQ(env.session, "S1");
  EXPECT_EQ(env.ts, static_cast<std::int64_t>(1715623200000LL));
  EXPECT_TRUE(env.body.isObject());
  // Spot-check a nested body field.
  const auto* you = env.body.find("you");
  EXPECT_TRUE(you != nullptr && you->isObject());
  EXPECT_STREQ(you->find("slot")->asString(), "A");
  EXPECT_EQ(you->find("userId")->asInt(), static_cast<std::int64_t>(12345));
  // Re-encode and decode again; envelopes must be equal.
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_1_Choices) {
  Envelope env = mustDecode(kChoices_8_1);
  EXPECT_TRUE(env.op == Opcode::BattleChoices);
  EXPECT_STREQ(env.session, "S1");
  EXPECT_EQ(env.body.find("turn")->asInt(), static_cast<std::int64_t>(1));
  EXPECT_STREQ(env.body.find("choice")->find("moveId")->asString(),
               "thunderbolt");
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_1_Resolve) {
  Envelope env = mustDecode(kResolve_8_1);
  EXPECT_TRUE(env.op == Opcode::BattleResolve);
  const auto* events = env.body.find("events");
  EXPECT_TRUE(events != nullptr && events->isArray());
  EXPECT_EQ(events->asArray().size(), static_cast<std::size_t>(7));
  // First event must be choices_locked, last must be turn_end_tick.
  EXPECT_STREQ(events->asArray()[0].find("kind")->asString(),
               "choices_locked");
  EXPECT_STREQ(events->asArray()[6].find("kind")->asString(),
               "turn_end_tick");
  // Damage event carries a double effectiveness — number kinds must survive.
  const auto& dmg = events->asArray()[2];
  EXPECT_STREQ(dmg.find("kind")->asString(), "damage");
  EXPECT_TRUE(dmg.find("effectiveness")->isNumber());
  EXPECT_EQ(dmg.find("effectiveness")->asDouble(), 1.0);
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_1_Ack) {
  Envelope env = mustDecode(kAck_8_1);
  EXPECT_TRUE(env.op == Opcode::BattleAck);
  EXPECT_STREQ(env.body.find("ref")->asString(), "01HZA2");
  EXPECT_STREQ(env.body.find("kind")->asString(), "applied");
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_2_TerminalResolve) {
  Envelope env = mustDecode(kResolveTerminal_8_2);
  EXPECT_TRUE(env.op == Opcode::BattleResolve);
  EXPECT_STREQ(env.body.find("next")->find("kind")->asString(), "battle_end");
  // No choiceWindow on terminal resolve.
  EXPECT_TRUE(env.body.find("next")->find("choiceWindow") == nullptr);
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_2_End) {
  Envelope env = mustDecode(kEnd_8_2);
  EXPECT_TRUE(env.op == Opcode::BattleEnd);
  EXPECT_STREQ(env.body.find("outcome")->find("winner")->asString(), "A");
  EXPECT_STREQ(env.body.find("reason")->asString(), "ko");
  EXPECT_STREQ(env.body.find("logRef")->asString(), "battle:S1");
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_3_Snapshot) {
  Envelope env = mustDecode(kSnapshot_8_3);
  EXPECT_TRUE(env.op == Opcode::BattleSnapshot);
  EXPECT_STREQ(env.body.find("state")->asString(), "awaiting_choices");
  EXPECT_STREQ(env.body.find("snapshotId")->asString(), "snap_01");
  EXPECT_STREQ(env.body.find("specVersion")->asString(), "1");
  EXPECT_FALSE(env.body.find("history")->find("truncated")->asBool());
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_TRUE(env == env2);
}

TEST(WireEnvelope, RoundTrip_8_4_BadChoices) {
  // The "bad" payload here is bad at the *choice* level (unknown move). The
  // envelope itself is well-formed — this proves envelope decoding does NOT
  // pre-validate body content (that's the resolver's job, §9.1 additive rule).
  Envelope env = mustDecode(kBadChoices_8_4);
  EXPECT_TRUE(env.op == Opcode::BattleChoices);
  EXPECT_STREQ(env.body.find("choice")->find("moveId")->asString(),
               "hyper_beam");
}

TEST(WireEnvelope, RoundTrip_8_4_ErrorBody) {
  Envelope env = mustDecode(kError_8_4);
  EXPECT_TRUE(env.op == Opcode::BattleError);
  EXPECT_STREQ(env.body.find("code")->asString(), "invalid_choice");
  EXPECT_STREQ(env.body.find("ref")->asString(), "01HZD0");
}

TEST(WireEnvelope, RoundTrip_8_5_Surrender) {
  Envelope env = mustDecode(kSurrender_8_5);
  EXPECT_TRUE(env.op == Opcode::BattleChoices);
  EXPECT_STREQ(env.body.find("choice")->find("kind")->asString(), "surrender");
  // surrender choice has no moveId/target/etc.
  EXPECT_TRUE(env.body.find("choice")->find("moveId") == nullptr);
}

// ===== Reject cases (Contract v1 §1.2, §4.2) =====

TEST(WireEnvelope, Reject_MalformedJSON) {
  WireError e = mustReject(R"({"v":1,"op":"battle:start",)");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.codeTag(), "bad_envelope");
  EXPECT_FALSE(e.retriable());
}

TEST(WireEnvelope, Reject_NotAnObject) {
  WireError e = mustReject("[1,2,3]");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
}

TEST(WireEnvelope, Reject_MissingRequiredField_op) {
  WireError e = mustReject(
      R"({"v":1,"id":"x","session":"s","ts":1,"body":{}})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "op");
}

TEST(WireEnvelope, Reject_MissingRequiredField_body) {
  WireError e = mustReject(
      R"({"v":1,"op":"battle:ack","id":"x","session":"s","ts":1})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "body");
}

TEST(WireEnvelope, Reject_UnknownTopLevelField) {
  WireError e = mustReject(
      R"({"v":1,"op":"battle:ack","id":"x","session":"s","ts":1,"body":{},"extra":"nope"})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "extra");
}

TEST(WireEnvelope, Reject_UnknownVersion) {
  WireError e = mustReject(
      R"({"v":2,"op":"battle:ack","id":"x","session":"s","ts":1,"body":{}})");
  EXPECT_TRUE(e.code == WireErrorCode::VersionMismatch);
  EXPECT_STREQ(e.codeTag(), "version_mismatch");
  EXPECT_TRUE(e.sawV.has_value() && *e.sawV == 2);
  EXPECT_FALSE(e.retriable());
}

TEST(WireEnvelope, Reject_UnknownOpcode) {
  WireError e = mustReject(
      R"({"v":1,"op":"battle:teleport","id":"x","session":"s","ts":1,"body":{}})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "op");
  EXPECT_TRUE(e.sawOp.has_value() && *e.sawOp == "battle:teleport");
}

TEST(WireEnvelope, Reject_WrongType_v_isString) {
  WireError e = mustReject(
      R"({"v":"1","op":"battle:ack","id":"x","session":"s","ts":1,"body":{}})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "v");
}

TEST(WireEnvelope, Reject_WrongType_body_isString) {
  WireError e = mustReject(
      R"({"v":1,"op":"battle:ack","id":"x","session":"s","ts":1,"body":"nope"})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "body");
}

TEST(WireEnvelope, Reject_EmptyId) {
  WireError e = mustReject(
      R"({"v":1,"op":"battle:ack","id":"","session":"s","ts":1,"body":{}})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "id");
}

TEST(WireEnvelope, Reject_EmptySession) {
  WireError e = mustReject(
      R"({"v":1,"op":"battle:ack","id":"x","session":"","ts":1,"body":{}})");
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
  EXPECT_STREQ(e.failedAt, "session");
}

TEST(WireEnvelope, Reject_OversizedPayload) {
  // Build a payload that's well-formed but > 32 KiB.
  std::string big(40000, 'x');
  std::string payload =
      R"({"v":1,"op":"battle:ack","id":"x","session":"s","ts":1,"body":{"pad":")" +
      big + R"("}})";
  EXPECT_TRUE(payload.size() > kMaxEnvelopeBytes);
  WireError e = mustReject(payload);
  EXPECT_TRUE(e.code == WireErrorCode::BadEnvelope);
}

// Encoding the same Envelope twice yields identical bytes (deterministic
// key order). This is the property the Lua round-trip script relies on.
TEST(WireEnvelope, EncodeIsDeterministic) {
  Envelope env = mustDecode(kStart_8_1);
  std::string a = encode(env);
  std::string b = encode(env);
  EXPECT_STREQ(a, b);
}

// Encode-side cap enforcement: oversized snapshot encode throws (rather than
// silently emitting an over-spec payload). Manager is expected to size the
// history window before encoding (§3.4).
TEST(WireEnvelope, Encode_RejectsOversized) {
  // Construct an envelope whose body exceeds the cap.
  json::ObjectT body;
  body.emplace_back("pad", json::Value(std::string(40000, 'x')));
  Envelope env;
  env.op = Opcode::BattleSnapshot;
  env.id = "x";
  env.session = "s";
  env.ts = 1;
  env.body = json::Value(std::move(body));
  bool threw = false;
  try {
    (void)encode(env);
  } catch (const std::runtime_error&) {
    threw = true;
  }
  EXPECT_TRUE(threw);
}

// JSON layer correctness: surrogate pairs, escapes, nested numbers.
TEST(WireEnvelope, Json_SurvivesUtf8Escape) {
  std::string payload =
      R"({"v":1,"op":"battle:ack","id":"x","session":"s","ts":1,"body":{"label":"Joey éè \"hi\""}})";
  Envelope env = mustDecode(payload);
  // Decoded string should contain the decoded UTF-8 bytes.
  EXPECT_STREQ(env.body.find("label")->asString(),
               std::string("Joey \xc3\xa9\xc3\xa8 \"hi\""));
  // Re-encode round-trip should be semantically equal (string content survives).
  std::string re = encode(env);
  Envelope env2 = mustDecode(re);
  EXPECT_STREQ(env2.body.find("label")->asString(),
               env.body.find("label")->asString());
}
