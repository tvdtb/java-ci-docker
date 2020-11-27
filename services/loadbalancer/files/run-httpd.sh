#!/bin/bash

# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/httpd/* /tmp/httpd*

# Start port forwarding to gitlab using Port 10022
socat tcp-listen:10022,reuseaddr,fork tcp:gitlab:22 &

# Start apache HTTPD
exec /usr/sbin/apachectl -DFOREGROUND
