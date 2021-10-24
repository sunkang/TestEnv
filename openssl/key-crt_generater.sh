TEMP_FOLDER=`pwd`"/key_tmp"
DOCKER_IMAGE="ubuntu_openssl"

if [ ! -d $TEMP_FOLDER ];then 
  mkdir $TEMP_FOLDER
fi

cd $TEMP_FOLDER

if ! docker ps | grep "openssl_gen" >/dev/null 2>&1; then
  docker run -itd --name openssl_gen -v $TEMP_FOLDER:/data $DOCKER_IMAGE
fi

exec_cmd() {
   cmd="docker exec -it openssl_gen $1"
   echo ${cmd}
   eval ${cmd}
}
exec_sed() {
   exec_cmd "sed -i \"$1\" /data/openssl.cnf"
}

exec_cmd "cp /etc/ssl/openssl.cnf /data"
exec_sed "s/# copy_extensions/copy_extensions/g"
exec_sed "s/# req_extensions/req_extensions/g"
exec_sed "/\[ v3_req \]/a\subjectAltName = @alt_names"
exec_sed "/\[ v3_req \]/i\\[ alt_names \]"
exec_sed "/\[ v3_req \]/i\DNS.1 = localhost"
exec_sed "/\[ v3_req \]/i\DNS.2 = www.custer.com"

exec_cmd "openssl genrsa -out /data/ca.key 2048"
exec_cmd "openssl req -new -x509 -days 3650 -key /data/ca.key -out /data/ca.pem -subj \"/CN=localhost\""

#generate server key&crt
exec_cmd "openssl genpkey -algorithm RSA -out /data/server.key"
exec_cmd "openssl req -new -nodes -key /data/server.key -out /data/server.csr -days 3650 -subj \"/C=cn/OU=custer/O=custer/CN=localhost\" -config /data/openssl.cnf -extensions v3_req"
exec_cmd "openssl x509 -req -days 3650 -in /data/server.csr -out /data/server.pem -CA /data/ca.pem -CAkey /data/ca.key -CAcreateserial -extfile /data/openssl.cnf -extensions v3_req"

#generate client key&crt
exec_cmd "openssl genpkey -algorithm RSA -out /data/client.key"
exec_cmd "openssl req -new -nodes -key /data/client.key -out /data/client.csr -days 3650 -subj \"/C=cn/OU=custer/O=custer/CN=localhost\" -config /data/openssl.cnf -extensions v3_req"
exec_cmd "openssl x509 -req -days 3650 -in /data/client.csr -out /data/client.pem -CA /data/ca.pem -CAkey /data/ca.key -CAcreateserial -extfile /data/openssl.cnf -extensions v3_req"








