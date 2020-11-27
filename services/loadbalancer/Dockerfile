# *************************************************************************************
# Prepare files in a Builder Image
FROM centos:8 as builder

ENV ROOT=/builder

COPY files/run-httpd.sh $ROOT/
COPY files/httpd.conf   $ROOT/etc/httpd/conf/
COPY files/00-load*     $ROOT/etc/httpd/conf.modules.d/
COPY files/load*        $ROOT/etc/httpd/conf.d/

COPY html/              $ROOT/var/www/html/


# To enable ssl ...
# ...create a certificate and keys... e.g. https://jamielinux.com/docs/openssl-certificate-authority/
# put 	loadbalancer.crt.pem, loadbalancer.key.pem into files/
# add mod_ssl to yum install below
# uncomment X-Forwarded header in files/loadbalancer.conf
# uncomment the following lines
# COPY files/loadbalancer.crt.pem            $ROOT/etc/pki/tls/certs/ 
# COPY files/loadbalancer.key.pem            $ROOT/etc/pki/tls/private/
# COPY files/ssl.conf                        $ROOT/etc/httpd/conf.d/     
# COPY files/00-ssl.conf                     $ROOT/etc/httpd/conf.modules.d/ 	

RUN  chmod -v +x $ROOT/run-httpd.sh                     && \
     find $ROOT -type f  | xargs -n 1 ls -al



# *************************************************************************************
# Build the final image
FROM centos:8

# see https://github.com/CentOS/CentOS-Dockerfiles/blob/master/httpd/centos7/Dockerfile
RUN yum -y --setopt=tsflags=nodocs install httpd mod_proxy_html openssl socat    && \   
    yum clean all 

COPY --from=builder /builder /

CMD ["/run-httpd.sh"]

