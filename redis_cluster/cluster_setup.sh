#
# chmod 777 setup.sh
#
LOCAL_IP=`ifconfig eth0 |awk -F '[ :]+' 'NR==2 {print $3}'`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi


SHELL_FOLDER=`pwd`
REDIS_CLUSTER_PATH=$SHELL_FOLDER/redis-tmp/redis-cluster

REDIS_PWD=pwd123pwd
CLUSTER_SLAVE_NUM=1
CLUSTER_MASTER_COUNT=4
PORT_FROM=8010
PORT_TO=`expr $PORT_FROM + $CLUSTER_MASTER_COUNT - 1`

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

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
#protected-mode no
appendonly yes' >> redis-cluster.tmpl

echo 'port ${PORT}
cluster-enabled yes'  > redis-cluster-slave.tmpl
echo '#protected-mode no
appendonly yes' >> redis-cluster-slave.tmpl

if ! docker network ls | grep redis-net >/dev/null 2>&1; then
  echo "create docker network redis-net";
  docker network create redis-net;
fi

for port in $(seq $PORT_FROM $PORT_TO);
  do
    mkdir -p $REDIS_CLUSTER_PATH/${port}/conf;
    PORT=${port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster.tmpl > $REDIS_CLUSTER_PATH/${port}/conf/redis.conf;

    slave_port=$((10#${port}+100))
    PORT=${slave_port} envsubst < $REDIS_CLUSTER_PATH/redis-cluster-slave.tmpl > $REDIS_CLUSTER_PATH/${port}/conf/redis_slave.conf;
    #echo "slaveof $LOCAL_IP ${port}" >> $REDIS_CLUSTER_PATH/${port}/conf/redis_slave.conf;
    mkdir -p $REDIS_CLUSTER_PATH/${port}/data;
    mkdir -p $REDIS_CLUSTER_PATH/${port}/slave_data;
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

for port in $(seq $PORT_FROM $PORT_TO);
  do
    docker run -it -d -p ${port}:${port} -p 1${port}:1${port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/conf/redis.conf:/usr/local/etc/redis/redis.conf \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/data:/data \
       --restart always --name redis-${port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /usr/local/etc/redis/redis.conf;
    sleep 2s

    slave_port=$((10#${port}+100))
    echo "docker run -it -d -p ${slave_port}:${slave_port} -p 1${slave_port}:1${slave_port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/conf/redis_slave.conf:/usr/local/etc/redis/redis.conf \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/slave_data:/data \
       --restart always --name redis-slave-${slave_port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /usr/local/etc/redis/redis.conf"

    docker run -it -d -p ${slave_port}:${slave_port} -p 1${slave_port}:1${slave_port} \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/conf/redis_slave.conf:/usr/local/etc/redis/redis.conf \
       --privileged=true -v $REDIS_CLUSTER_PATH/${port}/slave_data:/data \
       --restart always --name redis-slave-${slave_port} --net redis-net \
       --sysctl net.core.somaxconn=1024 redis redis-server /usr/local/etc/redis/redis.conf;
    sleep 2s
done

cmd="docker exec -it redis-$PORT_FROM redis-cli --cluster create";
for port in $(seq $PORT_FROM $PORT_TO); 
  do
    cmd+=" $LOCAL_IP:"${port};
done; 
echo "$cmd";
eval "$cmd";

for port in $(seq $PORT_FROM $PORT_TO); 
  do
    slave_port=$((10#${port}+100))
    cluster_id=`docker exec -it redis-${port} redis-cli -h $LOCAL_IP -p ${port} cluster myid`;
    echo "docker exec -it redis-slave-${slave_port} redis-cli --cluster add-node $LOCAL_IP:${slave_port} $LOCAL_IP:${port} --cluster-master-id ${cluster_id}";
    docker exec -it redis-slave-${slave_port} redis-cli --cluster add-node $LOCAL_IP:${slave_port} $LOCAL_IP:${port} --cluster-master-id ${cluster_id};
    sleep 1s
done; 

for port in $(seq $PORT_FROM $PORT_TO);
  do
    echo "requirepass $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/conf/redis.conf;
    echo "requirepass $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/conf/redis_slave.conf;
    echo "masterauth $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/conf/redis.conf;
    echo "masterauth $REDIS_PWD" >> $REDIS_CLUSTER_PATH/${port}/conf/redis_slave.conf;

    docker exec -it redis-${port} redis-cli -c -h localhost -p ${port} shutdown
    slave_port=$((10#${port}+100))
    docker exec -it redis-slave-${slave_port} redis-cli -c -h localhost -p ${slave_port} shutdown
done

sleep 2s

echo "docker exec -it redis-$PORT_TO redis-cli -c -h $LOCAL_IP -p $PORT_FROM -a $REDIS_PWD"
docker exec -it redis-$PORT_TO redis-cli -c -h $LOCAL_IP -p $PORT_FROM -a $REDIS_PWD

