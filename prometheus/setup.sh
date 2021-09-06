#
# Run this shell under linux with docker installed and started.
# eg. 
#   docker run -itd -p 9100:9100 -p 3000:3000 -p 9090:9090 --name ubuntu_dockerhost --privileged=true ubuntu:docker /sbin/init
#   docker exec -it ubuntu_dockerhost bash
#
LOCAL_IP=`ifconfig eth0 |awk -F '[ :]+' 'NR==2 {print $3}'`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

function docker_pull()
{
  if ! docker images|grep $1 > /dev/null > /dev/null 2>&1; then
    docker pull $1
  fi
}

function docker_stop_rm()
{
  if docker ps|grep $1 > /dev/null > /dev/null 2>&1; then
    docker stop $1
  fi
  if docker ps -a|grep $1 > /dev/null > /dev/null 2>&1; then
    docker rm $1
  fi
}

docker_pull prom/node-exporter
docker_pull prom/prometheus
docker_pull grafana/grafana

docker_stop_rm node-exporter
docker_stop_rm prometheus
docker_stop_rm grafana

docker run -d -p 9100:9100 \
   -v "/proc:/host/proc:ro" \
  -v "/sys:/host/sys:ro" \
  -v "/:/rootfs:ro" \
  --net="host" \
  --name="node-exporter" \
  prom/node-exporter

if [ -f /opt/prometheus/prometheus.yml ]; then
  rm /opt/prometheus/prometheus.yml
fi

if [ ! -d /opt/prometheus ]; then
  mkdir /opt/prometheus
  cd /opt/prometheus/
fi

echo "global: \
  scrape_interval:     60s \
  evaluation_interval: 60s \
scrape_configs: \
  - job_name: prometheus \
    static_configs: \
      - targets: ['localhost:9090'] \
        labels: \
          instance: prometheus \
  - job_name: linux \
    static_configs: \
      - targets: ['$LOCAL_IP:9100'] \
        labels: \
          instance: localhost" >> prometheus.yml

docker run  -d \
  -p 9090:9090 \
  -v /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml  \
  --name=prometheus \
  prom/prometheus

if [ ! -d /opt/grafana-storage ]; then
  mkdir /opt/grafana-storage
  chmod 777 -R /opt/grafana-storage
fi

docker run -d \
  -p 3000:3000 \
  --name=grafana \
  -v /opt/grafana-storage:/var/lib/grafana \
  grafana/grafana
