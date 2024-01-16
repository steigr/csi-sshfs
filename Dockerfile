ARG GOLANG_VERSION=1.21.6
ARG ALPINE_VERSION=3.19.0
FROM golang:${GOLANG_VERSION}-alpine AS golang
FROM library/alpine:${ALPINE_VERSION} AS alpine

FROM golang AS build-env
RUN apk add --no-cache git

ENV CGO_ENABLED=0
WORKDIR /go/src/github.com/steigr/csi-sshfs

COPY go.mod .
COPY go.sum .
RUN go mod download -x
COPY cmd/ cmd/
COPY pkg/ pkg/
RUN go get ./...
RUN go vet ./...
RUN go test -v ./...

RUN BUILD_TIME=$(date -R) \
 && go build -v -o /bin/csi-sshfs -ldflags "-w -s -X 'github.com/steigr/csi-sshfs/pkg/sshfs.BuildTime=${BUILD_TIME}'" github.com/steigr/csi-sshfs/cmd/csi-sshfs \
 && csi-sshfs version

FROM alpine

RUN apk add --no-cache ca-certificates sshfs findmnt

COPY --from=build-env /bin/csi-sshfs /bin/csi-sshfs

ENTRYPOINT ["csi-sshfs","run"]
CMD []
