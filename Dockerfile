FROM golang:1.15-alpine AS build-env
RUN apk add --no-cache git


ENV CGO_ENABLED=0
WORKDIR /go/src/github.com/Patricol/csi-sshfs

COPY . .
RUN go get ./...

RUN export BUILD_TIME=$(date -R) \
 && go build -o /csi-sshfs -ldflags "-X 'github.com/Patricol/csi-sshfs/pkg/sshfs.BuildTime=${BUILD_TIME}'" github.com/Patricol/csi-sshfs/cmd/csi-sshfs

FROM alpine:latest

RUN apk add --no-cache ca-certificates sshfs findmnt

COPY --from=build-env /csi-sshfs /bin/csi-sshfs

ENTRYPOINT ["/bin/csi-sshfs"]
CMD [""]
