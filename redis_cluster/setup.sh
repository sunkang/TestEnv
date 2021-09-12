#
# chmod 777 setup.sh
#
#For ubuntu
# LOCAL_IP =ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"
#

SHELL_FOLDER=`pwd`
REDIS_PATH=$SHELL_FOLDER/redis-tmp/redis
SENTINEL_PATH=$SHELL_FOLDER/redis-tmp/sentinel

LOCAL_IP=`ifconfig eth0 |awk -F '[ :]+' 'NR==2 {print $3}'`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

REDIS_PWD=pwd123pwd

SENTINEL_COUNT=3
SENTINEL_PORT_FROM=19010
SENTINEL_PORT_TO=`expr $SENTINEL_PORT_FROM + $SENTINEL_COUNT - 1`

REDIS_COUNT=3               #1 master with 2 slave
REDIS_PORT_MASTER=8010      #master port

REDIS_PORT_FROM=$REDIS_PORT_MASTER       #master node port
REDIS_PORT_TO=`expr $REDIS_PORT_FROM + $REDIS_COUNT - 1`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

if ! docker images | grep redis >/dev/null 2>&1; then
  echo "docker pull redis"
  docker pull redis
fi

if [[ -d $SHELL_FOLDER/redis-tmp ]];then
  rm -rf $SHELL_FOLDER/redis-tmp
fi

mkdir -p $REDIS_PATH
cd $REDIS_PATH

echo 'port ${PORT}' > redis.tmpl
echo "appendonly yes" >> redis.tmpl
echo "masterauth $REDIS_PWD" >> redis.tmpl
echo "requirepass $REDIS_PWD" >> redis.tmpl
echo "rename-command FLUSHALL \"\"" >> redis.tmpl
echo "rename-command EVAL \"\"" >> redis.tmpl

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    mkdir -p $REDIS_PATH/${port}/conf;
    PORT=${port} envsubst < $REDIS_PATH/redis.tmpl > $REDIS_PATH/${port}/conf/redis.conf;
    if [ $REDIS_PORT_FROM != ${port} ]; then
      echo "slaveof $LOCAL_IP $REDIS_PORT_FROM" >> $REDIS_PATH/${port}/conf/redis.conf;
    fi
    mkdir -p $REDIS_PATH/${port}/data;
done

mkdir -p $SENTINEL_PATH
cd $SENTINEL_PATH

echo 'port ${PORT}
pidfile  /data/redis-sentinel_${PORT}.log
logfile  /data/sentinel_${PORT}.log
protected-mode  no
sentinel down-after-milliseconds mymaster 3000
sentinel failover-timeout mymaster 5000' >> sentinel.tmpl;
echo "sentinel monitor mymaster $LOCAL_IP $REDIS_PORT_FROM 2" >> sentinel.tmpl;
echo "sentinel auth-pass mymaster $REDIS_PWD" >> sentinel.tmpl;

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    mkdir -p $SENTINEL_PATH/${port}/conf;
    PORT=${port} envsubst < $SENTINEL_PATH/sentinel.tmpl > $SENTINEL_PATH/${port}/conf/sentinel.conf;
    cat $SENTINEL_PATH/${port}/conf/sentinel.conf;
    mkdir -p $SENTINEL_PATH/${port}/data;
done

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    if docker ps | grep redis-${port} >/dev/null 2>&1; then
       docker stop redis-${port}
    fi
done

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    if docker ps -a | grep redis-${port} >/dev/null 2>&1; then
       docker rm redis-${port}
    fi
done

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    if docker ps | grep sentinel-${port} >/dev/null 2>&1; then
       docker stop sentinel-${port}
    fi
done

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    if docker ps -a | grep sentinel-${port} >/dev/null 2>&1; then
       docker rm sentinel-${port}
    fi
done

if ! docker network ls | grep redis-net >/dev/null 2>&1; then
  echo "create docker network redis-net";
  docker network create redis-net;
fi

for port in $(seq $REDIS_PORT_FROM $REDIS_PORT_TO);
  do
    #redis-bus-port: 1${port}
    docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_PATH/${port}/conf/redis.conf:/usr/local/etc/redis/redis.conf \
       --privileged=true -v $REDIS_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /usr/local/etc/redis/redis.conf;

    echo "docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_PATH/${port}/conf/redis.conf:/usr/local/etc/redis/redis.conf \
       --privileged=true -v $REDIS_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /usr/local/etc/redis/redis.conf;"
done

for port in $(seq $SENTINEL_PORT_FROM $SENTINEL_PORT_TO);
  do
    docker run -it -d -p ${port}:${port} \
       --privileged=true -v $SENTINEL_PATH/${port}/conf/sentinel.conf:/usr/local/etc/redis/sentinel.conf \
       --privileged=true -v $SENTINEL_PATH/${port}/data:/data \
       --restart always --name sentinel-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 --privileged=true redis redis-sentinel /usr/local/etc/redis/sentinel.conf;

    echo "docker run -it -d -p ${port}:${port} \
       --privileged=true -v $SENTINEL_PATH/${port}/conf/sentinel.conf:/usr/local/etc/redis/sentinel.conf \
       --privileged=true -v $SENTINEL_PATH/${port}/data:/data \
       --restart always --name sentinel-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 --privileged=true redis redis-sentinel /usr/local/etc/redis/sentinel.conf;"
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


