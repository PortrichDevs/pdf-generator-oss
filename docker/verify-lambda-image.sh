#!/bin/sh
# Lambda イメージのビルド時検証。本番稼働イメージ (commit c4fcc6f) と同じ描画結果になる前提条件を確認する。
set -eu

fail() { echo "verify-lambda-image: $*" >&2; exit 1; }

# ブラウザとドライバのバージョン
/usr/bin/chromium-browser --version | grep -q "${CHROME_VERSION}" || fail "chrome version mismatch: $(/usr/bin/chromium-browser --version)"
chromedriver --version | grep -q "${CHROME_VERSION}" || fail "chromedriver version mismatch: $(chromedriver --version)"

# 共有ライブラリの欠落
missing=$(ldd /opt/chrome/chrome /usr/bin/chromedriver | grep "not found" || true)
[ -z "$missing" ] || fail "missing shared libraries: $missing"

# 使えるフォントが本番と同じ構成 (IPA 4 種 + DejaVu Sans) であること
expected="DejaVu Sans
IPAGothic
IPAMincho
IPAPGothic
IPAPMincho"
actual=$(fc-list -f '%{family[0]}\n' | sort -u)
[ "$actual" = "$expected" ] || fail "font families mismatch: expected [$(echo $expected)], got [$(echo $actual)]"
[ -n "$(fc-list :lang=ja)" ] || fail "no Japanese font available"

# 総称フォントの解決先 (本番と同じであること)
check_match() {
  actual=$(fc-match -f '%{family[0]}' "$1")
  [ "$actual" = "$2" ] || fail "fc-match $1: expected '$2', got '$actual'"
}
check_match sans-serif "DejaVu Sans"
check_match serif IPAMincho
check_match monospace IPAGothic

echo "verify-lambda-image: OK"
