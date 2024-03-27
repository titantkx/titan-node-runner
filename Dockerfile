FROM golang:1.20

WORKDIR /root

RUN apt update
RUN apt install -y git jq curl tar coreutils gzip fish htop

RUN go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0

COPY configs_tmp /root/configs_tmp
COPY titan-node-runner.sh /root/titan-node-runner.sh

ENV HOME=/root
ENV HOME_DATA=/root/data

ENTRYPOINT [ "/root/titan-node-runner.sh" ]
