#!/usr/bin/env bash
#===============================================================================
#          FILE: samba.sh
#
#         USAGE: ./samba.sh
#
#   DESCRIPTION: Entrypoint for samba docker container
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: David Personette (dperson@gmail.com),
#  ORGANIZATION:
#       CREATED: 09/28/2014 12:11
#      REVISION: 1.0
#===============================================================================

set -o nounset                              # Treat unset variables as an error
set -o errexit                              # Exit on error
set -o pipefail                             # Catch errors in pipes

# Logging helper
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }

# Security: Sanitize input to prevent injection attacks
sanitize_path() {
    local path="$1"
    # Remove any path traversal attempts
    path="${path//..\/}"
    path="${path//..\\}"
    # Remove null bytes
    path="${path//$'\0'/}"
    # Remove leading/trailing whitespace
    path="$(echo "$path" | xargs)"
    echo "$path"
}

# Security: Validate share name (alphanumeric, spaces, hyphens, underscores only)
validate_share_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9\ _-]+$ ]]; then
        log "ERROR: Invalid share name '$name'. Only alphanumeric, spaces, hyphens, and underscores allowed."
        return 1
    fi
    return 0
}

# Security: Validate username (alphanumeric, hyphens, underscores only)
validate_username() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log "ERROR: Invalid username '$name'. Only alphanumeric, hyphens, and underscores allowed."
        return 1
    fi
    if [[ ${#name} -lt 3 || ${#name} -gt 32 ]]; then
        log "ERROR: Username must be between 3 and 32 characters."
        return 1
    fi
    return 0
}

# Security: Validate password strength
validate_password() {
    local pass="$1"
    if [[ ${#pass} -lt 8 ]]; then
        log "WARNING: Password is less than 8 characters. Consider using a stronger password."
        return 0  # Warning only, not enforced
    fi
    return 0
}

### charmap: setup character mapping for file/directory names
# Arguments:
#   chars) from:to character mappings separated by ','
# Return: configured character mapings
charmap() { 
    local chars="$1" file=/etc/samba/smb.conf
    [[ -z "${chars:-}" ]] && { log "ERROR: charmap requires character mappings"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    grep -q catia "$file" || sed -i '/TCP_NODELAY/a \
\
    vfs objects = catia\
    catia:mappings =\

                ' "$file"

    sed -i '/catia:mappings/s| =.*| = '"$chars"'|' "$file"
}

### generic: set a generic config option in a section
# Arguments:
#   section) section of config file
#   option) raw option
# Return: line added to smb.conf (replaces existing line with same key)
generic() { 
    local section="$1" key value file=/etc/samba/smb.conf
    [[ -z "${section:-}" ]] && { log "ERROR: generic requires section name"; return 1; }
    [[ -z "${2:-}" ]] && { log "ERROR: generic requires option"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    local option="$2"
    key="${option%% =*}"
    value="${option#*= }"
    value="${value# }"
    
    if sed -n '/^\['"$section"'\]/,/^\[/p' "$file" | grep -qE '^;*\s*'"$key"; then
        sed -i '/^\['"$1"'\]/,/^\[/s|^;*\s*\('"$key"' = \).*|   \1'"$value"'|' \
                    "$file"
    else
        sed -i '/\['"$section"'\]/a \   '"$key = $value" "$file"
    fi
}

### global: set a global config option
# Arguments:
#   option) raw option
# Return: line added to smb.conf (replaces existing line with same key)
global() { 
    local key value file=/etc/samba/smb.conf
    [[ -z "${1:-}" ]] && { log "ERROR: global requires option"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    local option="$1"
    key="${option%% =*}"
    value="${option#*= }"
    value="${value# }"
    
    if sed -n '/^\[global\]/,/^\[/p' "$file" | grep -qE '^;*\s*'"$key"; then
        sed -i '/^\[global\]/,/^\[/s|^;*\s*\('"$key"' = \).*|   \1'"$value"'|' \
                    "$file"
    else
        sed -i '/\[global\]/a \   '"$key = $value" "$file"
    fi
}

### include: add a samba config file include
# Arguments:
#   file) file to import
include() { 
    local includefile="$1" file=/etc/samba/smb.conf
    [[ -z "${includefile:-}" ]] && { log "ERROR: include requires file path"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    sed -i "\\|include = $includefile|d" "$file"
    echo "include = $includefile" >> "$file"
}

### import: import a smbpasswd file
# Arguments:
#   file) file to import
# Return: user(s) added to container
import() { 
    local file="$1" name id
    [[ -z "${file:-}" ]] && { log "ERROR: import requires file path"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Import file $file not found"; return 1; }
    
    while read -r name id; do
        grep -q "^$name:" /etc/passwd || adduser -D -H -u "$id" "$name"
    done < <(cut -d: -f1,2 "$file" | sed 's/:/ /')
    pdbedit -i smbpasswd:"$file"
}

### perms: fix ownership and permissions of share paths
# Arguments:
#   none)
# Return: result
perms() { 
    local i file=/etc/samba/smb.conf
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    while IFS= read -r i; do
        [[ -e "$i" ]] || continue
        log "Setting permissions on: $i"
        chown -Rh smbuser. "$i" 2>/dev/null || true
        find "$i" -type d ! -perm 775 -exec chmod 775 {} \; 2>/dev/null || true
        find "$i" -type f ! -perm 0664 -exec chmod 0664 {} \; 2>/dev/null || true
    done < <(awk -F ' = ' '/   path = / {print $2}' "$file")
}
export -f perms

### recycle: disable recycle bin
# Arguments:
#   none)
# Return: result
recycle() { 
    local file=/etc/samba/smb.conf
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    sed -i '/recycle:/d; /vfs objects/s/ recycle / /' "$file"
}

### share: Add share
# Arguments:
#   share) share name
#   path) path to share
#   browsable) 'yes' or 'no'
#   readonly) 'yes' or 'no'
#   guest) 'yes' or 'no'
#   users) list of allowed users
#   admins) list of admin users
#   writelist) list of users that can write to a RO share
#   comment) description of share
# Return: result
share() { 
    local share="$1" path="$2" browsable="${3:-yes}" ro="${4:-yes}" \
                guest="${5:-no}" users="${6:-""}" admins="${7:-""}" \
                writelist="${8:-""}" comment="${9:-""}" file=/etc/samba/smb.conf
    
    [[ -z "${share:-}" ]] && { log "ERROR: share requires share name"; return 1; }
    [[ -z "${path:-}" ]] && { log "ERROR: share requires path"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    # Security: Validate share name
    validate_share_name "$share" || return 1
    
    # Security: Sanitize and validate path
    path="$(sanitize_path "$path")"
    [[ "$path" == /* ]] || { log "ERROR: Path must be absolute"; return 1; }
    
    # Security: Warn about guest access
    if [[ "$guest" == "yes" ]]; then
        log "WARNING: Guest access enabled for share '$share'. This reduces security."
    fi
    
    log "Configuring share: $share at $path"
    sed -i "/\\[$share\\]/,/^\$/d" "$file"
    
    {
        echo "[$share]"
        echo "   path = $path"
        echo "   browsable = $browsable"
        echo "   read only = $ro"
        echo "   guest ok = $guest"
        
        if [[ ${VETO:-yes} != no ]]; then
            echo -n "   veto files = /.apdisk/.DS_Store/.TemporaryItems/"
            echo -n ".Trashes/desktop.ini/ehthumbs.db/Network Trash Folder/"
            echo "Temporary Items/Thumbs.db/"
            echo "   delete veto files = yes"
        fi
        
        [[ ${users:-""} && ! ${users:-""} == all ]] &&
            echo "   valid users = ${users//,/ }"
        [[ ${admins:-""} && ! ${admins:-""} =~ none ]] &&
            echo "   admin users = ${admins//,/ }"
        [[ ${writelist:-""} && ! ${writelist:-""} =~ none ]] &&
            echo "   write list = ${writelist//,/ }"
        [[ ${comment:-""} && ! ${comment:-""} =~ none ]] &&
            echo "   comment = ${comment//,/ }"
        echo ""
    } >> "$file"
    
    [[ -d "$path" ]] || mkdir -p "$path"
}

### smb: disable SMB2 minimum (NOT RECOMMENDED - Security Risk!)
# Arguments:
#   none)
# Return: result
smb() { 
    local file=/etc/samba/smb.conf
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    log "WARNING: Disabling SMB2/3 minimum is a SECURITY RISK! SMB1 has known vulnerabilities."
    log "WARNING: Only use this for legacy systems that absolutely require it."
    sed -i 's/\([^#]*min protocol *=\).*/\1 LANMAN1/' "$file"
}

### user: add a user
# Arguments:
#   name) for user
#   password) for user
#   id) for user
#   group) for user
#   gid) for group
# Return: user added to container
user() { 
    local name="$1" passwd="$2" id="${3:-""}" group="${4:-""}" \
                gid="${5:-""}"
    
    [[ -z "${name:-}" ]] && { log "ERROR: user requires username"; return 1; }
    [[ -z "${passwd:-}" ]] && { log "ERROR: user requires password"; return 1; }
    
    # Security: Validate username
    validate_username "$name" || return 1
    
    # Security: Validate password
    validate_password "$passwd"
    
    log "Adding user: $name"
    [[ "$group" ]] && { grep -q "^$group:" /etc/group ||
                addgroup ${gid:+--gid "$gid" }"$group"; }
    grep -q "^$name:" /etc/passwd ||
        adduser -D -H ${group:+-G "$group"} ${id:+-u "$id"} "$name"
    echo -e "$passwd\n$passwd" | smbpasswd -s -a "$name"
}

### workgroup: set the workgroup
# Arguments:
#   workgroup) the name to set
# Return: configure the correct workgroup
workgroup() { 
    local workgroup="$1" file=/etc/samba/smb.conf
    [[ -z "${workgroup:-}" ]] && { log "ERROR: workgroup requires workgroup name"; return 1; }
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    sed -i 's|^\( *workgroup = \).*|\1'"$workgroup"'|' "$file"
}

### widelinks: allow access wide symbolic links
# Arguments:
#   none)
# Return: result
widelinks() { 
    local file=/etc/samba/smb.conf
    local replace='\1\n   wide links = yes\n   unix extensions = no'
    [[ ! -f "$file" ]] && { log "ERROR: Config file $file not found"; return 1; }
    
    sed -i 's/\(follow symlinks = yes\)/'"$replace"'/' "$file"
}

### usage: Help
# Arguments:
#   none)
# Return: Help text
usage() { local RC="${1:-0}"
    echo "Usage: ${0##*/} [-opt] [command]
Options (fields in '[]' are optional, '<>' are required):
    -h          This help
    -c \"<from:to>\" setup character mapping for file/directory names
                required arg: \"<from:to>\" character mappings separated by ','
    -G \"<section;parameter>\" Provide generic section option for smb.conf
                required arg: \"<section>\" - IE: \"share\"
                required arg: \"<parameter>\" - IE: \"log level = 2\"
    -g \"<parameter>\" Provide global option for smb.conf
                required arg: \"<parameter>\" - IE: \"log level = 2\"
    -i \"<path>\" Import smbpassword
                required arg: \"<path>\" - full file path in container
    -n          Start the 'nmbd' daemon to advertise the shares
    -p          Set ownership and permissions on the shares
    -r          Disable recycle bin for shares
    -S          Disable SMB2 minimum version
    -s \"<name;/path>[;browse;readonly;guest;users;admins;writelist;comment]\"
                Configure a share
                required arg: \"<name>;</path>\"
                <name> is how it's called for clients
                <path> path to share
                NOTE: for the default value, just leave blank
                [browsable] default:'yes' or 'no'
                [readonly] default:'yes' or 'no'
                [guest] allowed default:'yes' or 'no'
                NOTE: for user lists below, usernames are separated by ','
                [users] allowed default:'all' or list of allowed users
                [admins] allowed default:'none' or list of admin users
                [writelist] list of users that can write to a RO share
                [comment] description of share
    -u \"<username;password>[;ID;group;GID]\"       Add a user
                required arg: \"<username>;<passwd>\"
                <username> for user
                <password> for user
                [ID] for user
                [group] for user
                [GID] for group
    -w \"<workgroup>\"       Configure the workgroup (domain) samba should use
                required arg: \"<workgroup>\"
                <workgroup> for samba
    -W          Allow access wide symbolic links
    -I          Add an include option at the end of the smb.conf
                required arg: \"<include file path>\"
                <include file path> in the container, e.g. a bind mount

The 'command' (if provided and valid) will be run instead of samba

Environment variables:
    CONFIG_FILE - Path to configuration file (see shares.conf.example)
" >&2
    exit $RC
}

# Check for configuration file first
if [[ -n "${CONFIG_FILE:-}" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from: $CONFIG_FILE"
        # Auto-detect format based on file extension or content
        if [[ "$CONFIG_FILE" =~ \.toml$ ]] || grep -q '^\[shares\.' "$CONFIG_FILE" 2>/dev/null; then
            log "Detected TOML format"
            mapfile -t config_args < <(/usr/bin/parse-toml-config.sh "$CONFIG_FILE")
        else
            log "Detected YAML format"
            mapfile -t config_args < <(/usr/bin/parse-config.sh "$CONFIG_FILE")
        fi
        # Prepend config args to existing arguments
        set -- "${config_args[@]}" "$@"
    else
        log "ERROR: CONFIG_FILE specified but not found: $CONFIG_FILE"
        exit 1
    fi
fi

[[ "${USERID:-""}" =~ ^[0-9]+$ ]] && usermod -u "$USERID" -o smbuser
[[ "${GROUPID:-""}" =~ ^[0-9]+$ ]] && groupmod -g "$GROUPID" -o smb

while getopts ":hc:G:g:i:nprs:Su:Ww:I:" opt; do
    case "$opt" in
        h) usage ;;
        c) charmap "$OPTARG" ;;
        G) eval "generic $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< "$OPTARG")" ;;
        g) global "$OPTARG" ;;
        i) import "$OPTARG" ;;
        n) NMBD="true" ;;
        p) PERMISSIONS="true" ;;
        r) recycle ;;
        s) eval "share $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< "$OPTARG")" ;;
        S) smb ;;
        u) eval "user $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< "$OPTARG")" ;;
        w) workgroup "$OPTARG" ;;
        W) widelinks ;;
        I) include "$OPTARG" ;;
        "?") echo "Unknown option: -$OPTARG"; usage 1 ;;
        ":") echo "No argument value for option: -$OPTARG"; usage 2 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ "${CHARMAP:-""}" ]] && charmap "$CHARMAP"
while read -r i; do
    eval "generic $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< "$i")"
done < <(env | awk '/^GENERIC[0-9=_]/ {sub (/^[^=]*=/, "", $0); print}')
while read -r i; do
    global "$i"
done < <(env | awk '/^GLOBAL[0-9=_]/ {sub (/^[^=]*=/, "", $0); print}')
[[ "${IMPORT:-""}" ]] && import "$IMPORT"
[[ "${RECYCLE:-""}" ]] && recycle
while read -r i; do
    eval "share $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< "$i")"
done < <(env | awk '/^SHARE[0-9=_]/ {sub (/^[^=]*=/, "", $0); print}')
[[ "${SMB:-""}" ]] && smb
while read -r i; do
    eval "user $(sed 's/^/"/; s/$/"/; s/;/" "/g' <<< "$i")"
done < <(env | awk '/^USER[0-9=_]/ {sub (/^[^=]*=/, "", $0); print}')
[[ "${WORKGROUP:-""}" ]] && workgroup "$WORKGROUP"
[[ "${WIDELINKS:-""}" ]] && widelinks
[[ "${INCLUDE:-""}" ]] && include "$INCLUDE"

# Run permissions fix in background but track the PID
if [[ "${PERMISSIONS:-""}" ]]; then
    log "Starting permissions fix in background"
    perms &
    PERMS_PID=$!
fi

# Cleanup function
cleanup() {
    log "Shutting down..."
    [[ -n "${PERMS_PID:-}" ]] && kill -TERM "$PERMS_PID" 2>/dev/null || true
    [[ -n "${NMBD_PID:-}" ]] && kill -TERM "$NMBD_PID" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

if [[ $# -ge 1 ]] && command -v "$1" >/dev/null 2>&1 && [[ -x "$(command -v "$1")" ]]; then
    log "Executing command: $*"
    exec "$@"
elif [[ $# -ge 1 ]]; then
    log "ERROR: command not found: $1"
    exit 13
elif pgrep -x smbd >/dev/null 2>&1; then
    log "Service already running, please restart container to apply changes"
    exit 0
else
    if [[ ${NMBD:-""} ]]; then
        log "Starting nmbd daemon"
        ionice -c 3 nmbd -D
        NMBD_PID=$!
    fi
    
    log "Starting smbd daemon"
    exec ionice -c 3 smbd -F --debug-stdout --no-process-group </dev/null
fi