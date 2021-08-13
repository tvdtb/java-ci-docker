FROM jenkins/jenkins:2.304-slim@sha256:ad9c3c14195d7cb01929c4c685aa3a355adb88ac55534f8b1ebad1122b31a722

USER root

RUN apt-get update                                                                                           && \
    apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common            && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -                                  && \
    apt-key fingerprint 0EBFCD88                                                                             && \
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" && \
    apt-get update                                                                                           && \
	apt-get install -y docker-ce                                                                             && \
	apt-get clean                                                                                            && \
	usermod -a --groups docker jenkins                                                                       && \
    echo docker installed!

COPY jenkins-entrypoint.sh /jenkins-entrypoint.sh
RUN  chown jenkins /jenkins-entrypoint.sh  && \
     chmod +x /jenkins-entrypoint.sh

# Erlaube SUDO für jenkins
RUN apt-get update                                                                                           && \
	apt-get install -y sudo                                                                                  && \
	apt-get clean && rm -rf /var/cache/apt                                                                   && \
    echo "%jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/jenkins                                        && \
#    mv /usr/bin/docker /usr/bin/docker.orig                        && \
#    echo '#!/bin/bash'           >  /usr/bin/docker                && \
#    echo 'sudo docker.orig "$@"'   >> /usr/bin/docker              && \
#    chmod +x /usr/bin/docker                                       && \
    echo sudo successful

USER jenkins

ENTRYPOINT /jenkins-entrypoint.sh
