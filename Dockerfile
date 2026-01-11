# Use latest Alpine version
FROM alpine:edge

# Security labels
LABEL org.opencontainers.image.title="Samba Server" \
      org.opencontainers.image.description="Secure Samba file server" \
      org.opencontainers.image.vendor="FalconNL93" \
      org.opencontainers.image.licenses="GPL-3.0" \
      maintainer="falconnl93"

# Install dependencies in optimized layers
RUN apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add \
        bash \
        samba \
        samba-common-tools \
        shadow \
        tini \
        tzdata && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Create samba user and group with fixed IDs for consistency
RUN addgroup -g 1000 -S smb && \
    adduser -u 1000 -S -D -H -h /tmp -s /sbin/nologin -G smb -g 'Samba User' smbuser

# Create necessary directories with proper permissions
RUN mkdir -p /var/lib/samba/private \
             /var/cache/samba \
             /var/log/samba \
             /run/samba && \
    chmod 700 /var/lib/samba/private && \
    chown -R smbuser:smb /var/lib/samba /var/cache/samba /var/log/samba /run/samba

# Copy configuration files from container folder
COPY container/smb.conf.template /etc/samba/smb.conf
COPY container/samba.sh /usr/bin/
COPY container/parse-config.sh /usr/bin/
COPY container/parse-toml-config.sh /usr/bin/

# Make script executable and set ownership
RUN chmod +x /usr/bin/samba.sh /usr/bin/parse-config.sh /usr/bin/parse-toml-config.sh && \
    chmod 644 /etc/samba/smb.conf

# Expose ports
EXPOSE 137/udp 138/udp 139 445

# Health check with proper error handling
HEALTHCHECK --interval=60s --timeout=15s --start-period=10s --retries=3 \
    CMD smbclient -L \\\\localhost -U % -m SMB3 2>/dev/null || exit 1

# Use specific volumes to avoid exposing system directories
VOLUME ["/var/cache/samba", "/var/lib/samba", "/var/log/samba", "/run/samba"]

# Use tini as PID 1 for proper signal handling
ENTRYPOINT ["/sbin/tini", "-g", "--", "/usr/bin/samba.sh"]