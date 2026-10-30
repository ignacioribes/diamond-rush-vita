#!/usr/bin/env bash
# Prepares the game sources from Diamond-Rush_J2ME_EN_v104-Nokia-N6101.jar:
#   1. checks the jar hash
#   2. decompiles it into ./java-src/ (Vineflower)
#   3. applies the port's changes (patches/java-src.patch)
#   4. translates java-src to C++ (port/src/game/gen)
set -euo pipefail
cd "$(dirname "$0")/.."

JAR="Diamond-Rush_J2ME_EN_v104-Nokia-N6101.jar"
EXPECTED_HASH="4871112043a1dbc57eb3560547e5a2b079a6a2f387da0e466c8039d81ed98e1f"

if [ ! -f "$JAR" ]; then
  echo "Error: $JAR not found in project root." >&2
  exit 1
fi

HASH=$(sha256sum "$JAR" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$JAR" | awk '{print $1}')
if [ "$HASH" != "$EXPECTED_HASH" ]; then
  echo "Error: $JAR SHA-256 is $HASH, expected $EXPECTED_HASH" >&2
  exit 1
fi

mkdir -p env env/freej2me

# Download Vineflower if needed
if [ ! -f env/vineflower.jar ]; then
  echo "Downloading Vineflower decompiler..."
  curl -fsSL -o env/vineflower.jar https://github.com/Vineflower/vineflower/releases/download/1.10.1/vineflower-1.10.1.jar
fi

# Download FreeJ2ME-Plus if needed (nightly release zip contains freej2me_plus.jar)
if [ ! -f env/freej2me/freej2me_plus.jar ]; then
  echo "Downloading FreeJ2ME-Plus (for classpath)..."
  FJ_URL="https://github.com/TASEmulators/freej2me-plus/releases/download/nightlies/freej2me_plus-nightly.zip"
  if curl -fsSL -o env/freej2me/freej2me_plus.zip "$FJ_URL"; then
    unzip -q -o env/freej2me/freej2me_plus.zip -d env/freej2me/
    rm -f env/freej2me/freej2me_plus.zip
  else
    # Fallback via GitHub API
    API_URL=$(curl -s https://api.github.com/repos/TASEmulators/freej2me-plus/releases | grep "browser_download_url.*freej2me.*\.zip" | head -1 | cut -d '"' -f 4)
    curl -fsSL -o env/freej2me/freej2me_plus.zip "$API_URL"
    unzip -q -o env/freej2me/freej2me_plus.zip -d env/freej2me/
    rm -f env/freej2me/freej2me_plus.zip
  fi

  # If extracted jar has another name or is in a subfolder, normalize it:
  if [ ! -f env/freej2me/freej2me_plus.jar ]; then
    FOUND_JAR=$(find env/freej2me -type f -name "*freej2me*.jar" | head -1)
    if [ -n "$FOUND_JAR" ]; then
      cp "$FOUND_JAR" env/freej2me/freej2me_plus.jar
    fi
  fi
fi

if [ ! -f env/freej2me/freej2me_plus.jar ]; then
  echo "Error: Failed to obtain env/freej2me/freej2me_plus.jar" >&2
  exit 1
fi

# [1/3] Decompile
if [ ! -d java-src ]; then
  echo "[1/3] Decompiling $JAR..."
  mkdir -p java-src
  java -jar env/vineflower.jar -dgs=1 -rsy=1 -lit=1 -ren=1 -ind="    " "$JAR" java-src/
  if [ -f "java-src/$JAR" ]; then
    unzip -q -o "java-src/$JAR" -d java-src/
    rm -f "java-src/$JAR"
  fi

  echo "[2/3] Applying port patch (including overlays)..."
  (
    cd java-src
    git apply --whitespace=nowarn ../patches/java-src.patch
  )
else
  echo "java-src/ already exists, skipping decompile and patch."
fi

# [3/3] Translate to C++
echo "[3/3] Translating Java to C++ (port/src/game/gen)..."
mkdir -p port/src/game/gen
SRCS=(java-src/*.java)
java \
  --add-exports jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \
  --add-exports jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED \
  --add-exports jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
  --add-exports jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED \
  tools/j2cpp/J2Cpp.java \
  port/src/game/gen \
  env/freej2me/freej2me_plus.jar \
  GloftDIRU \
  "${SRCS[@]}"

echo "Sources successfully generated in port/src/game/gen."
