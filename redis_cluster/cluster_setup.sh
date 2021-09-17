#
# chmod 777 setup.sh
#
LOCAL_IP=`ifconfig eth0 |awk -F '[ :]+' 'NR==2 {print $3}'`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

CLUSTER_TMP_FOLDER=`pwd`"/redis-cluster-tmp"
REDIS_CLUSTER_PATH=$CLUSTER_TMP_FOLDER/redis-cluster
SENTINEL_PATH=$CLUSTER_TMP_FOLDER/sentinel

REDIS_PWD=pwd123pwd

CLUSTER_SLAVE_NUM=1
CLUSTER_MASTER_COUNT=3
PORT_FROM=8010
PORT_TO=`expr $PORT_FROM + $CLUSTER_MASTER_COUNT - 1`
CLUSTER_PORT_ARRAY=($(seq $PORT_FROM $PORT_TO))

SLAVE_PORT_FROM=8110
SLAVE_PORT_ARRAY=($(seq $SLAVE_PORT_FROM `expr $SLAVE_PORT_FROM + $CLUSTER_MASTER_COUNT - 1`))

SENTINEL_COUNT=3
SENTINEL_VALID_COUNT=2
SENTINEL_PORT_FROM=19010
SENTINEL_PORT_TO=`expr $SENTINEL_PORT_FROM + $SENTINEL_COUNT - 1`
SENTINEL_PORT_ARRAY=($(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO))

if ! docker images | grep redis >/dev/null 2>&1; then
  docker pull redis
fi

if [[ -d $CLUSTER_TMP_FOLDER ]];then
  rm -rf $CLUSTER_TMP_FOLDER
fi

mkdir -p $REDIS_CLUSTER_PATH
cd $REDIS_CLUSTER_PATH

echo 'port ${PORT}
daemonize no
protected-mode no
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000'  > redis-cluster.tmpl
echo "cluster-announce-ip $LOCAL_IP" >> redis-cluster.tmpl
echo 'cluster-announce-port ${PORT}
cluster-announce-bus-port 1${PORT}
appendonly yes' >> redis-cluster.tmpl

echo 'port ${PORT}
daemonize no
protected-mode no
cluster-enabled yes
appendonly yes' >> redis-cluster-slave.tmpl

if ! docker network ls | grep redis-net >/dev/null 2>&1; then
  echo "create docker network redis-net";
  docker network create redis-net;
fi

for(( i=0;i<${#CLUSTER_PORT_ARRAY[@]};i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    slave_port=${SLAVE_PORT_ARRAY[$i]}

    mkdir -p $REDIS_CLUSTER_PATH/${port}/data;
    mkdir -p $REDIS_CLUSTER_PATH/${port}/slave_data;
    PORT=${port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster.tmpl > $REDIS_CLUSTER_PATH/${port}/data/redis.conf;
    PORT=${slave_port} MASTER_IP_PORT=$LOCAL_IP" "${port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster-slave.tmpl > $REDIS_CLUSTER_PATH/${port}/slave_data/redis_slave.conf;
done

mkdir -p $SENTINEL_PATH
cd $SENTINEL_PATH

echo 'port ${PORT}
daemonize no
protected-mode  no
pidfile  /data/redis-sentinel_${PORT}.log
logfile  /data/sentinel_${PORT}.log' > sentinel.tmpl;

for(( i=0;i<${#SENTINEL_PORT_ARRAY[@]};i++)) do
  port=${SENTINEL_PORT_ARRAY[$i]}
  mkdir -p $SENTINEL_PATH/${port}/data;
  PORT=${port} envsubst < $SENTINEL_PATH/sentinel.tmpl > $SENTINEL_PATH/${port}/data/sentinel.conf;

  for(( j=0;j<${#CLUSTER_PORT_ARRAY[@]};j++)) do
    master_port=${CLUSTER_PORT_ARRAY[$j]}
    echo "sentinel monitor mymaster${j} $LOCAL_IP ${master_port} $SENTINEL_VALID_COUNT" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
    echo "sentinel down-after-milliseconds mymaster${j} 3000" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
    echo "sentinel failover-timeout mymaster${j} 5000" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
    echo "sentinel auth-pass mymaster${j} $REDIS_PWD" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
  done
done

for port in $(seq $PORT_FROM $PORT_TO);
  do
    if docker ps | grep redis-${port} >/dev/null 2>&1; then
       echo "docker stop redis-${port}"
       docker stop redis-${port}
       sleep 2s
    fi
done

for port in $(seq $PORT_FROM $PORT_TO);
  do
    slave_port=$((10#${port}+100))
    if docker ps | grep redis-slave-${slave_port} >/dev/null 2>&1; then
       echo "docker stop redis-slave-${slave_port}"
       docker stop redis-slave-${slave_port}
       sleep 2s
    fi
done

for port in $(seq $PORT_FROM $PORT_TO);
  do
    if docker ps -a | grep redis-${port} >/dev/null 2>&1; then
       echo "docker rm redis-${port}"
       docker rm redis-${port}
       sleep 2s
    fi
done

for port in $(seq $PORT_FROM $PORT_TO);
  do
    slave_port=$((10#${port}+100))
    if docker ps -a | grep redis-slave-${slave_port} >/dev/null 2>&1; then
       echo "docker rm redis-slave-${slave_port}"
       docker rm redis-slave-${slave_port}
       sleep 2s
    fi
done

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    if docker ps | grep sentinel-${port} >/dev/null 2>&1; then
       docker stop sentinel-${port}
       sleep 2s
    fi
done

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    if docker ps -a | grep sentinel-${port} >/dev/null 2>&1; then
       docker rm sentinel-${port}
       sleep 2s
    fi
done

if [[ $1 == "stop" ]]; then
  echo "stop docker containers"
  exit 1
fi

for port in $(seq $PORT_FROM $PORT_TO);
  do
    docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /data/redis.conf;
    sleep 2s

    slave_port=$((10#${port}+100))
    echo "docker run -it -d -p ${slave_port}:${slave_port} -p 1${slave_port}:1${slave_port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/slave_data:/data \
       --restart always --name redis-slave-${slave_port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /data/redis_slave.conf"

    docker run -it -d -p ${slave_port}:${slave_port} -p 1${slave_port}:1${slave_port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/slave_data:/data \
       --restart always --name redis-slave-${slave_port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /data/redis_slave.conf;
    sleep 2s
done

cmd="docker exec -it redis-$PORT_FROM redis-cli --cluster create";
for port in $(seq $PORT_FROM $PORT_TO);
  do
    cmd+=" $LOCAL_IP:"${port};
done;
echo "$cmd";
eval "$cmd";

for(( i=0;i<${#CLUSTER_PORT_ARRAY[@]};i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    slave_port=${SLAVE_PORT_ARRAY[$i]}

    cluster_id=`docker exec -it redis-${port} redis-cli -h $LOCAL_IP -p ${port} cluster myid`;
    echo "docker exec -it redis-slave-${slave_port} redis-cli --cluster add-node $LOCAL_IP:${slave_port} $LOCAL_IP:${port} --cluster-master-id ${cluster_id}";
    docker exec -it redis-slave-${slave_port} redis-cli --cluster add-node $LOCAL_IP:${slave_port} $LOCAL_IP:${port} --cluster-master-id ${cluster_id};
    sleep 1s
done;

for(( i=0;i<${#CLUSTER_PORT_ARRAY[@]};i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    slave_port=${SLAVE_PORT_ARRAY[$i]}

    echo "requirepass $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/data/redis.conf;
    echo "requirepass $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/slave_data/redis_slave.conf;
    echo "masterauth $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/data/redis.conf;
    echo "masterauth $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/slave_data/redis_slave.conf;

    docker exec -it redis-${port} redis-cli -c -h localhost -p ${port} shutdown
    docker exec -it redis-slave-${slave_port} redis-cli -c -h localhost -p ${slave_port} shutdown
done

sleep 2s

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    docker run -it -d -p ${port}:${port} \
       --privileged=true -v $SENTINEL_PATH/${port}/data:/data \
       --restart always --name sentinel-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 --privileged=true redis redis-server /data/sentinel.conf --sentinel

    sleep 2s
    echo "docker run -it -d -p ${port}:${port} \
       --privileged=true -v $SENTINEL_PATH/${port}/data:/data \
       --restart always --name sentinel-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 --privileged=true redis redis-server /data/sentinel.conf --sentinel;"
done

echo "docker exec -it redis-$PORT_TO redis-cli -c -h $LOCAL_IP -p $PORT_FROM -a $REDIS_PWD"
docker exec -it redis-$PORT_TO redis-cli -c -h $LOCAL_IP -p $PORT_FROM -a $REDIS_PWD
