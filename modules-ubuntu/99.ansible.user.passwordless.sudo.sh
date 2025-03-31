#!/bin/bash

set -euo pipefail

log() {
  echo "[INFO] $1"
}

warn() {
  echo "[WARN] $1"
}

error() {
  echo "[ERROR] $1"
}

{
  # Determine admin group
  if getent group sudo > /dev/null; then
    admin_group="sudo"
  elif getent group wheel > /dev/null; then
    admin_group="wheel"
  else
    warn "No suitable admin group (sudo/wheel) found. Skipping ansible user setup."
    exit 0
  fi

  # Create ansible user if it doesn't exist
  if id "ansible" &>/dev/null; then
    log "User 'ansible' already exists. Skipping user creation."
  else
    useradd -m -s /bin/bash -G "$admin_group" ansible || {
      error "Failed to create user 'ansible'."
      exit 0
    }
  fi

  # Configure passwordless sudo
  SUDOERS_FILE="/etc/sudoers.d/ansible"
  SUDOERS_LINE="ansible ALL=(ALL) NOPASSWD:ALL"

  if [[ -f "$SUDOERS_FILE" ]] && grep -Fxq "$SUDOERS_LINE" "$SUDOERS_FILE"; then
    log "Passwordless sudo already configured for ansible user."
  else
    echo "$SUDOERS_LINE" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
  fi

  # Set up SSH key
  SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK6kq0F66kQIEala1jD+V2y5nN0ks6TSdVBPpFEvQOAE"
  SSH_DIR="/home/ansible/.ssh"
  AUTH_KEYS="$SSH_DIR/authorized_keys"

  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  chown -R ansible:ansible "$SSH_DIR"

  if [[ -f "$AUTH_KEYS" ]] && grep -q "$SSH_KEY" "$AUTH_KEYS"; then
    log "SSH key already present for ansible user. Skipping."
  else
    echo "$SSH_KEY" >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    chown -R ansible:ansible "$SSH_DIR"
  fi
  chown -R ansible:ansible /home/ansible

  log "Ansible user setup completed successfully."

} || {
  warn "An error occurred during ansible user setup. Continuing with instance initialization..."
}
