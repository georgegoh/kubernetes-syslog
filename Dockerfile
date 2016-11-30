FROM fluent/fluentd:latest
MAINTAINER George Goh <george.goh@redhat.com>
WORKDIR /home/fluent
ENV PATH /home/fluent/.gem/ruby/2.3.0/bin:$PATH

USER root
RUN apk --no-cache --update add sudo build-base ruby-dev && \

    sudo -u fluent gem install --no-document fluent-plugin-record-reformer && \
    sudo -u fluent gem install --no-document fluent-plugin-docker_metadata_filter && \
    sudo -u fluent gem install --no-document fluent-plugin-kubernetes_metadata_filter && \
    sudo -u fluent gem install --no-document fluent-plugin-flatten-hash && \
    sudo -u fluent gem install --no-document fluent-plugin-kubernetes_remote_syslog && \

    rm -rf /home/fluent/.gem/ruby/2.3.0/cache/*.gem && sudo -u fluent gem sources -c && \
    apk del sudo build-base ruby-dev && rm -rf /var/cache/apk/*

EXPOSE 24284

CMD exec fluentd -c /fluentd/etc/$FLUENTD_CONF -p /fluentd/plugins $FLUENTD_OPT
