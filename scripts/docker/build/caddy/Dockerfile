FROM caddy:2.7.6-alpine

COPY ./Caddyfile /etc/caddy/Caddyfile

RUN apk update && apk --no-cache add curl && \
    rm -rf /var/cache/apk/* && \
    adduser -D -s /bin/sh caddy && \
    chown -R caddy:caddy /etc/caddy

USER caddy
