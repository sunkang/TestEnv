#
# chmod 777 master_setup.sh
# please using redis 6+ version docker images as well.
# After exec this shell, try cmd "docker stop redis-6010"  to check if sentinel take effect.
# (it will cost servel seconds, set the redis configuration as you wish within the conf file).
#
# exec cmd "master_setup.sh stop" to shutdown and remove all docker containers.
#

MASTER_SLAVE_TMP_FOLDER=`pwd`"/master-slave-tmp"
REDIS_PATH=$MASTER_SLAVE_TMP_FOLDER/redis
SENTINEL_PATH=$MASTER_SLAVE_TMP_FOLDER/sentinel

LOCAL_IP=`ifconfig eth0 |awk -F '[ :]+' 'NR==2 {print $3}'`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

REDIS_PWD=pwd123pwd

SENTINEL_COUNT=3
SENTINEL_VALID_COUNT=2
SENTINEL_PORT_FROM=17010
SENTINEL_PORT_TO=`expr $SENTINEL_PORT_FROM + $SENTINEL_COUNT - 1`

REDIS_COUNT=3               #1 master with 2 slave
REDIS_PORT_MASTER=6010      #master port

REDIS_PORT_FROM=$REDIS_PORT_MASTER       #master node port
REDIS_PORT_TO=`expr $REDIS_PORT_FROM + $REDIS_COUNT - 1`

if ! docker images | grep redis >/dev/null 2>&1; then
  echo "docker pull redis"
  docker pull redis
fi

if [[ -d $MASTER_SLAVE_TMP_FOLDER ]];then
  rm -rf $MASTER_SLAVE_TMP_FOLDER
fi

mkdir -p $REDIS_PATH
cd $REDIS_PATH

echo 'port ${PORT}
daemonize no' > redis.tmpl
echo "appendonly yes" >> redis.tmpl
echo "masterauth $REDIS_PWD" >> redis.tmpl
echo "requirepass $REDIS_PWD" >> redis.tmpl
echo "rename-command FLUSHALL \"\"" >> redis.tmpl
echo "rename-command EVAL \"\"" >> redis.tmpl

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    mkdir -p $REDIS_PATH/${port}/data;
    PORT=${port} envsubst < $REDIS_PATH/redis.tmpl > $REDIS_PATH/${port}/data/redis.conf;
    if [ $REDIS_PORT_FROM != ${port} ]; then
      echo "slaveof $LOCAL_IP $REDIS_PORT_FROM" >> $REDIS_PATH/${port}/data/redis.conf;
    fi
done

mkdir -p $SENTINEL_PATH
cd $SENTINEL_PATH

echo 'port ${PORT}
pidfile  /data/redis-sentinel_${PORT}.log
logfile  /data/sentinel_${PORT}.log' > sentinel.tmpl;
echo "sentinel monitor mymaster $LOCAL_IP $REDIS_PORT_FROM $SENTINEL_VALID_COUNT" >> sentinel.tmpl;
echo "sentinel auth-pass mymaster $REDIS_PWD" >> sentinel.tmpl;
echo 'protected-mode  no
sentinel down-after-milliseconds mymaster 3000
sentinel failover-timeout mymaster 5000' >> sentinel.tmpl;

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    mkdir -p $SENTINEL_PATH/${port}/data;
    PORT=${port} envsubst < $SENTINEL_PATH/sentinel.tmpl > $SENTINEL_PATH/${port}/data/sentinel.conf;
    #cat $SENTINEL_PATH/${port}/data/sentinel.conf;
done

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    if docker ps | grep redis-${port} >/dev/null 2>&1; then
       docker stop redis-${port}
       sleep 2s
    fi
done

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    if docker ps -a | grep redis-${port} >/dev/null 2>&1; then
       docker rm redis-${port}
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

if ! docker network ls | grep redis-net >/dev/null 2>&1; then
  echo "create docker network redis-net";
  docker network create redis-net;
fi

if [[ $1 == "stop" ]]; then
  echo "stop docker containers"
  rm -rf $MASTER_SLAVE_TMP_FOLDER
  exit 1
fi

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    #redis-bus-port: 1${port}
    docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /data/redis.conf;

    sleep 2s
    echo "docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /data/redis.conf;"
done

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

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    echo "docker exec -it redis-${port} redis-cli -a $REDIS_PWD -p ${port} -h $LOCAL_IP info replication"
    docker exec -it redis-${port} redis-cli -a $REDIS_PWD -p ${port} -h $LOCAL_IP info replication
done

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    echo "docker exec -it sentinel-${port} redis-cli -a $REDIS_PWD -p ${port} -h $LOCAL_IP info sentinel"
    docker exec -it sentinel-${port} redis-cli -a $REDIS_PWD -p ${port} -h $LOCAL_IP info sentinel
done
