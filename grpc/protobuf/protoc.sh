usage()
{
   echo "USAGE:"
   echo "   For go: protoc.sh go test.proto"
   echo "   For cpp: protoc.sh cpp test.proto"
   echo "   For java: protoc.sh java test.proto"
   echo "   For js: protoc.sh js test.proto"
}

if [ $# -lt 2 ]
then
  usage
  exit 1
fi
if [ ! -f $2 ];then 
  echo "$2 not existed."
  exit 1
fi

if ! docker images | grep "alpine_grpc" >/dev/null 2>&1; then
  docker build -t alpine_grpc:v1 .
fi

if [ ! -d protobuf_generated ];then 
  mkdir protobuf_generated
fi

if [ $1 = "go" ]; then
  docker run --rm -v $(pwd):$(pwd) -w $(pwd) alpine_grpc:v1 --go-grpc_out=./protobuf_generated --go_out=./protobuf_generated  --go_opt=paths=source_relative --go-grpc_opt=paths=source_relative $2
else
  docker run --rm -v $(pwd):$(pwd) -w $(pwd) alpine_grpc:v1 --$1_out=./protobuf_generated $2
fi
echo "please check files generated within protobuf_generated:"
ls protobuf_generated 
