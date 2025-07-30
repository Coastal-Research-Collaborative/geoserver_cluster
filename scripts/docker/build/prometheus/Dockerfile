FROM prom/prometheus:v2.48.1

USER root
RUN adduser -D -s /bin/sh prometheus-user
USER prometheus-user

ADD prometheus.yml /etc/prometheus/

