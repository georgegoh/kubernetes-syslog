FROM fluent/fluentd:v0.12
MAINTAINER George Goh <george.goh@redhat.com>
WORKDIR /home/fluent

RUN apk add --no-cache --update --virtual .build-deps sudo build-base ruby-dev && \

    sudo fluent-gem install --no-document fluent-plugin-record-reformer && \
    sudo fluent-gem install --no-document fluent-plugin-docker_metadata_filter && \
    sudo fluent-gem install --no-document fluent-plugin-kubernetes_metadata_filter && \
    sudo fluent-gem install --no-document fluent-plugin-flatten-hash && \
    sudo fluent-gem install --no-document fluent-plugin-kubernetes_remote_syslog && \
    sudo fluent-gem sources --clear-all && \
    apk del .build-deps sudo build-base ruby-dev && \
    rm -rf /var/cache/apk/* \
           /home/fluent/.gem/ruby/2.3.0/cache/*.gem

EXPOSE 24284

CMD exec fluentd -c /fluentd/etc/$FLUENTD_CONF -p /fluentd/plugins $FLUENTD_OPT
