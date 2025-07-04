#!/bin/bash
# ============================================================
# ISO Server Bootstrap Script
# ------------------------------------------------------------
# This script automates initial server setup for ISO-managed
# Linux hosts.
#
# Author:     Jason Cihelka (Isotechnics)
# Copyright:  © 2025 Isotechnics Inc. All rights reserved.
# Organization: https://github.com/isotechnics
# ============================================================

set -e

TOKEN_PATH="/etc/iso-github-token"
HOSTNAME=$(hostname)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Try again with sudo."
  exit 1
fi

# ==========================
# GitHub Token Setup
# ==========================
if [[ ! -f "$TOKEN_PATH" ]]; then
  read -rsp "Enter GitHub token (Bitwarden: Github ISO Deploy Key): " GITHUB_TOKEN
  echo ""
  echo "$GITHUB_TOKEN" > "$TOKEN_PATH"
  chmod 600 "$TOKEN_PATH"
  chown root:root "$TOKEN_PATH"
  echo "GitHub token saved to $TOKEN_PATH"
else
  GITHUB_TOKEN=$(< "$TOKEN_PATH")
fi

# ==========================
# Initial Configuration
# ==========================
apt-get update
# required dependencies
apt-get -y install jq 

# Set up iptables-persistent
log "Installing iptables-persistent..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

# extend volume group if not already using all space
log "Extending OS volume group..."
lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv || log "lvextend failed or volume already fully extended"
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv || log "resize2fs failed or unnecessary"

# ==========================
# SSH Config for isoadmin User
# ==========================
SSH_CONFIG_PATH="/home/isoadmin/.ssh/config"
SSH_CONFIG_BLOCK="Host *
  KexAlgorithms +diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
  Ciphers +aes256-cbc,aes128-cbc
  HostkeyAlgorithms +ssh-rsa"

log "Setting up SSH config for isoadmin user..."

# Create .ssh directory if it doesn't exist
if [[ ! -d "/home/isoadmin/.ssh" ]]; then
  mkdir -p "/home/isoadmin/.ssh"
  chown isoadmin:isoadmin "/home/isoadmin/.ssh"
  chmod 700 "/home/isoadmin/.ssh"
  log "Created /home/isoadmin/.ssh directory"
fi

# Check if the SSH config block already exists
if [[ -f "$SSH_CONFIG_PATH" ]] && grep -q "KexAlgorithms +diffie-hellman-group14-sha1" "$SSH_CONFIG_PATH"; then
  log "SSH config block already exists in $SSH_CONFIG_PATH"
else
  # Create or append the SSH config block
  if [[ ! -f "$SSH_CONFIG_PATH" ]]; then
    echo "$SSH_CONFIG_BLOCK" > "$SSH_CONFIG_PATH"
    log "Created new SSH config file with compatibility settings"
  else
    echo "" >> "$SSH_CONFIG_PATH"
    echo "$SSH_CONFIG_BLOCK" >> "$SSH_CONFIG_PATH"
    log "Appended SSH compatibility settings to existing config"
  fi
  
  # Set proper ownership and permissions
  chown isoadmin:isoadmin "$SSH_CONFIG_PATH"
  chmod 600 "$SSH_CONFIG_PATH"
  log "Set proper ownership and permissions on SSH config"
fi

# ==========================
# SSH Auth Key Autoupdate Installation
# ==========================
SSH_AUTOUPDATE_URL="https://raw.githubusercontent.com/isotechnics/ssh-config/refs/heads/main/scripts/authorizedkeys_autoupdate_install.sh"

read -rp "Install SSH authorized_keys auto-update script? (Y/n): " ssh_choice
if [[ "$ssh_choice" =~ ^[Yy]?$ ]]; then
  log "Downloading and executing SSH key auto-update install script..."
  TMP_SSH_SCRIPT=$(mktemp)
  curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" "$SSH_AUTOUPDATE_URL" -o "$TMP_SSH_SCRIPT"
  chmod +x "$TMP_SSH_SCRIPT"
  "$TMP_SSH_SCRIPT"
  rm -f "$TMP_SSH_SCRIPT"
  
  # Disable password authentication if not already disabled
  if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
    log "Disabling password authentication in SSH config..."
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl reload ssh
    log "Password authentication disabled and SSH service reloaded."
  else
    log "Password authentication already disabled in SSH config."
  fi
else
  log "Skipped SSH key auto-update install."
fi

# ==========================
# NMS Agent Installation
# ==========================
NMS_INSTALL_URL="https://raw.githubusercontent.com/isotechnics/iso-nms-agent/refs/heads/master/scripts/install.sh"

read -rp "Install NMS agent? (Y/n): " nms_choice
if [[ "$nms_choice" =~ ^[Yy]?$ ]]; then
  log "Downloading and executing NMS agent install script..."
  TMP_NMS_SCRIPT=$(mktemp)
  curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" "$NMS_INSTALL_URL" -o "$TMP_NMS_SCRIPT"
  chmod +x "$TMP_NMS_SCRIPT"
  "$TMP_NMS_SCRIPT"
  rm -f "$TMP_NMS_SCRIPT"
else
  log "Skipped NMS agent install."
fi

# ==========================
# Backups Installation
# ==========================
BACKUP_INSTALL_URL="https://raw.githubusercontent.com/isotechnics/iso-server-backup/refs/heads/main/scripts/install_iso_server_backup.sh"

read -rp "Install server backup system? (Y/n): " backup_choice
if [[ "$backup_choice" =~ ^[Yy]?$ ]]; then
  log "Downloading and executing backup install script..."
  TMP_BACKUP_SCRIPT=$(mktemp)
  curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" "$BACKUP_INSTALL_URL" -o "$TMP_BACKUP_SCRIPT"
  chmod +x "$TMP_BACKUP_SCRIPT"
  "$TMP_BACKUP_SCRIPT"
  rm -f "$TMP_BACKUP_SCRIPT"
else
  log "Skipped backup system install."
fi
