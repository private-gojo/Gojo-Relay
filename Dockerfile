FROM teddysun/xray:latest

# Install nginx + supervisord + python3
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    nginx \
    supervisor \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy configs
COPY config.json /etc/xray/config.json
COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisord.conf
COPY index.html /usr/share/nginx/html/index.html
COPY entrypoint.sh /entrypoint.sh

# Permissions
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
