#!/bin/bash

# OLS Config Persistence - Installer & Uninstaller
# Version: 1.0
#
# By: Abdelrahman Abdeen
# Contact: me@abdeen.one
#
# Description: Manages the installation and uninstallation of the OpenLiteSpeed
# configuration persistence system.
#
# DISCLAIMER: This script is provided "as-is" without any warranty. Use at your own risk.
# Always test in a development environment first.

# --- Configuration ---
SCRIPT_VERSION="1.0"
# Unified names for script and service
MONITOR_SCRIPT_NAME="ols_config_persistence.sh"
SERVICE_NAME="ols-config-persistence"

# Paths
SCRIPT_PATH="/root/$MONITOR_SCRIPT_NAME"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CUSTOM_CONFIG_FILE="/root/ols_custom_config.txt"
DEFAULT_OLS_CONFIG="/usr/local/lsws/conf/httpd_config.conf"
HELPER_COMMAND_PATH="/usr/local/bin/ols-persistence-info"
CHECKSUM_FILE="/root/.ols_custom_config.checksum"
LOG_FILE="/var/log/ols_monitor.log"
BACKUP_DIR="/root/ols_backups"

# Other
CRON_COMMENT="OLS Config Persistence"
OLS_CONFIG_FILE="" # Determined during installation

# --- Shell Output Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# --- Helper Functions ---
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root."
        exit 1
    fi
}

show_usage() {
    echo "OLS Config Persistence Manager - Version $SCRIPT_VERSION"
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  (no command)    Run the interactive installer."
    echo "  uninstall       Remove the entire persistence system."
    echo "  help            Show this usage message."
    echo
}

# --- Installer Functions ---

print_install_header() {
    echo -e "${PURPLE}"
    echo "============================================================"
    echo "  OLS Config Persistence Setup - Version $SCRIPT_VERSION"
    echo "  By Abdelrahman Abdeen (me@abdeen.one)"
    echo "============================================================"
    echo -e "${NC}"
    echo -e "${YELLOW}DISCLAIMER: This software is provided 'as-is' without warranty."
    echo -e "Use at your own risk. Test in development environment first.${NC}"
    echo
}

get_ols_config_path() {
    echo -e "${BLUE}OpenLiteSpeed Configuration Path:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "Default path: ${YELLOW}$DEFAULT_OLS_CONFIG${NC}"
    echo
    
    if [[ -f "$DEFAULT_OLS_CONFIG" ]]; then
        print_success "Default OLS configuration found"
        read -p "Use default path? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            read -p "Enter custom OLS config path: " OLS_CONFIG_FILE
        else
            OLS_CONFIG_FILE="$DEFAULT_OLS_CONFIG"
        fi
    else
        print_warning "Default OLS configuration not found"
        read -p "Enter OLS config path: " OLS_CONFIG_FILE
    fi
    
    if [[ ! -f "$OLS_CONFIG_FILE" ]]; then
        print_error "OLS configuration file not found at: $OLS_CONFIG_FILE"
        print_error "Please verify the path and ensure OpenLiteSpeed is installed"
        exit 1
    fi
    
    print_success "Using OLS configuration: $OLS_CONFIG_FILE"
    echo
}

install_dependencies() {
    print_status "Installing required system dependencies..."
    
    if command -v apt-get >/dev/null; then
        apt-get update -qq
        apt-get install -y inotify-tools cron
    elif command -v yum >/dev/null; then
        yum install -y inotify-tools cronie
    elif command -v dnf >/dev/null; then
        dnf install -y inotify-tools cronie
    else
        print_error "Unsupported package manager detected"
        print_error "Please install inotify-tools and cron manually and retry"
        exit 1
    fi
    
    print_success "System dependencies installed successfully"
}

create_monitor_script() {
    print_status "Creating OLS configuration monitor script..."
    
    cat > "$SCRIPT_PATH" << EOF
#!/bin/bash

# OLS Config Persistence Monitor
# Version: 1.0 | By Abdelrahman Abdeen
# Description: Monitors and reapplies custom OpenLiteSpeed settings.

set -e

# These variables are populated by the installer
OLS_CONFIG_FILE="$OLS_CONFIG_FILE"
CUSTOM_CONFIG_FILE="$CUSTOM_CONFIG_FILE"
CHECKSUM_FILE="$CHECKSUM_FILE"
BACKUP_DIR="$BACKUP_DIR"
LOG_FILE="$LOG_FILE"
BACKUP_RETENTION_DAYS=30

mkdir -p "\$BACKUP_DIR"
touch "\$LOG_FILE"

log_message() {
    echo "['\$(date '+%Y-%m-%d %H:%M:%S')'] \$1" | tee -a "\$LOG_FILE"
    
    if [[ \$(wc -l <"\$LOG_FILE") -gt 1000 ]]; then
        tail -n 500 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"
    fi
}

create_backup() {
    local backup_file="\$BACKUP_DIR/httpd_config_\$(date +%Y%m%d_%H%M%S).conf"
    cp "\$OLS_CONFIG_FILE" "\$backup_file"
    log_message "Configuration backup created: \$(basename "\$backup_file")"
    find "\$BACKUP_DIR" -name "httpd_config_*.conf" -mtime +\$BACKUP_RETENTION_DAYS -delete 2>/dev/null
}

restart_ols() {
    log_message "Performing graceful OLS restart..."
    if command -v systemctl >/dev/null && systemctl is-active --quiet lsws; then
        systemctl reload lsws 2>/dev/null || systemctl restart lsws
    elif [[ -f "/usr/local/lsws/bin/lswsctrl" ]]; then
        /usr/local/lsws/bin/lswsctrl graceful 2>/dev/null || /usr/local/lsws/bin/lswsctrl restart
    else
        log_message "WARNING: No restart method found. Could not apply changes."
    fi
}

apply_custom_config() {
    if ! grep -q '^[^#]' "\$CUSTOM_CONFIG_FILE" 2>/dev/null; then
        if grep -q "# CUSTOM_OLS_CONFIG_START" "\$OLS_CONFIG_FILE"; then
            log_message "Custom config is empty. Removing existing blocks from OLS config."
            create_backup
            sed -i '/# CUSTOM_OLS_CONFIG_START/,/# CUSTOM_OLS_CONFIG_END/d' "\$OLS_CONFIG_FILE"
            restart_ols
        fi
        rm -f "\$CHECKSUM_FILE"
        return 0
    fi
    
    create_backup
    sed -i '/# CUSTOM_OLS_CONFIG_START/,/# CUSTOM_OLS_CONFIG_END/d' "\$OLS_CONFIG_FILE"

    TMP_BLOCK=\$(mktemp)
    echo "# CUSTOM_OLS_CONFIG_START - Maintained by Persistence Script" > "\$TMP_BLOCK"
    cat "\$CUSTOM_CONFIG_FILE" >> "\$TMP_BLOCK"
    echo "# CUSTOM_OLS_CONFIG_END" >> "\$TMP_BLOCK"
    
    TMP_OLS_CONFIG=\$(mktemp)
    
    cat "\$TMP_BLOCK" > "\$TMP_OLS_CONFIG"
    echo "" >> "\$TMP_OLS_CONFIG"
    cat "\$OLS_CONFIG_FILE" >> "\$TMP_OLS_CONFIG"
    echo "" >> "\$TMP_OLS_CONFIG"
    cat "\$TMP_BLOCK" >> "\$TMP_OLS_CONFIG"
    
    mv "\$TMP_OLS_CONFIG" "\$OLS_CONFIG_FILE"
    rm -f "\$TMP_BLOCK"
    
    log_message "Custom configuration applied (prepended and appended)."
    
    sha256sum "\$CUSTOM_CONFIG_FILE" | awk '{print \$1}' > "\$CHECKSUM_FILE"
    restart_ols
}

check_and_apply_changes() {
    local source="\$1"
    log_message "Verifying configuration (source: \$source)."
    
    local apply_needed=false
    local apply_reason=""
    
    local has_content=false
    if grep -q '^[^#]' "\$CUSTOM_CONFIG_FILE" 2>/dev/null; then
        has_content=true
    fi

    if [[ "\$has_content" == true ]] && ! grep -q "# CUSTOM_OLS_CONFIG_START" "\$OLS_CONFIG_FILE"; then
        apply_needed=true
        apply_reason="Custom block is missing from OLS config."
    elif [[ "\$has_content" == false ]] && grep -q "# CUSTOM_OLS_CONFIG_START" "\$OLS_CONFIG_FILE"; then
        apply_needed=true
        apply_reason="OLS config contains a block that should be removed."
    fi
    
    if [[ "\$apply_needed" == false ]] && [[ "\$has_content" == true ]]; then
        desired_checksum=\$(sha256sum "\$CUSTOM_CONFIG_FILE" | awk '{print \$1}')
        applied_content=\$(sed -n '/# CUSTOM_OLS_CONFIG_START/,/# CUSTOM_OLS_CONFIG_END/{//!p;}; /# CUSTOM_OLS_CONFIG_END/q' "\$OLS_CONFIG_FILE")
        applied_checksum=\$(echo -n "\$applied_content" | sha256sum | awk '{print \$1}')
        
        if [[ "\$desired_checksum" != "\$applied_checksum" ]]; then
            apply_needed=true
            apply_reason="Manual change detected in OLS config block."
        fi
    fi
    
    if [[ "\$apply_needed" == true ]]; then
        log_message "Change required: \$apply_reason Reapplying configuration..."
        apply_custom_config
    else
        log_message "Configuration is up-to-date."
    fi
}

# --- Main Execution Logic ---
if [[ "\$1" == "--apply-now" ]]; then
    check_and_apply_changes "cron"
    exit 0
fi

log_message "Starting real-time monitoring service..."
check_and_apply_changes "service_startup"

while true; do
    inotifywait -e modify,delete_self,move_self,create "\$OLS_CONFIG_FILE" "\$CUSTOM_CONFIG_FILE" 2>/dev/null |
    while read -r directory event file; do
        log_message "File system event '\$event' on '\$file' detected. Waiting 10 seconds before applying..."
        sleep 10
        check_and_apply_changes "inotify"
    done
    log_message "inotify listener restarting..."
    sleep 5
done
EOF
    
    chmod +x "$SCRIPT_PATH"
    print_success "Monitor script created successfully"
}

create_sample_config() {
    if [[ ! -f "$CUSTOM_CONFIG_FILE" ]]; then
        print_status "Creating sample configuration template..."
        
        cat > "$CUSTOM_CONFIG_FILE" << 'EOF'
# Your custom OLS overrides should be here
EOF
        
        print_success "Configuration template created at $CUSTOM_CONFIG_FILE"
        print_warning "Edit $CUSTOM_CONFIG_FILE to add your custom OLS settings"
    else
        print_status "Configuration file already exists at $CUSTOM_CONFIG_FILE"
    fi
}

create_systemd_service() {
    print_status "Creating system service for real-time monitoring..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=OLS Config Persistence Monitor (Real-time)
After=network.target
Wants=lsws.service

[Service]
Type=simple
User=root
ExecStart=$SCRIPT_PATH
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "System service configuration created"
}

setup_cron_job() {
    print_status "Setting up periodic check (cron job)..."
    
    (crontab -l 2>/dev/null | grep -vF "$CRON_COMMENT") | crontab -
    (crontab -l 2>/dev/null; echo "*/3 * * * * bash $SCRIPT_PATH --apply-now &> /dev/null # $CRON_COMMENT") | crontab -
    
    print_success "Cron job for periodic checks configured successfully"
}

create_helper_command() {
    print_status "Creating helper command..."

    cat > "$HELPER_COMMAND_PATH" << EOF
#!/bin/bash
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "\${PURPLE}--- OLS Config Persistence Info ---\${NC}"
echo
echo -e "\${BLUE}System Management Commands:\${NC}"
echo "  Service Status:     systemctl status $SERVICE_NAME"
echo "  View Logs (Live):   tail -f $LOG_FILE"
echo "  Restart Service:    systemctl restart $SERVICE_NAME"
echo "  Apply Manually:     bash $SCRIPT_PATH --apply-now"
echo
echo -e "\${BLUE}File Locations:\${NC}"
echo "  Custom Settings:    $CUSTOM_CONFIG_FILE"
echo "  Monitor Script:     $SCRIPT_PATH"
echo "  Backup Directory:   $BACKUP_DIR/"
echo
EOF
    chmod +x "$HELPER_COMMAND_PATH"
    print_success "Helper command 'ols-persistence-info' is now available."
}

setup_service() {
    print_status "Configuring and starting system service..."
    
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Real-time monitor service started and enabled on boot"
    else
        print_error "Service startup failed. Check: systemctl status $SERVICE_NAME"
        print_error "Also check logs: tail -n 50 $LOG_FILE"
        return 1
    fi
}

test_installation() {
    print_status "Performing installation verification..."
    local all_passed=true

    echo -n "  - Monitor script executable: "
    if [[ -x "$SCRIPT_PATH" ]]; then print_success "Yes"; else print_error "No"; all_passed=false; fi
    
    echo -n "  - System service running:    "
    if systemctl is-active --quiet "$SERVICE_NAME"; then print_success "Yes"; else print_error "No"; all_passed=false; fi

    echo -n "  - Cron job configured:       "
    if crontab -l 2>/dev/null | grep -qF "$CRON_COMMENT"; then print_success "Yes"; else print_error "No"; all_passed=false; fi
    
    echo -n "  - Custom config file exists: "
    if [[ -f "$CUSTOM_CONFIG_FILE" ]]; then print_success "Yes"; else print_error "No"; all_passed=false; fi

    echo -n "  - Helper command installed:  "
    if [[ -x "$HELPER_COMMAND_PATH" ]]; then print_success "Yes"; else print_error "No"; all_passed=false; fi
    
    echo
    if [[ "$all_passed" == true ]]; then
        print_success "Installation verification passed!"
        return 0
    else
        print_warning "Installation completed with some issues. Please review the checks above."
        return 1
    fi
}

show_completion_info() {
    echo
    print_success "OLS Config Persistence installation completed!"
    echo
    echo -e "${BLUE}A command is now available to show important details:${NC}"
    echo "  ols-persistence-info"
    echo
    echo -e "${BLUE}Your next step is to add your custom settings:${NC}"
    echo "  nano $CUSTOM_CONFIG_FILE"
    echo
    print_status "The service is active, and your OLS configuration is now protected."
}

cleanup_on_error() {
    print_error "Installation failed. Performing cleanup..."
    
    systemctl stop "$SERVICE_NAME" &> /dev/null || true
    systemctl disable "$SERVICE_NAME" &> /dev/null || true
    (crontab -l 2>/dev/null | grep -vF "$CRON_COMMENT") | crontab -
    
    rm -f "$SERVICE_FILE" "$SCRIPT_PATH" "$HELPER_COMMAND_PATH" "$CHECKSUM_FILE"
    
    systemctl daemon-reload &> /dev/null || true
    print_error "Cleanup completed. Please check the error messages above."
}


# --- Uninstaller Functions ---

reload_ols_after_cleanup() {
    print_status "Performing graceful OLS reload to apply cleanup..."
    if command -v systemctl >/dev/null && systemctl is-active --quiet lsws; then
        systemctl reload lsws 2>/dev/null || systemctl restart lsws
        print_success "OLS reloaded."
    elif [[ -f "/usr/local/lsws/bin/lswsctrl" ]]; then
        /usr/local/lsws/bin/lswsctrl graceful 2>/dev/null || /usr/local/lsws/bin/lswsctrl restart
        print_success "OLS reloaded."
    else
        print_warning "No OLS restart method found. A manual reload might be needed."
    fi
}

clean_ols_config() {
    local ols_config_path=""
    # Try to find the OLS config path from the monitor script if it exists
    if [[ -f "$SCRIPT_PATH" ]]; then
        ols_config_path=$(grep '^OLS_CONFIG_FILE=' "$SCRIPT_PATH" | cut -d'"' -f2)
    fi

    if [[ -z "$ols_config_path" ]] || [[ ! -f "$ols_config_path" ]]; then
        local prompt_msg="Enter path to OLS config to clean it (or press Enter to skip)"
        if [[ -f "$DEFAULT_OLS_CONFIG" ]]; then
            prompt_msg="Enter path to OLS config (default: $DEFAULT_OLS_CONFIG)"
        fi
        read -p "$prompt_msg: " ols_config_path
        # If user hits enter and default exists, use it
        if [[ -z "$ols_config_path" ]] && [[ -f "$DEFAULT_OLS_CONFIG" ]]; then
            ols_config_path="$DEFAULT_OLS_CONFIG"
        fi
    fi
    
    if [[ -f "$ols_config_path" ]]; then
        print_status "Removing custom config block from $ols_config_path..."
        cp "$ols_config_path" "$ols_config_path.bak-uninst"
        print_status "A backup has been created at $ols_config_path.bak-uninst"
        sed -i '/# CUSTOM_OLS_CONFIG_START/,/# CUSTOM_OLS_CONFIG_END/d' "$ols_config_path"
        print_success "OLS configuration file cleaned."
        # Reload OLS to apply the changes from cleanup
        reload_ols_after_cleanup
    else
        if [[ -n "$ols_config_path" ]]; then # Only show warning if a path was provided
             print_warning "OLS configuration file not found at '$ols_config_path'. Skipping cleanup."
        fi
    fi
}

# --- Main Logic Routines ---

run_install() {
    trap cleanup_on_error ERR
    set -e
    print_install_header
    check_root
    read -p "Do you want to proceed with the installation? (y/N): " -n 1 -r; echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then print_status "Installation cancelled"; exit 0; fi; echo
    get_ols_config_path
    install_dependencies
    create_monitor_script
    create_sample_config
    create_systemd_service
    setup_cron_job
    create_helper_command
    setup_service
    test_installation
    show_completion_info
    trap - ERR
}

run_uninstall() {
    echo -e "${YELLOW}This script will completely remove the OLS Config Persistence system.${NC}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Uninstallation cancelled."
        exit 0
    fi
    echo

    check_root

    print_status "Stopping and disabling systemd service..."
    systemctl stop "$SERVICE_NAME" &>/dev/null || true
    systemctl disable "$SERVICE_NAME" &>/dev/null || true
    print_success "Service stopped and disabled."

    print_status "Removing cron job..."
    (crontab -l 2>/dev/null | grep -vF "$CRON_COMMENT") | crontab -
    print_success "Cron job removed."

    print_status "Removing system files..."
    rm -f "$SERVICE_FILE" "$SCRIPT_PATH" "$HELPER_COMMAND_PATH" "$CHECKSUM_FILE"
    print_success "System files removed."
    
    clean_ols_config

    echo
    print_warning "The following files contain your custom settings, backups, and logs."
    read -p "Do you want to remove the custom config file ($CUSTOM_CONFIG_FILE)? (y/N): " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then rm -f "$CUSTOM_CONFIG_FILE"; print_success "Custom config file removed."; fi
    
    read -p "Do you want to remove ALL backups ($BACKUP_DIR/)? (y/N): " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then rm -rf "$BACKUP_DIR"; print_success "Backup directory removed."; fi

    read -p "Do you want to remove the log file ($LOG_FILE)? (y/N): " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then rm -f "$LOG_FILE"; print_success "Log file removed."; fi

    print_status "Reloading systemd daemon..."
    systemctl daemon-reload &> /dev/null || true
    echo
    print_success "Uninstallation complete."
}

# --- Script Entrypoint ---
main() {
    case "$1" in
        uninstall|--uninstall)
            run_uninstall
            ;;
        help|--help)
            show_usage
            ;;
        *)
            run_install
            ;;
    esac
}

main "$@"

