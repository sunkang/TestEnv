#
# docker build . -t ubuntu:docker
# docker run --rm -itd --privileged=true ubuntu:docker /sbin/init
# docker exec -it [container_id] bash
#
FROM ubuntu
RUN apt update \
    && apt install -y curl apt-transport-https ca-certificates software-properties-common wget systemd gettext iproute2 net-tools iputils-ping \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt update \
    && apt install -y docker-ce docker-ce-cli containerd.io

WORKDIR /
CMD ["/sbin/init" && "docker --registry-mirror=https://registry.docker-cn.com"]
