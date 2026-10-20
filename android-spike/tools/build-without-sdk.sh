#!/usr/bin/env bash
# 在沒有 Android SDK、連不上 dl.google.com 的環境組出可安裝的 debug APK。
# 需要：java 17+、gradle 8.9+、node 18+、python3、openssl。
# 工具來源（全部不經 dl.google.com）：
#   android.jar  : https://raw.githubusercontent.com/Sable/android-platforms/master/android-35/android.jar
#   r8lib.jar(d8): https://storage.googleapis.com/r8-releases/raw/8.7.18/r8lib.jar
#   aapt2        : npm 套件 aaptjs3 2.0.2 內附的 Linux x64 aapt2（2.20），PyPI 的 aapt2 0.2.1 是 2.19，讀不了 API 35 的 resources.arsc
#   簽章         : npm 套件 apk_sign_ts 1.0.1（v1+v2+v3，含 zipalign）
# 用法：WORK=/path/to/workdir tools/build-without-sdk.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HERE/build-nosdk}"
mkdir -p "$WORK"/{dl,res,out}
cd "$WORK"

ANDROID_JAR="$WORK/dl/android-35.jar"
R8="$WORK/dl/r8lib.jar"
AAPT2="$WORK/dl/aapt2/package/bin/x64/linux/aapt2"

[ -f "$ANDROID_JAR" ] || curl -sSL -o "$ANDROID_JAR" https://raw.githubusercontent.com/Sable/android-platforms/master/android-35/android.jar
[ -f "$R8" ] || curl -sSL -o "$R8" https://storage.googleapis.com/r8-releases/raw/8.7.18/r8lib.jar
if [ ! -x "$AAPT2" ]; then
  curl -sSL -o dl/aaptjs3.tgz https://registry.npmjs.org/aaptjs3/-/aaptjs3-2.0.2.tgz
  mkdir -p dl/aapt2 && tar -xzf dl/aaptjs3.tgz -C dl/aapt2
  chmod +x "$AAPT2"
fi
if [ ! -d dl/sign/node_modules/apk_sign_ts ]; then
  mkdir -p dl/sign && (cd dl/sign && npm init -y >/dev/null && npm install apk_sign_ts@1.0.1 --no-audit --no-fund >/dev/null)
fi

# 1. Kotlin → class：用一個純 JVM 的 Gradle 專案，把 android.jar 當 compileOnly。
mkdir -p kbuild && cat > kbuild/settings.gradle.kts <<'K'
pluginManagement { repositories { gradlePluginPortal(); mavenCentral() } }
rootProject.name = "spike-kcompile"
K
cat > kbuild/build.gradle.kts <<K
plugins { kotlin("jvm") version "2.0.21" }
repositories { mavenCentral() }
kotlin { sourceSets["main"].kotlin.srcDir("$HERE/app/src/main/java") }
dependencies {
    compileOnly(files("$ANDROID_JAR"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
tasks.register<Copy>("copyRuntime") { from(configurations.runtimeClasspath); into(layout.buildDirectory.dir("runtime-jars")) }
K
(cd kbuild && gradle --no-daemon -q compileKotlin copyRuntime)
echo "[1/5] Kotlin 編譯完成"

# 2. 資源與 manifest：aapt2 需要 manifest 有 package 屬性，AGP 平常會自己補。
sed 's|<manifest xmlns:android="http://schemas.android.com/apk/res/android">|<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.readtrans.spike">|' \
  "$HERE/app/src/main/AndroidManifest.xml" > out/AndroidManifest.xml
rm -f out/res.zip
"$AAPT2" compile --dir "$HERE/app/src/main/res" -o out/res.zip
"$AAPT2" link -o out/base.apk -I "$ANDROID_JAR" --manifest out/AndroidManifest.xml \
  --min-sdk-version 26 --target-sdk-version 35 --version-code 1 --version-name 0.1 out/res.zip
echo "[2/5] aapt2 link 完成"

# 3. dex
rm -rf out/dex && mkdir -p out/dex
# d8 只收 .class、.jar、.zip，不收目錄，先把 class 目錄打成 jar。
python3 -I - kbuild/build/classes/kotlin/main out/app-classes.jar <<'PY'
import sys, os, zipfile
src, dst = sys.argv[1:3]
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            if f.endswith('.class'):
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, src))
PY
java -cp "$R8" com.android.tools.r8.D8 --release --min-api 26 --lib "$ANDROID_JAR" --output out/dex \
  out/app-classes.jar kbuild/build/runtime-jars/*.jar
echo "[3/5] d8 完成：$(ls out/dex)"

# 4. 把 classes.dex 塞進 APK
python3 -I - "$WORK/out/base.apk" "$WORK/out/dex/classes.dex" "$WORK/out/unsigned.apk" <<'PY'
import sys, zipfile, shutil
base, dex, outp = sys.argv[1:4]
shutil.copy(base, outp)
with zipfile.ZipFile(outp, 'a', compression=zipfile.ZIP_DEFLATED) as z:
    z.write(dex, 'classes.dex')
PY
echo "[4/5] 已加入 classes.dex"

# 5. 簽章（debug 用自簽金鑰，第一次產生）
if [ ! -f dl/sign/debug.key.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout dl/sign/debug.key.pem -out dl/sign/debug.cert.pem \
    -days 10000 -subj "/CN=ReadTrans Spike Debug" >/dev/null 2>&1
fi
cat > dl/sign/sign.mjs <<'JS'
import { readFileSync, writeFileSync } from 'node:fs';
import { ApkSigner, SigningKey } from 'apk_sign_ts';
const [,, inApk, outApk, keyPem, certPem] = process.argv;
const signer = new ApkSigner({ signingKey: SigningKey.fromPEM(readFileSync(keyPem,'utf8'), readFileSync(certPem,'utf8')) });
const { signedApk } = await signer.sign(new Uint8Array(readFileSync(inApk)));
writeFileSync(outApk, signedApk);
JS
(cd dl/sign && node sign.mjs "$WORK/out/unsigned.apk" "$WORK/out/readtrans-spike-debug.apk" debug.key.pem debug.cert.pem)
echo "[5/5] 簽章完成 → $WORK/out/readtrans-spike-debug.apk"
"$AAPT2" dump badging out/readtrans-spike-debug.apk | head -8
