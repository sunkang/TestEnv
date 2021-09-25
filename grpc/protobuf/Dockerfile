## stage 1 : install protoc
FROM alpine:latest as stage1

## install protobuf
RUN apk update && apk add --no-cache protobuf
RUN protoc --version
RUN type protoc

## stage 2 : install protoc-gen-go
FROM golang:latest as stage2

# Build Delve
RUN go env -w GO111MODULE=on && go env -w GOPROXY=https://goproxy.cn
RUN go install github.com/golang/protobuf/protoc-gen-go@latest
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
RUN ls $GOPATH/bin && echo $GOPATH

#COPY --from=stage1 /usr/bin/protoc /go/bin/

## stage 3 : copy command file to buxybox
FROM  stage1

RUN mkdir -p /go/bin
COPY --from=stage2 /go/bin/protoc-gen-go /go/bin/
COPY --from=stage2 /go/bin/protoc-gen-go-grpc /go/bin/

ENV PATH=$PATH:/go/bin

RUN ls /go/bin

ENTRYPOINT ["protoc"]
CMD ["--version"]


