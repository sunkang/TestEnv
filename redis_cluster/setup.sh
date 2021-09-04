# MAC version
# chmod 777 setup.sh
#
LOCAL_IP=`ifconfig | grep inet | grep -v inet6 | grep -v 127 | cut -d ' ' -f2`
SHELL_FOLDER=`pwd`
REDIS_CLUSTER_PATH=$SHELL_FOLDER/redis-tmp/redis-cluster

CLUSTER_COUNT=3
PORT_FROM=8010
PORT_TO=`expr $PORT_FROM + $CLUSTER_COUNT - 1`

if ! docker images | grep redis >/dev/null 2>&1; then
  docker pull redis
fi

if [[ -d $SHELL_FOLDER/redis-tmp ]];then
  rm -rf $SHELL_FOLDER/redis-tmp
fi

mkdir -p $REDIS_CLUSTER_PATH
cd $REDIS_CLUSTER_PATH

echo 'port ${PORT}
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000'  > redis-cluster.tmpl
echo "cluster-announce-ip $LOCAL_IP" >> redis-cluster.tmpl
echo 'cluster-announce-port ${PORT}
cluster-announce-bus-port 1${PORT}
appendonly yes' >> redis-cluster.tmpl

if ! docker network ls | grep redis-net >/dev/null 2>&1; then
  echo "create docker network redis-net";
  docker network create redis-net;
fi

for port in $(seq $PORT_FROM $PORT_TO);
  do
    mkdir -p $REDIS_CLUSTER_PATH/${port}/conf;
    PORT=${port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster.tmpl > $REDIS_CLUSTER_PATH/${port}/conf/redis.conf;
    mkdir -p $REDIS_CLUSTER_PATH/${port}/data;
done

for port in $(seq $PORT_FROM $PORT_TO);
  do
    if docker ps | grep redis-${port} >/dev/null 2>&1; then
       docker stop redis-${port}
       docker rm redis-${port}
    fi
    docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/conf/redis.conf:/usr/local/etc/redis/redis.conf \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /usr/local/etc/redis/redis.conf;
done

#docker exec -it redis-$PORT_FROM redis-cli --cluster create 192.168.2.109:8010 192.168.2.109:8011 192.168.2.109:8012
cmd="docker exec -it redis-$PORT_FROM redis-cli --cluster create";
for port in $(seq $PORT_FROM $PORT_TO); 
  do cmd+=' $LOCAL_IP:'${port};
done; 
eval "$cmd";

#docker exec -it redis-8010 redis-cli -c -h 192.168.2.109 -p 8012

