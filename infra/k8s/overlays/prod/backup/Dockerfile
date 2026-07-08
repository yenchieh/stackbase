# stackbase backup toolchain: pg16 client (matches the server major) + MinIO
# client + bash/curl. The backup script is mounted from a ConfigMap at runtime
# (configMapGenerator in overlays/prod), so this image rarely changes.
#
# mc is pinned + sha256-verified. To bump: re-fetch the checksum from
#   https://dl.min.io/client/mc/release/linux-amd64/mc.sha256sum
# (version + sha carried over from a verified diagramzu/manyi pin).
FROM postgres:16-alpine
ARG MC_VERSION=RELEASE.2025-08-13T08-35-41Z
ARG MC_SHA256=01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891
RUN apk add --no-cache bash curl ca-certificates \
 && curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}" -o /usr/local/bin/mc \
 && echo "${MC_SHA256}  /usr/local/bin/mc" | sha256sum -c - \
 && chmod +x /usr/local/bin/mc
# backup_script.sh is mounted from the ConfigMap; entrypoint points at that mount.
ENTRYPOINT ["/bin/bash", "/scripts/backup_script.sh"]
