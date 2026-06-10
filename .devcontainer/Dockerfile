# Flutter + Android SDK + JDK, preinstalled by the cirruslabs image.
# We extend it with the Android emulator + a system image so that
# integration / GUI tests can run headless inside the container (KVM-accelerated).
FROM ghcr.io/cirruslabs/flutter:stable

# API level used for the emulator AVD and the integration-test target.
ARG ANDROID_API=34
ARG ANDROID_ABI=x86_64
ARG ANDROID_TAG=google_apis

USER root

# Native libs the headless emulator needs. libasound2 was renamed to
# libasound2t64 on newer Ubuntu (24.04+); try the new name, fall back to the old.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpulse0 libgl1 libnss3 libxcursor1 libxdamage1 libxrandr2 \
        libxcomposite1 libdbus-1-3 && \
    ( apt-get install -y --no-install-recommends libasound2t64 || \
      apt-get install -y --no-install-recommends libasound2 ) && \
    rm -rf /var/lib/apt/lists/*

# Emulator + platform-tools + a system image, then create a reusable AVD.
RUN yes | sdkmanager "emulator" "platform-tools" \
        "platforms;android-${ANDROID_API}" \
        "system-images;android-${ANDROID_API};${ANDROID_TAG};${ANDROID_ABI}" && \
    yes | sdkmanager --licenses && \
    echo "no" | avdmanager create avd \
        --force -n cycle_test \
        -k "system-images;android-${ANDROID_API};${ANDROID_TAG};${ANDROID_ABI}"

ENV PATH="${PATH}:${ANDROID_SDK_ROOT}/emulator:${ANDROID_SDK_ROOT}/platform-tools"
