# TODO make DRY

default:
	echo Choose an option

deps-clean:
	rm -f go.sum
	cp -a original_go.mod go.mod

deps: deps-clean
	./update-kubernetes-versions.sh 1.20.2
	go get ./...
	go mod tidy

fmt:
	go fmt ./...

vet:
	go vet ./...

test:
	go test ./...

compile:
	CGO_ENABLED=0 go build -ldflags="-w -s -X 'github.com/steigr/csi-sshfs/pkg/sshfs.BuildTime=$(shell date -R)'" -o csi-sshfs ./cmd/csi-sshfs/...

build:
	docker build . --pull --no-cache -t steigr/csi-sshfs:latest

build-with-cache:
	docker build . --pull -t steigr/csi-sshfs:latest

push: build-with-cache
	docker push steigr/csi-sshfs:latest

build-debug:
	docker build . --pull --no-cache -t steigr/csi-sshfs:debug -f Dockerfile.debug

build-debug-with-cache:
	docker build . --pull -t steigr/csi-sshfs:debug -f Dockerfile.debug

push-debug: build-debug-with-cache
	docker push steigr/csi-sshfs:debug

push-all: push push-debug
