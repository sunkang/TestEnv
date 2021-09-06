ETCD_VERSION=v3.2.30 #3.5.0
LOCAL_IP=`ifconfig eth0 |awk -F '[ :]+' 'NR==2 {print $3}'`
TOKEN=amc-etcd-token
SUDO=

#For mac os
if uname -a | grep Darwin > /dev/null > /dev/null 2>&1; then
  LOCAL_IP=`ifconfig en0 | grep "inet\ " | awk '{ print $2}'`
fi

CLUSTER_STATE=new
NAMES=(etcd-node-0 etcd-node-1 etcd-node-2)
HOSTS=($LOCAL_IP $LOCAL_IP $LOCAL_IP)
CLIENT_PORTS=(21379 22379 23379)
PARTNER_PORTS=(21380 22380 23380)

#Test array index start(pick up for mac ^ linux)
_first=0
if [ -z ${NAMES[0]} ]; then
    _first=1;
fi

CLUSTER=${NAMES[_first]}=http://${HOSTS[_first]}:${PARTNER_PORTS[_first]}
for (( i=1; i < ${#NAMES[@]}; i++)) do
    CLUSTER=${CLUSTER},${NAMES[$i+${_first}]}=http://${HOSTS[$i+${_first}]}:${PARTNER_PORTS[$i+${_first}]};
done;

echo CLUSTER=${CLUSTER}

for (( i=0; i < ${#NAMES[@]}; i++)) do
  THIS_NAME=${NAMES[$i+${_first}]};
  if docker ps|grep ${THIS_NAME} > /dev/null 2>&1 ;then
    docker stop ${THIS_NAME}
  fi
  if docker ps -a|grep ${THIS_NAME} > /dev/null 2>&1 ;then
    docker rm ${THIS_NAME}
  fi
done

# For each node 1
for (( i=0; i < ${#NAMES[@]}; i++)) do
  THIS_NAME=${NAMES[$i+${_first}]};
  THIS_HOST=${HOSTS[$i+${_first}]};
  THIS_CLIENT_PORT=${CLIENT_PORTS[$i+${_first}]};
  THIS_PARTNER_PORT=${PARTNER_PORTS[$i+${_first}]};
  ${SUDO} docker run -d --name ${THIS_NAME} \
        -p ${THIS_PARTNER_PORT}:2380 -p ${THIS_CLIENT_PORT}:2379 \
        quay.io/coreos/etcd:${ETCD_VERSION} \
        /usr/local/bin/etcd \
        --data-dir=data.etcd --name ${THIS_NAME} \
        --initial-advertise-peer-urls http://${THIS_HOST}:${THIS_PARTNER_PORT} --listen-peer-urls http://0.0.0.0:2380 \
        --advertise-client-urls http://${THIS_HOST}:${THIS_CLIENT_PORT} --listen-client-urls http://0.0.0.0:2379 \
        --initial-cluster ${CLUSTER} \
        --initial-cluster-token ${TOKEN} \
        --initial-cluster-state ${CLUSTER_STATE};
done;

docker exec -it ${NAMES[1]} etcdctl member list
