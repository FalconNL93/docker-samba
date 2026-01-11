#!/usr/bin/env bash
#===============================================================================
#          FILE: parse-config.sh
#
#   DESCRIPTION: Parse YAML configuration file for Samba shares
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

parse_config() {
    local config_file="$1"
    local in_shares=false
    local current_share=""
    local share_path=""
    local share_user=""
    local share_pass=""
    local share_browsable="yes"
    local share_readonly="no"
    local share_guest="no"
    
    [[ ! -f "$config_file" ]] && { echo "ERROR: Config file not found: $config_file" >&2; return 1; }
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Count leading spaces for indent detection
        local spaces="${line%%[^[:space:]]*}"
        local current_indent=${#spaces}
        
        # Remove leading/trailing whitespace
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        
        # Detect shares section
        if [[ "$line" == "shares:" ]]; then
            in_shares=true
            continue
        fi
        
        if [[ "$in_shares" == true ]]; then
            # Detect share name (2-space indent)
            if [[ $current_indent -eq 2 && "$line" =~ ^([a-zA-Z0-9_-]+): ]]; then
                # Process previous share if exists
                if [[ -n "$current_share" && -n "$share_path" && -n "$share_user" && -n "$share_pass" ]]; then
                    echo "-u \"$share_user;$share_pass\""
                    echo "-s \"$current_share;$share_path;$share_browsable;$share_readonly;$share_guest;$share_user\""
                fi
                
                # Start new share
                current_share="${BASH_REMATCH[1]}"
                share_path=""
                share_user=""
                share_pass=""
                share_browsable="yes"
                share_readonly="no"
                share_guest="no"
                
            # Parse share properties (4-space indent)
            elif [[ $current_indent -eq 4 && "$line" =~ ^([a-z_]+):[[:space:]]*(.+)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                case "$key" in
                    path) share_path="$value" ;;
                    username) share_user="$value" ;;
                    password) share_pass="$value" ;;
                    browsable) share_browsable="$value" ;;
                    readonly) share_readonly="$value" ;;
                    guest) share_guest="$value" ;;
                esac
            fi
        fi
    done < "$config_file"
    
    # Process last share
    if [[ -n "$current_share" && -n "$share_path" && -n "$share_user" && -n "$share_pass" ]]; then
        echo "-u \"$share_user;$share_pass\""
        echo "-s \"$current_share;$share_path;$share_browsable;$share_readonly;$share_guest;$share_user\""
    fi
}

# If called directly, parse the config
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ $# -eq 0 ]] && { echo "Usage: $0 <config-file>" >&2; exit 1; }
    parse_config "$1"
fi
