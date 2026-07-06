FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive

RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
       bzip2 \
       curl \
       git \
       git-lfs \
       jq \
       yq \
       libgl1 \
       libglib2.0-0 \
       make \
       default-jre-headless \
       patch \
       python3 \
       python3-pip \
       python3-virtualenv \
       unzip \
       xz-utils \
       libdbus-1-3

COPY silabs-firmware-builder/requirements.txt /tmp/

RUN \
    virtualenv /opt/venv \
    && /opt/venv/bin/pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Install Simplicity Commander (unfortunately no stable URL available, this
# is known to be working with Commander_linux_x86_64_1v15p0b1306.tar.bz).
RUN \
    curl -O https://www.silabs.com/documents/login/software/SimplicityCommander-Linux.zip \
    && unzip -q SimplicityCommander-Linux.zip \
    && tar -C /opt -xjf SimplicityCommander-Linux/Commander_linux_x86_64_*.tar.bz \
    && rm -r SimplicityCommander-Linux \
    && rm SimplicityCommander-Linux.zip

ENV PATH="$PATH:/opt/commander"

# Install Silicon Labs Configurator (slc)
RUN \
    curl -O https://www.silabs.com/documents/login/software/slc_cli_linux.zip \
    && unzip -q -d /opt slc_cli_linux.zip \
    && rm slc_cli_linux.zip

ENV PATH="$PATH:/opt/slc_cli"

# GCC Embedded Toolchain 12.2.rel1 (for Gecko SDK 4.4.0+)
RUN \
    curl -O https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/12.2.rel1/binrel/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-eabi.tar.xz \
    && tar -C /opt -xf arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-eabi.tar.xz \
    && rm arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-eabi.tar.xz

# Simplicity SDK 2024.6.2
RUN \
    curl -o simplicity_sdk_2024.6.2.zip -L https://github.com/SiliconLabs/simplicity_sdk/releases/download/v2024.6.2/gecko-sdk.zip \
    && unzip -q -d simplicity_sdk_2024.6.2 simplicity_sdk_2024.6.2.zip \
    && rm simplicity_sdk_2024.6.2.zip

# Gecko SDK 4.4.6
RUN \
    curl -o gecko_sdk_4.4.6.zip -L https://github.com/SiliconLabs/gecko_sdk/releases/download/v4.4.6/gecko-sdk.zip \
    && unzip -q -d gecko_sdk_4.4.6 gecko_sdk_4.4.6.zip \
    && rm gecko_sdk_4.4.6.zip

# ZCL Advanced Platform (ZAP) v2024.09.27
RUN \
    curl -o zap_2024.09.27.zip -L https://github.com/project-chip/zap/releases/download/v2024.09.27/zap-linux-x64.zip \
    && unzip -q -d /opt/zap zap_2024.09.27.zip \
    && rm zap_2024.09.27.zip

ENV STUDIO_ADAPTER_PACK_PATH="/opt/zap"

# Fix this SDK bug...
RUN sed -i 's/#include "sl_led.h"/#include "sl_simple_led_instances.h"/' /gecko_sdk_*/platform/service/legacy_hal/src/base-replacement.c && \
    sed -i 's/SL_CATALOG_LED_PRESENT/SL_CATALOG_SIMPLE_LED_PRESENT/' /gecko_sdk_*/platform/service/legacy_hal/src/base-replacement.c

ARG USERNAME=builder
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

RUN mkdir -p /.git/modules
COPY ../.git/modules/silabs-firmware-builder /.git/modules/silabs-firmware-builder
COPY silabs-firmware-builder /firmware

RUN for sdk in /*_sdk_*; do \
  su $USERNAME -- $(which slc) signature trust --sdk "$sdk" && \
  ln -s /firmware/gecko_sdk_extensions "$sdk"/extension && \
  for ext in "$sdk"/extension/*/; do \
    su $USERNAME -- $(which slc) signature trust --sdk "$sdk" --extension-path "$ext"; \
  done; \
  done

RUN ln -s /firmware /silabs-firmware-builder

USER $USERNAME
WORKDIR /build

RUN git config --global --add safe.directory "/firmware"

RUN /opt/venv/bin/python3 /firmware/tools/build_project.py \
    --keep-slc-daemon \
    --sdk /gecko_sdk* \
    --toolchain /opt/*arm-none-eabi* \
    --manifest "/firmware/manifests/nabucasa/bryx_bootloader.yaml" \
    --build-dir /build/build \
    --build-system makefile \
    --output-dir /build/outputs \
    --output gbl \
    --output hex \
    --output s37 \
    --no-clean-build-dir \
    --output out && \
  /opt/venv/bin/python3 /firmware/tools/build_project.py \
    --sdk /gecko_sdk* \
    --toolchain /opt/*arm-none-eabi* \
    --manifest "/firmware/manifests/nabucasa/bryx_zigbee_ncp.yaml" \
    --build-dir /build/build_ncp \
    --build-system makefile \
    --output-dir /build/outputs \
    --output gbl \
    --output hex \
    --output out \
    --no-clean-build-dir
