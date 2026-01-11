#!/usr/bin/env bash
#===============================================================================
#          FILE: parse-toml-config.sh
#
#   DESCRIPTION: Parse TOML configuration file for Samba shares
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

parse_toml_config() {
    local config_file="$1"
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
        
        # Remove leading/trailing whitespace
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        
        # Detect share section [shares.ShareName]
        if [[ "$line" =~ ^\[shares\.([a-zA-Z0-9_-]+)\] ]]; then
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
            
        # Parse key = value pairs
        elif [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes from value
            value="${value#\"}"
            value="${value%\"}"
            
            # Convert boolean values
            [[ "$value" == "true" ]] && value="yes"
            [[ "$value" == "false" ]] && value="no"
            
            case "$key" in
                path) share_path="$value" ;;
                username) share_user="$value" ;;
                password) share_pass="$value" ;;
                browsable) share_browsable="$value" ;;
                readonly) share_readonly="$value" ;;
                guest) share_guest="$value" ;;
            esac
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
    parse_toml_config "$1"
fi
