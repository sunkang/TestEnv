#
# chmod 777 setup.sh
# please using redis 6+ version docker images as well.
# After exec this shell, try cmd "docker stop redis-8010"  to check if sentinel take effect.
# (it will cost servel seconds, set the redis configuration as you wish within the conf file).
#
# exec cmd "cluster_setup.sh stop" to shutdown and remove all docker containers.
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
CLUSTER_MASTER_ID_ARRAY=()

SLAVE_PORT_FROM=8110
SLAVE_PORT_ARRAY=($(seq $SLAVE_PORT_FROM `expr $SLAVE_PORT_FROM + $(($CLUSTER_SLAVE_NUM * $CLUSTER_MASTER_COUNT)) - 1`))

SENTINEL_COUNT=3
SENTINEL_VALID_COUNT=2
SENTINEL_PORT_FROM=19010
SENTINEL_PORT_ARRAY=($(seq $SENTINEL_PORT_FROM `expr $SENTINEL_PORT_FROM + $SENTINEL_COUNT - 1`))

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

for(( i=0;i<$CLUSTER_MASTER_COUNT;i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    mkdir -p $REDIS_CLUSTER_PATH/${port}/data;
    PORT=${port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster.tmpl > $REDIS_CLUSTER_PATH/${port}/data/redis.conf;

    for (( j=0;j<$CLUSTER_SLAVE_NUM;j++ )) do
      index=$(( $(($j*$CLUSTER_MASTER_COUNT)) + $i))
      slave_port=${SLAVE_PORT_ARRAY[$index]}
      mkdir -p $REDIS_CLUSTER_PATH/${port}/slave${index}_data;
      PORT=${slave_port} MASTER_IP_PORT=$LOCAL_IP" "${port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster-slave.tmpl > $REDIS_CLUSTER_PATH/${port}/slave${index}_data/redis_slave.conf;
    done
done

mkdir -p $SENTINEL_PATH
cd $SENTINEL_PATH

echo 'port ${PORT}
daemonize no
protected-mode  no
pidfile  /data/redis-sentinel_${PORT}.log
logfile  /data/sentinel_${PORT}.log' > sentinel.tmpl;

for(( i=0;i<$SENTINEL_COUNT;i++ )) do
  port=${SENTINEL_PORT_ARRAY[$i]}
  mkdir -p $SENTINEL_PATH/${port}/data;
  PORT=${port} envsubst < $SENTINEL_PATH/sentinel.tmpl > $SENTINEL_PATH/${port}/data/sentinel.conf;

  master_port=${CLUSTER_PORT_ARRAY[$i]}
  echo "sentinel monitor mymaster${i} $LOCAL_IP ${master_port} $SENTINEL_VALID_COUNT" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
  echo "sentinel down-after-milliseconds mymaster${i} 3000" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
  echo "sentinel failover-timeout mymaster${i} 5000" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
  echo "sentinel auth-pass mymaster${i} $REDIS_PWD" >> $SENTINEL_PATH/${port}/data/sentinel.conf;
done

echo_eval() {
  echo $1
  eval $1
}

exec_start_docker() {
  active_name=""
  arary=($1)
  for(( i=0;i<${#arary[@]};i++)) do
      port=${arary[$i]}
      if ! docker ps | grep $2-${port} >/dev/null 2>&1; then
        active_name+=" $2-${port}"
      fi
  done
  if [ ! "$active_name" == "" ]; then
    echo_eval "docker start $active_name"
  fi
}

exec_rm_docker() {
  active_name=""
  deactive_name=""
  arary=($1)
  for(( i=0;i<${#arary[@]};i++)) do
      port=${arary[$i]}
      if docker ps | grep $2-${port} >/dev/null 2>&1; then
        active_name+=" $2-${port}"
      fi
      if docker ps -a | grep $2-${port} >/dev/null 2>&1; then
        deactive_name+=" $2-${port}"
      fi
  done
  if [ ! "$active_name" == "" ]; then
    echo_eval "docker stop $active_name"
  fi
  sleep 3s
  if [ ! "$deactive_name" == "" ]; then
    echo_eval "docker rm $deactive_name"
  fi
}
exec_rm_docker "${CLUSTER_PORT_ARRAY[*]}" "redis"
exec_rm_docker "${SLAVE_PORT_ARRAY[*]}" "redis-slave"
exec_rm_docker "${SENTINEL_PORT_ARRAY[*]}" "sentinel"

if [[ $1 == "stop" ]]; then
  echo "stop docker containers"
  rm -rf $CLUSTER_TMP_FOLDER
  exit 1
fi

for(( i=0;i<$CLUSTER_MASTER_COUNT;i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    echo_eval "docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /data/redis.conf";
    sleep 2s
done

cmd="docker exec -it redis-$PORT_FROM redis-cli --cluster create";
for port in $(seq $PORT_FROM $PORT_TO);
  do
    cmd+=" $LOCAL_IP:"${port};
done;
cmd+=" --cluster-replicas 0";
echo "$cmd";
eval "$cmd";

for(( i=0;i<$CLUSTER_MASTER_COUNT;i++ )) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    cluster_id=`docker exec -it redis-${port} redis-cli -h $LOCAL_IP -p ${port} cluster myid`;
    CLUSTER_MASTER_ID_ARRAY[$i]=${cluster_id}
done

for(( i=0;i<${#CLUSTER_PORT_ARRAY[@]};i++ )) do
    port=${CLUSTER_PORT_ARRAY[$i]}

    for (( j=0;j<$CLUSTER_SLAVE_NUM;j++ )) do
      index=$(( $(($j*$CLUSTER_MASTER_COUNT)) + $i))
      slave_port=${SLAVE_PORT_ARRAY[$index]}
      echo_eval "docker run -it -d -p ${slave_port}:${slave_port} -p 1${slave_port}:1${slave_port} \
         --privileged=true -v $REDIS_CLUSTER_PATH/${port}/slave${index}_data:/data \
         --restart always --name redis-slave-${slave_port} --net redis-net \
         --sysctl net.core.somaxconn=1024 redis redis-server /data/redis_slave.conf"
      sleep 2s
    done
done

sleep 5s

for(( i=0;i<$CLUSTER_MASTER_COUNT;i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    slave_port=${SLAVE_PORT_ARRAY[$i]}

    echo "requirepass $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/data/redis.conf;
    echo "masterauth $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/data/redis.conf;

    for (( j=0;j<$CLUSTER_SLAVE_NUM;j++ )) do
      index=$(( $(($j*$CLUSTER_MASTER_COUNT)) + $i))
      echo "requirepass $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/slave${index}_data/redis_slave.conf;
      echo "masterauth $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/slave${index}_data/redis_slave.conf;
    done

    docker exec -it redis-${port} redis-cli -c -h $LOCAL_IP -p ${port} shutdown
    docker exec -it redis-slave-${slave_port} redis-cli -c -h $LOCAL_IP -p ${slave_port} shutdown
    sleep 3s
done
sleep 8s
exec_start_docker "${CLUSTER_PORT_ARRAY[*]}" "redis"
exec_start_docker "${SLAVE_PORT_ARRAY[*]}" "redis-slave"
sleep 8s
for(( i=0;i<$CLUSTER_MASTER_COUNT;i++)) do
    port=${CLUSTER_PORT_ARRAY[$i]}
    cluster_id=${CLUSTER_MASTER_ID_ARRAY[$i]}
    echo_eval "docker exec -it redis-${port} redis-cli -c -h $LOCAL_IP -p ${port} -a $REDIS_PWD cluster nodes"

    for (( j=0;j<$CLUSTER_SLAVE_NUM;j++ )) do
      index=$(( $(($j*$CLUSTER_MASTER_COUNT)) + $i))
      slave_port=${SLAVE_PORT_ARRAY[$index]}
      echo_eval "docker exec -it redis-slave-${slave_port} redis-cli -c -h $LOCAL_IP -p ${slave_port} -a $REDIS_PWD cluster meet $LOCAL_IP ${port}"
      echo_eval "docker exec -it redis-slave-${slave_port} redis-cli -c -h $LOCAL_IP -p ${slave_port} -a $REDIS_PWD cluster replicate ${cluster_id}"
    done
done

for(( i=0;i<$SENTINEL_COUNT;i++)) do
    port=${SENTINEL_PORT_ARRAY[$i]}
    echo_eval "docker run -it -d -p ${port}:${port} \
       --privileged=true -v $SENTINEL_PATH/${port}/data:/data \
       --restart always --name sentinel-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 --privileged=true redis redis-server /data/sentinel.conf --sentinel"
done

echo_eval "docker exec -it redis-$PORT_TO redis-cli -c -h $LOCAL_IP -p $PORT_FROM -a $REDIS_PWD"
