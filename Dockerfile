# Use latest Alpine version
FROM alpine:latest

# Install dependencies in optimized layers
RUN apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add \
        bash \
        samba \
        shadow \
        tini \
        tzdata && \
    rm -rf /var/cache/apk/* /tmp/*

# Create samba user and group with fixed IDs for consistency
RUN addgroup -g 1000 -S smb && \
    adduser -u 1000 -S -D -H -h /tmp -s /sbin/nologin -G smb -g 'Samba User' smbuser

# Copy configuration files
COPY smb.conf.template /etc/samba/smb.conf
COPY samba.sh /usr/bin/

# Make script executable
RUN chmod +x /usr/bin/samba.sh

EXPOSE 137/udp 138/udp 139 445

HEALTHCHECK --interval=60s --timeout=15s \
    CMD smbclient -L \\localhost -U % -m SMB3

VOLUME ["/etc", "/var/cache/samba", "/var/lib/samba", "/var/log/samba",\
    "/run/samba"]

ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/samba.sh"]