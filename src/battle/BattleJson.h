#pragma once

#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace pokebrave::battle::json {

class Value;

using ArrayT = std::vector<Value>;
using ObjectT = std::vector<std::pair<std::string, Value>>;

class ParseError : public std::runtime_error {
public:
  ParseError(std::string msg, std::size_t pos)
      : std::runtime_error(std::move(msg)), pos_(pos) {}
  std::size_t pos() const noexcept { return pos_; }

private:
  std::size_t pos_;
};

class TypeError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

class Value {
public:
  enum class Kind : std::uint8_t {
    Null,
    Bool,
    Int,
    Double,
    String,
    Array,
    Object,
  };

  Value() noexcept = default;
  Value(std::nullptr_t) noexcept {}
  explicit Value(bool b) noexcept : kind_(Kind::Bool), bool_(b) {}
  explicit Value(int v) noexcept : kind_(Kind::Int), int_(v) {}
  explicit Value(std::int64_t v) noexcept : kind_(Kind::Int), int_(v) {}
  explicit Value(double v) noexcept : kind_(Kind::Double), dbl_(v) {}
  explicit Value(std::string s) : kind_(Kind::String), str_(std::move(s)) {}
  explicit Value(const char* s) : kind_(Kind::String), str_(s ? s : "") {}
  explicit Value(ArrayT a) : kind_(Kind::Array), arr_(std::move(a)) {}
  explicit Value(ObjectT o) : kind_(Kind::Object), obj_(std::move(o)) {}

  Kind kind() const noexcept { return kind_; }
  bool isNull() const noexcept { return kind_ == Kind::Null; }
  bool isBool() const noexcept { return kind_ == Kind::Bool; }
  bool isInt() const noexcept { return kind_ == Kind::Int; }
  bool isDouble() const noexcept { return kind_ == Kind::Double; }
  bool isNumber() const noexcept {
    return kind_ == Kind::Int || kind_ == Kind::Double;
  }
  bool isString() const noexcept { return kind_ == Kind::String; }
  bool isArray() const noexcept { return kind_ == Kind::Array; }
  bool isObject() const noexcept { return kind_ == Kind::Object; }

  bool asBool() const;
  std::int64_t asInt() const;
  double asDouble() const;
  const std::string& asString() const;
  const ArrayT& asArray() const;
  ArrayT& asArray();
  const ObjectT& asObject() const;
  ObjectT& asObject();

  // Object helpers. find() returns nullptr if absent or this is not an object.
  const Value* find(std::string_view key) const noexcept;
  Value* find(std::string_view key) noexcept;
  bool contains(std::string_view key) const noexcept {
    return find(key) != nullptr;
  }

  bool operator==(const Value& other) const noexcept;
  bool operator!=(const Value& other) const noexcept { return !(*this == other); }

private:
  Kind kind_ = Kind::Null;
  bool bool_ = false;
  std::int64_t int_ = 0;
  double dbl_ = 0.0;
  std::string str_;
  ArrayT arr_;
  ObjectT obj_;
};

// Throws ParseError on malformed input. Strict: rejects trailing garbage,
// duplicate keys, unterminated strings, invalid escapes, bare control chars,
// NaN / Infinity, leading zeros, and trailing commas.
Value parse(std::string_view text);

// Compact serialization with no whitespace. Object key order is preserved
// from insertion / parse order so encode(decode(x)) is stable.
std::string serialize(const Value& v);

} // namespace pokebrave::battle::json
