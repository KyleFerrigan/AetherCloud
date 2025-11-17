# --- stage: pull CUDA 11.8 + cuDNN8 runtime libs (Ubuntu 22.04) ---
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS cuda

# --- final: Nextcloud 32 (Apache) base ---
FROM nextcloud:32-apache

ENV CUDA_HOME=/usr/local/cuda \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    TF_CPP_MIN_LOG_LEVEL=1

# place to stash the libs
RUN mkdir -p /usr/local/cuda/lib64

# --- copy CUDA & cuDNN shared libs from the CUDA stage ---
COPY --from=cuda /usr/local/cuda/targets/x86_64-linux/lib/libcudart.so*     /usr/local/cuda/lib64/
COPY --from=cuda /usr/local/cuda/targets/x86_64-linux/lib/libcublas*.so*    /usr/local/cuda/lib64/
COPY --from=cuda /usr/local/cuda/targets/x86_64-linux/lib/libcufft*.so*     /usr/local/cuda/lib64/
COPY --from=cuda /usr/local/cuda/targets/x86_64-linux/lib/libcurand*.so*    /usr/local/cuda/lib64/
COPY --from=cuda /usr/local/cuda/targets/x86_64-linux/lib/libcusolver*.so*  /usr/local/cuda/lib64/
COPY --from=cuda /usr/local/cuda/targets/x86_64-linux/lib/libcusparse*.so*  /usr/local/cuda/lib64/
COPY --from=cuda /usr/lib/x86_64-linux-gnu/libcudnn*.so*                    /usr/local/cuda/lib64/

# make the dynamic linker see them
RUN echo "/usr/local/cuda/lib64" > /etc/ld.so.conf.d/cuda.conf && ldconfig

# --- add ffmpeg for video previews/thumbnails ---
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*
 
# Install PHP’s Postgres driver
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev pkg-config \
 && docker-php-ext-install -j"$(nproc)" pdo_pgsql pgsql \
 && docker-php-ext-enable pdo_pgsql pgsql \
 && apt-get purge -y libpq-dev pkg-config \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

# Play nice with unraid Permissions 
ARG PUID=99
ARG PGID=100

# Make sure the group exists with PGID (100 is usually 'users' in Unraid)
# If www-data group exists, change its gid; otherwise map to PGID.
RUN set -eux; \
    if getent group www-data >/dev/null; then groupmod -o -g "${PGID}" www-data; fi; \
    if ! getent group "${PGID}" >/dev/null; then groupadd -o -g "${PGID}" users || true; fi; \
    usermod -o -u "${PUID}" -g "${PGID}" www-data

# Fix ownership only where www-data owned things already exist
# (avoids chowning the world and killing build times)
RUN set -eux; \
    old_uid=33; old_gid=33; \
    for p in /var/www /var/lib/php/sessions /var/log/apache2 /run/apache2; do \
      if [ -d "$p" ]; then \
        find "$p" -xdev -uid "$old_uid" -exec chown -h ${PUID}:${PGID} {} + || true; \
        find "$p" -xdev -gid "$old_gid" -exec chgrp -h ${PGID} {} + || true; \
      fi; \
    done