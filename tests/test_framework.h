#pragma once

#include <cstdio>
#include <cstdlib>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace pokebrave::test {

struct Case {
  std::string suite;
  std::string name;
  std::function<void()> fn;
};

inline std::vector<Case>& registry() {
  static std::vector<Case> r;
  return r;
}

struct Registrar {
  Registrar(std::string suite, std::string name, std::function<void()> fn) {
    registry().push_back({std::move(suite), std::move(name), std::move(fn)});
  }
};

class AssertionFailure {
public:
  AssertionFailure(std::string msg) : msg_(std::move(msg)) {}
  const std::string& what() const noexcept { return msg_; }

private:
  std::string msg_;
};

[[noreturn]] inline void failAssertion(const std::string& expr,
                                       const char* file, int line,
                                       const std::string& detail = "") {
  std::string msg = std::string(file) + ":" + std::to_string(line) +
                    ": assertion failed: " + expr;
  if (!detail.empty()) {
    msg += "\n  detail: " + detail;
  }
  throw AssertionFailure(msg);
}

inline int run(int argc, char** argv) {
  std::string filter;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a.rfind("--filter=", 0) == 0) filter = a.substr(9);
  }
  int passed = 0;
  int failed = 0;
  std::vector<std::string> failures;
  for (auto& c : registry()) {
    std::string full = c.suite + "." + c.name;
    if (!filter.empty() && full.find(filter) == std::string::npos) continue;
    std::printf("[ RUN      ] %s\n", full.c_str());
    try {
      c.fn();
      ++passed;
      std::printf("[       OK ] %s\n", full.c_str());
    } catch (const AssertionFailure& f) {
      ++failed;
      std::printf("[  FAILED  ] %s\n%s\n", full.c_str(), f.what().c_str());
      failures.push_back(full);
    } catch (const std::exception& e) {
      ++failed;
      std::printf("[  FAILED  ] %s\n  uncaught std::exception: %s\n",
                  full.c_str(), e.what());
      failures.push_back(full);
    } catch (...) {
      ++failed;
      std::printf("[  FAILED  ] %s\n  uncaught unknown exception\n",
                  full.c_str());
      failures.push_back(full);
    }
  }
  std::printf("\n=== Results: %d passed, %d failed ===\n", passed, failed);
  for (const auto& f : failures) std::printf("  FAILED: %s\n", f.c_str());
  return failed == 0 ? 0 : 1;
}

} // namespace pokebrave::test

#define POKEBRAVE_CONCAT_INNER(a, b) a##b
#define POKEBRAVE_CONCAT(a, b) POKEBRAVE_CONCAT_INNER(a, b)

#define TEST(SUITE, NAME)                                                  \
  static void POKEBRAVE_CONCAT(SUITE##_##NAME##_, __LINE__)();             \
  static ::pokebrave::test::Registrar POKEBRAVE_CONCAT(                    \
      SUITE##_##NAME##_reg_, __LINE__)(                                    \
      #SUITE, #NAME, POKEBRAVE_CONCAT(SUITE##_##NAME##_, __LINE__));       \
  static void POKEBRAVE_CONCAT(SUITE##_##NAME##_, __LINE__)()

#define EXPECT_TRUE(expr)                                                  \
  do {                                                                     \
    if (!(expr))                                                           \
      ::pokebrave::test::failAssertion(#expr, __FILE__, __LINE__);         \
  } while (0)

#define EXPECT_FALSE(expr) EXPECT_TRUE(!(expr))

#define EXPECT_EQ(a, b)                                                    \
  do {                                                                     \
    auto&& _av = (a);                                                      \
    auto&& _bv = (b);                                                      \
    if (!(_av == _bv))                                                     \
      ::pokebrave::test::failAssertion(#a " == " #b, __FILE__, __LINE__);  \
  } while (0)

#define EXPECT_NE(a, b)                                                    \
  do {                                                                     \
    auto&& _av = (a);                                                      \
    auto&& _bv = (b);                                                      \
    if (!(_av != _bv))                                                     \
      ::pokebrave::test::failAssertion(#a " != " #b, __FILE__, __LINE__);  \
  } while (0)

#define EXPECT_STREQ(a, b)                                                 \
  do {                                                                     \
    std::string _as = (a);                                                 \
    std::string _bs = (b);                                                 \
    if (_as != _bs)                                                        \
      ::pokebrave::test::failAssertion(                                    \
          #a " == " #b, __FILE__, __LINE__,                                \
          "got=\"" + _as + "\" expected=\"" + _bs + "\"");                 \
  } while (0)
