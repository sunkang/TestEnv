FROM centos

RUN ETCD_VER=v3.5.0 && ETCD_HOME=/home/etcd \
    && GOOGLE_URL=https://storage.googleapis.com/etcd \	
    && GITHUB_URL=https://github.com/etcd-io/etcd/releases/download \
    && DOWNLOAD_URL=${GOOGLE_URL} \
    && rm -f /${ETCD_HOME}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
    && rm -rf ${ETCD_HOME} && mkdir -p ${ETCD_HOME} \
    && curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /${ETCD_HOME}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
    && tar xzvf /${ETCD_HOME}/etcd-${ETCD_VER}-linux-amd64.tar.gz -C ${ETCD_HOME} --strip-components=1 \
    && rm -f /${ETCD_HOME}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
    && chmod 777 ${ETCD_HOME}/etcd \
    && chmod 777 ${ETCD_HOME}/etcdctl \
    && chmod 777 ${ETCD_HOME}/etcdutl

WORKDIR /home
CMD ["/home/etcd/etcd --name s1   --data-dir /etcd-data   --listen-client-urls http://0.0.0.0:2379   --advertise-client-urls http://0.0.0.0:2379   --listen-peer-urls http://0.0.0.0:2380   --initial-advertise-peer-urls http://0.0.0.0:2380   --initial-cluster s1=http://0.0.0.0:2380   --initial-cluster-token tkn   --initial-cluster-state new   --log-level info   --logger zap   --log-outputs stderr"]



