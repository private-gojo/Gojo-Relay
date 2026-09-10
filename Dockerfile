FROM teddysun/xray:latest

# Install nginx + supervisord + python3 + curl + netcat
RUN apk add --no-cache \
    nginx \
    supervisor \
    python3 \
    curl \
    netcat-openbsd

# Copy configs
COPY config.json /etc/xray/config.json
COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisord.conf
COPY index.html /var/lib/nginx/html/index.html
COPY entrypoint.sh /entrypoint.sh
COPY sub_server.py /sub_server.py
COPY wait-for-xray.sh /wait-for-xray.sh

# Permissions
RUN chmod +x /entrypoint.sh /sub_server.py /wait-for-xray.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
