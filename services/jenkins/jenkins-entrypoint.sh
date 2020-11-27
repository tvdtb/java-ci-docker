#!/bin/sh

#original entrypoint
set -- /sbin/tini -- /usr/local/bin/jenkins.sh "$@"

SOCK_GID=`ls -ng /var/run/docker.sock | cut -f3 -d' '`
DOCKER_GID=`getent group docker | cut -f3 -d: || true`

if [ ! -z "$SOCK_GID" -a "$SOCK_GID" != "$DOCKER_GID" ]; then
  sudo groupmod -g ${SOCK_GID} -o docker
  echo "MODIFIED DOCKER and JENKINS GROUP assignment - restart required!"
else
  echo "jenkins and docker are ok!"
fi

exec "$@"
