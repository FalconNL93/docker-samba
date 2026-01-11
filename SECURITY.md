# Security Configuration Guide

## Default Security Settings

This Samba container implements security-first defaults aligned with 2026 best practices:

### 🔒 Core Security Features

1. **SMB3 Only**
   - Minimum protocol: SMB3
   - Older vulnerable protocols (SMB1, SMB2) are disabled
   - Protects against known SMB1 vulnerabilities (e.g., EternalBlue)

2. **Mandatory SMB Signing**
   - Prevents man-in-the-middle attacks
   - Ensures message integrity
   - Both server and client signing enforced

3. **SMB Encryption**
   - Set to "desired" by default (negotiates encryption)
   - Can be set to "required" for maximum security
   - Protects data in transit

4. **No Guest Access**
   - `map to guest = never` (disabled by default)
   - All connections require authentication
   - Reduces attack surface

5. **Restricted Anonymous Access**
   - `restrict anonymous = 2` (maximum restriction)
   - Prevents null session enumeration
   - Blocks anonymous user information disclosure

6. **Symlink Protection**
   - `follow symlinks = no` by default
   - `wide links = no`
   - Prevents directory traversal attacks

7. **No Null Passwords**
   - Empty passwords not allowed
   - Enforces password policy

## Container Security

### Non-Privileged Volumes
- Does NOT expose `/etc` directory
- Limited to Samba-specific paths only
- Reduces container escape risks

### Proper Signal Handling
- Uses `tini` as PID 1
- Graceful shutdown on SIGTERM
- Prevents zombie processes

### Minimal Attack Surface
- Alpine Linux base (small footprint)
- Only essential packages installed
- Regular security updates via `apk upgrade`

### File Permissions
- `/var/lib/samba/private` set to 700
- Samba databases protected
- User/group isolation

## Security Best Practices

### 1. Use Strong Passwords
```bash
# Minimum 12 characters, mix of types
docker-compose run samba -u "user;$(openssl rand -base64 16)"
```

### 2. Enable Audit Logging
Uncomment in `smb.conf.template`:
```ini
vfs objects = full_audit catia fruit recycle streams_xattr
full_audit:prefix = %u|%I|%m|%S
full_audit:success = mkdir rmdir read pread write pwrite rename unlink
full_audit:failure = connect
```

### 3. Require SMB Encryption
In `smb.conf.template`, change:
```ini
server smb encrypt = required
```

### 4. Enable Guest Access Per-Share Only
If you need guest access, enable it per-share, not globally:
```bash
docker-compose run samba -s "PublicShare;/path;yes;yes;yes"
#                                              # ^ guest ok = yes
```

### 5. Use Read-Only Shares When Possible
```bash
docker-compose run samba -s "Docs;/docs;yes;yes;no"
#                                         # ^ readonly = yes
```

### 6. Implement Network Segmentation
- Run Samba on isolated network
- Use firewall rules
- Limit access to trusted IPs

### 7. Regular Updates
```bash
# Rebuild with latest packages
docker-compose build --no-cache
docker-compose up -d
```

### 8. Monitor Logs
```bash
docker-compose logs -f samba
```

### 9. Use Docker Security Options
Already configured in `docker-compose.yml`:
- `read_only: true` - Immutable filesystem
- `cap_drop: ALL` - Drop all capabilities
- `cap_add: [minimal set]` - Only required capabilities
- `no-new-privileges` - Prevents privilege escalation
- Resource limits - Prevent DoS

### 10. Backup Password Database
```bash
docker cp samba:/var/lib/samba/private/passdb.tdb ./backup/
```

## Compliance & Standards

### CIS Benchmarks
- Principle of least privilege
- Secure defaults
- Defense in depth

### NIST Guidelines
- Strong cryptography (SMB3)
- Access control (authentication required)
- Audit logging (optional, configurable)

### GDPR Considerations
- Data encryption in transit
- Access logging
- Secure data storage

## Threat Model

### Mitigated Threats
✅ SMB1 vulnerabilities (CVE-2017-0144, etc.)
✅ Man-in-the-middle attacks (signing)
✅ Eavesdropping (encryption)
✅ Anonymous enumeration (restrict anonymous)
✅ Directory traversal (symlink protection)
✅ Privilege escalation (container hardening)
✅ Null session attacks
✅ Password spray attacks (strong passwords)

### Residual Risks
⚠️ Brute force attacks (implement rate limiting externally)
⚠️ Compromised credentials (use key-based auth if possible)
⚠️ Zero-day vulnerabilities (keep updated)
⚠️ Docker daemon compromise (secure Docker host)

## Security Checklist

Before deploying to production:

- [ ] Changed default passwords
- [ ] Reviewed and limited share permissions
- [ ] Enabled audit logging if required
- [ ] Configured firewall rules
- [ ] Set appropriate resource limits
- [ ] Tested backup/restore procedures
- [ ] Reviewed logs for anomalies
- [ ] Updated to latest container version
- [ ] Documented access policies
- [ ] Trained users on secure access

## Incident Response

### Suspected Compromise
1. Stop container immediately: `docker-compose down`
2. Preserve logs: `docker-compose logs > incident.log`
3. Analyze logs for suspicious activity
4. Reset all passwords
5. Rebuild container from scratch
6. Review and tighten security settings

### Performance Issues (Potential DoS)
1. Check resource usage: `docker stats samba`
2. Review connection logs
3. Implement rate limiting at network level
4. Adjust resource limits in docker-compose.yml

## Additional Resources

- [Samba Security Documentation](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html#SERVERSIGNING)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [SMB3 Encryption](https://wiki.samba.org/index.php/SMB3_kernel_status#SMB3_Encryption)

## Support & Reporting

For security issues, please:
1. DO NOT open public GitHub issues
2. Contact maintainer directly
3. Allow time for patch before disclosure
4. Follow responsible disclosure practices
