#include "battle/BattleJson.h"

#include <cmath>
#include <cstdio>
#include <limits>
#include <sstream>

namespace pokebrave::battle::json {

namespace {

[[noreturn]] void throwTypeError(const char* expected, Value::Kind got) {
  static const char* names[] = {"null",  "bool",  "int",   "double",
                                "string", "array", "object"};
  std::string msg = "BattleJson::TypeError: expected ";
  msg += expected;
  msg += ", got ";
  msg += names[static_cast<std::size_t>(got)];
  throw TypeError(msg);
}

class Parser {
public:
  explicit Parser(std::string_view s) : s_(s) {}

  Value parseDocument() {
    skipWs();
    Value v = parseValue();
    skipWs();
    if (pos_ != s_.size()) {
      fail("trailing garbage after JSON document");
    }
    return v;
  }

private:
  [[noreturn]] void fail(const std::string& msg) {
    throw ParseError("BattleJson::ParseError at " + std::to_string(pos_) +
                         ": " + msg,
                     pos_);
  }

  char peek() {
    if (pos_ >= s_.size()) fail("unexpected end of input");
    return s_[pos_];
  }

  char next() {
    if (pos_ >= s_.size()) fail("unexpected end of input");
    return s_[pos_++];
  }

  bool eof() const { return pos_ >= s_.size(); }

  void expect(char c) {
    if (eof() || s_[pos_] != c) {
      fail(std::string("expected '") + c + "'");
    }
    ++pos_;
  }

  void skipWs() {
    while (pos_ < s_.size()) {
      char c = s_[pos_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++pos_;
      } else {
        break;
      }
    }
  }

  Value parseValue() {
    skipWs();
    if (eof()) fail("expected JSON value");
    char c = s_[pos_];
    if (c == '{') return parseObject();
    if (c == '[') return parseArray();
    if (c == '"') return Value(parseString());
    if (c == 't' || c == 'f') return parseBool();
    if (c == 'n') return parseNull();
    if (c == '-' || (c >= '0' && c <= '9')) return parseNumber();
    fail(std::string("unexpected character '") + c + "'");
  }

  Value parseObject() {
    expect('{');
    skipWs();
    ObjectT o;
    if (!eof() && s_[pos_] == '}') {
      ++pos_;
      return Value(std::move(o));
    }
    while (true) {
      skipWs();
      if (eof() || s_[pos_] != '"') fail("expected '\"' to start key");
      std::string key = parseString();
      skipWs();
      expect(':');
      Value v = parseValue();
      for (const auto& kv : o) {
        if (kv.first == key) fail("duplicate key '" + key + "' in object");
      }
      o.emplace_back(std::move(key), std::move(v));
      skipWs();
      if (eof()) fail("unterminated object");
      char ch = s_[pos_];
      if (ch == ',') {
        ++pos_;
        skipWs();
        if (!eof() && s_[pos_] == '}') fail("trailing comma in object");
        continue;
      }
      if (ch == '}') {
        ++pos_;
        return Value(std::move(o));
      }
      fail("expected ',' or '}' in object");
    }
  }

  Value parseArray() {
    expect('[');
    skipWs();
    ArrayT a;
    if (!eof() && s_[pos_] == ']') {
      ++pos_;
      return Value(std::move(a));
    }
    while (true) {
      Value v = parseValue();
      a.emplace_back(std::move(v));
      skipWs();
      if (eof()) fail("unterminated array");
      char ch = s_[pos_];
      if (ch == ',') {
        ++pos_;
        skipWs();
        if (!eof() && s_[pos_] == ']') fail("trailing comma in array");
        continue;
      }
      if (ch == ']') {
        ++pos_;
        return Value(std::move(a));
      }
      fail("expected ',' or ']' in array");
    }
  }

  std::string parseString() {
    expect('"');
    std::string out;
    while (true) {
      if (eof()) fail("unterminated string");
      unsigned char ch = static_cast<unsigned char>(s_[pos_++]);
      if (ch == '"') return out;
      if (ch == '\\') {
        if (eof()) fail("unterminated escape sequence");
        char esc = s_[pos_++];
        switch (esc) {
          case '"': out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/': out.push_back('/'); break;
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'n': out.push_back('\n'); break;
          case 'r': out.push_back('\r'); break;
          case 't': out.push_back('\t'); break;
          case 'u': {
            if (pos_ + 4 > s_.size()) fail("incomplete \\u escape");
            unsigned cp = 0;
            for (int i = 0; i < 4; ++i) {
              char h = s_[pos_++];
              unsigned d;
              if (h >= '0' && h <= '9') d = static_cast<unsigned>(h - '0');
              else if (h >= 'a' && h <= 'f') d = static_cast<unsigned>(h - 'a' + 10);
              else if (h >= 'A' && h <= 'F') d = static_cast<unsigned>(h - 'A' + 10);
              else fail("invalid hex digit in \\u escape");
              cp = (cp << 4) | d;
            }
            // Surrogate pairs
            if (cp >= 0xD800 && cp <= 0xDBFF) {
              if (pos_ + 6 > s_.size() || s_[pos_] != '\\' ||
                  s_[pos_ + 1] != 'u') {
                fail("expected low surrogate after high surrogate");
              }
              pos_ += 2;
              unsigned lo = 0;
              for (int i = 0; i < 4; ++i) {
                char h = s_[pos_++];
                unsigned d;
                if (h >= '0' && h <= '9') d = static_cast<unsigned>(h - '0');
                else if (h >= 'a' && h <= 'f') d = static_cast<unsigned>(h - 'a' + 10);
                else if (h >= 'A' && h <= 'F') d = static_cast<unsigned>(h - 'A' + 10);
                else fail("invalid hex digit in \\u low surrogate");
                lo = (lo << 4) | d;
              }
              if (lo < 0xDC00 || lo > 0xDFFF) fail("invalid low surrogate");
              cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
            } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
              fail("unexpected low surrogate without high surrogate");
            }
            appendUtf8(out, cp);
            break;
          }
          default:
            fail(std::string("invalid escape '\\") + esc + "'");
        }
      } else if (ch < 0x20) {
        fail("unescaped control character in string");
      } else {
        out.push_back(static_cast<char>(ch));
      }
    }
  }

  static void appendUtf8(std::string& out, unsigned cp) {
    if (cp <= 0x7F) {
      out.push_back(static_cast<char>(cp));
    } else if (cp <= 0x7FF) {
      out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0xFFFF) {
      out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
      out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
  }

  Value parseBool() {
    if (s_.compare(pos_, 4, "true") == 0) {
      pos_ += 4;
      return Value(true);
    }
    if (s_.compare(pos_, 5, "false") == 0) {
      pos_ += 5;
      return Value(false);
    }
    fail("invalid literal (expected true/false)");
  }

  Value parseNull() {
    if (s_.compare(pos_, 4, "null") == 0) {
      pos_ += 4;
      return Value();
    }
    fail("invalid literal (expected null)");
  }

  Value parseNumber() {
    std::size_t start = pos_;
    bool isFloat = false;
    if (s_[pos_] == '-') ++pos_;
    if (eof()) fail("incomplete number");
    if (s_[pos_] == '0') {
      ++pos_;
      if (!eof() && s_[pos_] >= '0' && s_[pos_] <= '9') {
        fail("leading zero in number");
      }
    } else if (s_[pos_] >= '1' && s_[pos_] <= '9') {
      while (!eof() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
    } else {
      fail("expected digit in number");
    }
    if (!eof() && s_[pos_] == '.') {
      isFloat = true;
      ++pos_;
      if (eof() || s_[pos_] < '0' || s_[pos_] > '9') {
        fail("expected digit after decimal point");
      }
      while (!eof() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
    }
    if (!eof() && (s_[pos_] == 'e' || s_[pos_] == 'E')) {
      isFloat = true;
      ++pos_;
      if (!eof() && (s_[pos_] == '+' || s_[pos_] == '-')) ++pos_;
      if (eof() || s_[pos_] < '0' || s_[pos_] > '9') {
        fail("expected digit in exponent");
      }
      while (!eof() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
    }
    std::string lit(s_.substr(start, pos_ - start));
    if (isFloat) {
      char* end = nullptr;
      double d = std::strtod(lit.c_str(), &end);
      if (end != lit.c_str() + lit.size()) fail("malformed double");
      if (std::isnan(d) || std::isinf(d)) fail("non-finite number");
      return Value(d);
    }
    // Integer parse with overflow check.
    errno = 0;
    char* end = nullptr;
    long long ll = std::strtoll(lit.c_str(), &end, 10);
    if (end != lit.c_str() + lit.size()) fail("malformed integer");
    if (errno == ERANGE) fail("integer out of range");
    return Value(static_cast<std::int64_t>(ll));
  }

  std::string_view s_;
  std::size_t pos_ = 0;
};

void serializeString(const std::string& s, std::string& out) {
  out.push_back('"');
  for (auto rawch : s) { unsigned char ch = static_cast<unsigned char>(rawch);
    switch (ch) {
      case '"': out.append("\\\""); break;
      case '\\': out.append("\\\\"); break;
      case '\b': out.append("\\b"); break;
      case '\f': out.append("\\f"); break;
      case '\n': out.append("\\n"); break;
      case '\r': out.append("\\r"); break;
      case '\t': out.append("\\t"); break;
      default:
        if (ch < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", ch);
          out.append(buf);
        } else {
          out.push_back(static_cast<char>(ch));
        }
    }
  }
  out.push_back('"');
}

void serializeImpl(const Value& v, std::string& out) {
  switch (v.kind()) {
    case Value::Kind::Null:
      out.append("null");
      return;
    case Value::Kind::Bool:
      out.append(v.asBool() ? "true" : "false");
      return;
    case Value::Kind::Int:
      out.append(std::to_string(v.asInt()));
      return;
    case Value::Kind::Double: {
      double d = v.asDouble();
      char buf[64];
      // %.17g preserves round-trip for IEEE-754 doubles. Strip trailing
      // ".0" / fractional zeros for tidier output where possible.
      std::snprintf(buf, sizeof(buf), "%.17g", d);
      std::string s(buf);
      // Ensure floats round-trip as floats — JSON makes no distinction, but
      // we keep a decimal point so re-parse comes back as Double.
      if (s.find('.') == std::string::npos &&
          s.find('e') == std::string::npos &&
          s.find('E') == std::string::npos &&
          s.find('n') == std::string::npos) {
        s.append(".0");
      }
      out.append(s);
      return;
    }
    case Value::Kind::String:
      serializeString(v.asString(), out);
      return;
    case Value::Kind::Array: {
      out.push_back('[');
      bool first = true;
      for (const auto& item : v.asArray()) {
        if (!first) out.push_back(',');
        first = false;
        serializeImpl(item, out);
      }
      out.push_back(']');
      return;
    }
    case Value::Kind::Object: {
      out.push_back('{');
      bool first = true;
      for (const auto& kv : v.asObject()) {
        if (!first) out.push_back(',');
        first = false;
        serializeString(kv.first, out);
        out.push_back(':');
        serializeImpl(kv.second, out);
      }
      out.push_back('}');
      return;
    }
  }
}

} // namespace

bool Value::asBool() const {
  if (kind_ != Kind::Bool) throwTypeError("bool", kind_);
  return bool_;
}

std::int64_t Value::asInt() const {
  if (kind_ == Kind::Int) return int_;
  if (kind_ == Kind::Double) {
    double d = dbl_;
    if (std::isnan(d) || std::isinf(d)) {
      throw TypeError("BattleJson::TypeError: non-finite double as int");
    }
    if (d < static_cast<double>(std::numeric_limits<std::int64_t>::min()) ||
        d > static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
      throw TypeError("BattleJson::TypeError: double out of int64 range");
    }
    return static_cast<std::int64_t>(d);
  }
  throwTypeError("int", kind_);
}

double Value::asDouble() const {
  if (kind_ == Kind::Double) return dbl_;
  if (kind_ == Kind::Int) return static_cast<double>(int_);
  throwTypeError("double", kind_);
}

const std::string& Value::asString() const {
  if (kind_ != Kind::String) throwTypeError("string", kind_);
  return str_;
}

const ArrayT& Value::asArray() const {
  if (kind_ != Kind::Array) throwTypeError("array", kind_);
  return arr_;
}

ArrayT& Value::asArray() {
  if (kind_ != Kind::Array) throwTypeError("array", kind_);
  return arr_;
}

const ObjectT& Value::asObject() const {
  if (kind_ != Kind::Object) throwTypeError("object", kind_);
  return obj_;
}

ObjectT& Value::asObject() {
  if (kind_ != Kind::Object) throwTypeError("object", kind_);
  return obj_;
}

const Value* Value::find(std::string_view key) const noexcept {
  if (kind_ != Kind::Object) return nullptr;
  for (const auto& kv : obj_) {
    if (kv.first == key) return &kv.second;
  }
  return nullptr;
}

Value* Value::find(std::string_view key) noexcept {
  if (kind_ != Kind::Object) return nullptr;
  for (auto& kv : obj_) {
    if (kv.first == key) return &kv.second;
  }
  return nullptr;
}

bool Value::operator==(const Value& other) const noexcept {
  if (kind_ != other.kind_) {
    // Treat numeric kinds as comparable when numerically equal.
    if ((kind_ == Kind::Int && other.kind_ == Kind::Double) ||
        (kind_ == Kind::Double && other.kind_ == Kind::Int)) {
      return asDouble() == other.asDouble();
    }
    return false;
  }
  switch (kind_) {
    case Kind::Null: return true;
    case Kind::Bool: return bool_ == other.bool_;
    case Kind::Int: return int_ == other.int_;
    case Kind::Double: return dbl_ == other.dbl_;
    case Kind::String: return str_ == other.str_;
    case Kind::Array: {
      if (arr_.size() != other.arr_.size()) return false;
      for (std::size_t i = 0; i < arr_.size(); ++i) {
        if (!(arr_[i] == other.arr_[i])) return false;
      }
      return true;
    }
    case Kind::Object: {
      // Order-insensitive equality for objects.
      if (obj_.size() != other.obj_.size()) return false;
      for (const auto& kv : obj_) {
        const Value* o = other.find(kv.first);
        if (!o || !(*o == kv.second)) return false;
      }
      return true;
    }
  }
  return false;
}

Value parse(std::string_view text) {
  Parser p(text);
  return p.parseDocument();
}

std::string serialize(const Value& v) {
  std::string out;
  serializeImpl(v, out);
  return out;
}

} // namespace pokebrave::battle::json
