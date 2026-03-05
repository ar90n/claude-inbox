#!/bin/bash
# Entrypoint: remap claude-inbox user to DOCKER_UID:DOCKER_GID, then exec as that user.
# This allows pre-built images to work with any host UID/GID.
set -e

TARGET_UID="${DOCKER_UID:-1000}"
TARGET_GID="${DOCKER_GID:-1000}"
CURRENT_UID=$(id -u claude-inbox)
CURRENT_GID=$(id -g claude-inbox)

if [ "$CURRENT_UID" != "$TARGET_UID" ] || [ "$CURRENT_GID" != "$TARGET_GID" ]; then
    sed -i "s/claude-inbox:x:${CURRENT_UID}:${CURRENT_GID}:/claude-inbox:x:${TARGET_UID}:${TARGET_GID}:/" /etc/passwd
    sed -i "s/\(claude-inbox:x:\)${CURRENT_GID}:/\1${TARGET_GID}:/" /etc/group
    chown -R "$TARGET_UID:$TARGET_GID" /home/claude-inbox /workdir
fi

exec gosu claude-inbox "$@"
