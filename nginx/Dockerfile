
FROM centos

RUN yum install -y  pcre-devel zlib zlib-devel wget unzip net-tools make gcc openssl openssl-devel \
    && useradd -r -s /sbin/nologin nginx \
    && yum clean all \
    && wget http://nginx.org/download/nginx-1.21.1.tar.gz \
    && tar -zxvf nginx-1.21.1.tar.gz -C /usr/local/src/  \
    && wget https://github.com/adwpc/nginx-rtmp-module/archive/refs/heads/master.zip \
    && unzip master.zip -d /usr/local/src/nginx-1.21.1 \
    && cd /usr/local/src/nginx-1.21.1 && export CFLAGS="-Wno-error" \
    && ./configure --prefix=/apps/nginx --with-http_stub_status_module --with-http_ssl_module --add-module=./nginx-rtmp-module-master \
    && make -j 4  && make -j 4 install \
    && rm -rf /usr/local/src/nginx*

ADD nginx.conf /apps/nginx/conf/nginx.conf

#COPY index.html /apps/nginx/html/

RUN ln -s /apps/nginx/sbin/nginx /usr/sbin/nginx 

EXPOSE 80 443

CMD ["nginx","-g","daemon off;"]