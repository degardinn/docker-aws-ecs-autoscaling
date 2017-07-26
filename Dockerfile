FROM alpine
MAINTAINER Nicolas Degardin <degardin.n@gmail.com>

RUN apk add --update --no-cache jq py-pip
RUN pip install awscli
COPY asg.sh /usr/bin/asg

ENTRYPOINT ["asg"]