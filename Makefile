# =============================================================
#  Makefile — single entry point
#
#  Usage:        make help
#  Multi-server: make sync-users SERVER=edge-02
#  Requirements: terraform, ansible, python3
# =============================================================

SHELL         := /bin/bash
.DEFAULT_GOAL := help

TF_DIR        := terraform
ANSIBLE_DIR   := ansible
INVENTORY     := $(ANSIBLE_DIR)/inventory/hosts.yml
SCRIPTS_DIR   := scripts

# Server targeting (optional): make install SERVER=edge-02
SERVER        ?=
LIMIT         := $(if $(SERVER),--limit $(SERVER),)

# Colors
CYAN   := \033[0;36m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
BOLD   := \033[1m
NC     := \033[0m

.PHONY: help \
        init plan apply destroy destroy-all output \
        inventory wait-ssh \
        install sync-users status rotate-keys rotate-warp logs \
        deploy ssh \
        backup-server pause-server resume-server \
        check-deps check-whitelist update-whitelist

# =============================================================
#  Help
# =============================================================

help: ## Show all commands
	@echo ""
	@echo -e "  $(CYAN)$(BOLD)Xray VLESS+Reality Infrastructure$(NC)"
	@echo -e "  $(YELLOW)Multi-server: add SERVER=edge-02 to any command$(NC)"
	@echo ""
	@echo -e "  $(GREEN)Infrastructure (Terraform):$(NC)"
	@echo -e "    make $(BOLD)init$(NC)          Initialize Terraform (first run)"
	@echo -e "    make $(BOLD)plan$(NC)          Show change plan"
	@echo -e "    make $(BOLD)apply$(NC)         Create / update infrastructure in YC"
	@echo -e "    make $(BOLD)destroy$(NC)       ⚠️  Delete VM and network (IP preserved)"
	@echo -e "    make $(BOLD)destroy-all$(NC)   ⚠️  Delete EVERYTHING including IP"
	@echo -e "    make $(BOLD)output$(NC)        Show Terraform outputs"
	@echo ""
	@echo -e "  $(GREEN)Configuration (Ansible):$(NC)"
	@echo -e "    make $(BOLD)install$(NC)       Full server installation"
	@echo -e "    make $(BOLD)sync-users$(NC)    Sync users from vars/users.yml"
	@echo -e "    make $(BOLD)show-users$(NC)    Show subscription links"
	@echo -e "    make $(BOLD)show-qr$(NC)       Show links + QR codes (PNG)"
	@echo -e "    make $(BOLD)status$(NC)        Check status of all servers"
	@echo -e "    make $(BOLD)rotate-keys$(NC)   Rotate Reality keys"
	@echo -e "    make $(BOLD)rotate-warp$(NC)   Re-register WARP credentials"
	@echo -e "    make $(BOLD)logs$(NC)          Show Xray logs"
	@echo ""
	@echo -e "  $(GREEN)Pause / Resume (save costs):$(NC)"
	@echo -e "    make $(BOLD)backup-server$(NC) Backup secrets to data/backups/{server}/"
	@echo -e "    make $(BOLD)pause-server$(NC)  Backup + destroy VM (IP preserved, ~130 RUB/mo)"
	@echo -e "    make $(BOLD)resume-server$(NC) Recreate VM + restore secrets + install"
	@echo ""
	@echo -e "  $(GREEN)Combined:$(NC)"
	@echo -e "    make $(BOLD)deploy$(NC)        Full deploy: Terraform + Ansible"
	@echo -e "    make $(BOLD)ssh$(NC)           SSH connection to server"
	@echo ""
	@echo -e "  $(GREEN)Utilities:$(NC)"
	@echo -e "    make $(BOLD)check-deps$(NC)    Check that all utilities are installed"
	@echo -e "    make $(BOLD)check-whitelist$(NC) Check IP against whitelists"
	@echo -e "    make $(BOLD)update-whitelist$(NC) Update whitelists from GitHub"
	@echo ""
	@echo -e "  $(GREEN)Examples:$(NC)"
	@echo -e "    make deploy                     # deploy all servers"
	@echo -e "    make install SERVER=edge-02      # install only edge-02"
	@echo -e "    make sync-users SERVER=edge-03   # sync users on edge-03"
	@echo -e "    make destroy SERVER=edge-02      # destroy only edge-02"
	@echo -e "    make status                      # status of all servers"
	@echo -e "    make pause-server SERVER=edge-01 # pause edge-01 (save money)"
	@echo -e "    make resume-server SERVER=edge-01 # resume edge-01"
	@echo ""

# =============================================================
#  Dependency check
# =============================================================

check-deps: ## Check that terraform, ansible, python3 are installed
	@echo -e "$(CYAN)→ Checking dependencies...$(NC)"
	@command -v terraform >/dev/null 2>&1 \
		&& echo -e "  $(GREEN)✓$(NC) terraform: $$(terraform version -json | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])')" \
		|| (echo -e "  $(RED)✗$(NC) terraform not found. https://developer.hashicorp.com/terraform/install" && exit 1)
	@command -v ansible >/dev/null 2>&1 \
		&& echo -e "  $(GREEN)✓$(NC) ansible: $$(ansible --version | head -1)" \
		|| (echo -e "  $(RED)✗$(NC) ansible not found. pip install ansible" && exit 1)
	@command -v python3 >/dev/null 2>&1 \
		&& echo -e "  $(GREEN)✓$(NC) python3: $$(python3 --version)" \
		|| (echo -e "  $(RED)✗$(NC) python3 not found" && exit 1)
	@python3 -c "import json, base64, sys" 2>/dev/null \
		&& echo -e "  $(GREEN)✓$(NC) python3 modules: json, base64, sys" \
		|| (echo -e "  $(RED)✗$(NC) python3 standard modules unavailable" && exit 1)
	@echo -e "  $(GREEN)✓$(NC) Everything is installed"

# =============================================================
#  Terraform
# =============================================================

init: check-deps ## Initialize Terraform (run once)
	@echo -e "$(CYAN)→ Initializing Terraform...$(NC)"
	@test -f $(TF_DIR)/terraform.tfvars || \
		(echo -e "$(RED)✗ File $(TF_DIR)/terraform.tfvars not found!$(NC)" && \
		echo -e "  Copy: cp $(TF_DIR)/terraform.tfvars.example $(TF_DIR)/terraform.tfvars" && \
		echo -e "  And fill in your YC credentials" && exit 1)
	@test -f $(TF_DIR)/backend.conf || \
		(echo -e "$(RED)✗ File $(TF_DIR)/backend.conf not found!$(NC)" && \
		echo -e "  Copy: cp $(TF_DIR)/backend.conf.example $(TF_DIR)/backend.conf" && \
		echo -e "  And fill in access_key / secret_key" && exit 1)
	cd $(TF_DIR) && terraform init -backend-config=backend.conf
	@echo -e "$(GREEN)✓ Initialization complete$(NC)"

plan: ## Show what will change (without applying)
	@echo -e "$(CYAN)→ Planning changes...$(NC)"
	cd $(TF_DIR) && terraform plan

apply: ## Create / update infrastructure in YC
	@echo -e "$(CYAN)→ Applying changes in Yandex Cloud...$(NC)"
ifdef SERVER
	cd $(TF_DIR) && terraform apply \
		-target='yandex_vpc_network.main["$(SERVER)"]' \
		-target='yandex_vpc_subnet.main["$(SERVER)"]' \
		-target='yandex_vpc_address.public_ip["$(SERVER)"]' \
		-target='yandex_vpc_security_group.xray["$(SERVER)"]' \
		-target='yandex_compute_instance.xray["$(SERVER)"]'
else
	cd $(TF_DIR) && terraform apply
endif
	@$(MAKE) inventory
	@echo ""
	@echo -e "$(GREEN)✓ Infrastructure created$(NC)"
	@echo -e "  Next step: $(BOLD)make install$(if $(SERVER), SERVER=$(SERVER),)$(NC)"

destroy: ## Delete VM and network (IP is preserved)
	@echo -e "$(YELLOW)$(BOLD)⚠️  Will delete VM and network.$(if $(SERVER), Server: $(SERVER).,) IP will remain.$(NC)"
	@read -p "  Enter 'yes' to confirm: " confirm && \
		[ "$$confirm" = "yes" ] && \
		cd $(TF_DIR) && terraform destroy \
			-target='yandex_compute_instance.xray["$(or $(SERVER),edge-01)"]' \
			-target='yandex_vpc_subnet.main["$(or $(SERVER),edge-01)"]' \
		|| echo -e "$(YELLOW)Cancelled$(NC)"

destroy-all: ## ⚠️  Delete EVERYTHING including IP
	@echo -e "$(RED)$(BOLD)⚠️  Will delete EVERYTHING$(if $(SERVER), for $(SERVER),) including IP! User links will break!$(NC)"
	@read -p "  Enter 'yes' to confirm: " confirm && \
		[ "$$confirm" = "yes" ] && ( \
			yc vpc address update --name $(or $(SERVER),edge-01)-ip --deletion-protection=false 2>/dev/null || true; \
			cd $(TF_DIR) && terraform destroy \
				$(if $(SERVER),-target='yandex_vpc_address.public_ip["$(SERVER)"]' -target='yandex_compute_instance.xray["$(SERVER)"]' -target='yandex_vpc_subnet.main["$(SERVER)"]' -target='yandex_vpc_security_group.xray["$(SERVER)"]' -target='yandex_vpc_network.main["$(SERVER)"]',) \
		) || echo -e "$(YELLOW)Cancelled$(NC)"

output: ## Show Terraform outputs
	@cd $(TF_DIR) && terraform output

# =============================================================
#  Generate Ansible inventory from Terraform outputs
# =============================================================

inventory: ## Generate inventory from Terraform outputs
	@echo -e "$(CYAN)→ Generating Ansible inventory...$(NC)"
	@mkdir -p $(ANSIBLE_DIR)/inventory
	@cd $(TF_DIR) && terraform output -json ansible_inventory_json | \
		python3 ../$(SCRIPTS_DIR)/gen_inventory.py > ../$(INVENTORY)
	@echo -e "$(GREEN)✓ Inventory updated:$(NC)"
	@echo ""
	@cat $(INVENTORY)
	@echo ""

# =============================================================
#  Ansible
# =============================================================

wait-ssh: ## Wait for SSH readiness on server(s)
	@echo -e "$(CYAN)→ Waiting for SSH on the server...$(NC)"
	@cd $(TF_DIR) && terraform output -json server_ips | SERVER=$(SERVER) python3 ../$(SCRIPTS_DIR)/wait_ssh.py

install: inventory wait-ssh ## Full server installation and configuration
	@echo -e "$(CYAN)→ Installing Ansible collections...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml
	@echo -e "$(CYAN)→ Running installation via Ansible...$(NC)"
	@echo -e "  $(YELLOW)This will take 3-5 minutes$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install.yml -v $(LIMIT)
	@echo ""
	@echo -e "$(GREEN)✓ Installation complete$(NC)"

sync-users: ## Sync users (add / disable)
	@echo -e "$(CYAN)→ Syncing users...$(NC)"
	@echo -e "  Reading: $(BOLD)$(ANSIBLE_DIR)/vars/users.yml$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/users.yml $(LIMIT)
	@echo ""
	@echo -e "$(GREEN)✓ Users synced$(NC)"

show-users: ## Show subscription links for all users
	@echo ""
	@echo -e "  $(CYAN)$(BOLD)Users and links$(NC)"
	@echo ""
ifdef SERVER
	@cd $(TF_DIR) && terraform output -json server_ips | python3 -c " \
		import sys, json; ips = json.load(sys.stdin); print(ips.get('$(SERVER)', ''))" | \
		xargs -I{} env SERVER_IP={} SERVER_NAME=$(SERVER) python3 ../$(SCRIPTS_DIR)/show_users.py
else
	@cd $(TF_DIR) && terraform output -json server_ips | python3 -c " \
		import sys, json, subprocess, os; \
		ips = json.load(sys.stdin); \
		[subprocess.run(['python3', '../$(SCRIPTS_DIR)/show_users.py'], env={**os.environ, 'SERVER_IP': ip, 'SERVER_NAME': name}) for name, ip in ips.items()]"
endif

show-qr: ## Show links + QR codes for mobile clients
	@echo ""
	@echo -e "  $(CYAN)$(BOLD)Users, links and QR codes$(NC)"
	@echo ""
ifdef SERVER
	@cd $(TF_DIR) && terraform output -json server_ips | python3 -c " \
		import sys, json; ips = json.load(sys.stdin); print(ips.get('$(SERVER)', ''))" | \
		xargs -I{} env SERVER_IP={} SERVER_NAME=$(SERVER) python3 ../$(SCRIPTS_DIR)/show_users.py --qr
else
	@cd $(TF_DIR) && terraform output -json server_ips | python3 -c " \
		import sys, json, subprocess, os; \
		ips = json.load(sys.stdin); \
		[subprocess.run(['python3', '../$(SCRIPTS_DIR)/show_users.py', '--qr'], env={**os.environ, 'SERVER_IP': ip, 'SERVER_NAME': name}) for name, ip in ips.items()]"
endif

status: ## Check status of all servers
	@echo -e "$(CYAN)→ Checking server status...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/status.yml $(LIMIT)
	@echo ""

rotate-keys: ## Rotate Reality keys
	@echo -e "$(CYAN)→ Rotating Reality keys...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/rotate_keys.yml $(LIMIT)
	@echo ""
	@echo -e "$(GREEN)✓ Keys updated$(NC)"
	@echo -e "  $(YELLOW)Users press Update in their client$(NC)"

rotate-warp: ## Re-register WARP credentials
	@echo -e "$(CYAN)→ Rotating WARP credentials...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/rotate_warp.yml $(LIMIT)
	@echo ""
	@echo -e "$(GREEN)✓ WARP updated$(NC)"

logs: ## Show last 50 lines of Xray logs
	@echo -e "$(CYAN)→ Xray logs...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible xray_servers -b -m command \
		-a "journalctl -u xray -n 50 --no-pager" $(LIMIT)

check-whitelist: ## Check server IP against mobile operator whitelists
	@cd $(TF_DIR) && terraform output -json server_ips | python3 -c " \
		import sys, json, subprocess, os; \
		ips = json.load(sys.stdin); \
		server = '$(SERVER)'; \
		targets = {server: ips[server]} if server and server in ips else ips; \
		[subprocess.run(['python3', '../$(SCRIPTS_DIR)/check_whitelist.py', ip]) for name, ip in targets.items()]"

update-whitelist: ## Update whitelists from GitHub
	@echo -e "$(CYAN)→ Updating whitelists...$(NC)"
	@cd data/whitelist && git pull
	@echo -e "$(GREEN)✓ Whitelists updated$(NC)"

# =============================================================
#  Combined commands
# =============================================================

deploy: check-deps init apply install ## Full deploy from scratch: Terraform + Ansible
	@echo ""
	@echo -e "$(GREEN)$(BOLD)✓ Deploy complete!$(NC)"
	@echo ""
	@echo -e "  Next steps:"
	@echo -e "    Add users: edit $(BOLD)ansible/vars/users.yml$(NC)"
	@echo -e "    Apply:     $(BOLD)make sync-users$(NC)"

# =============================================================
#  Pause / Resume — save costs without losing user configs
# =============================================================

backup-server: inventory ## Backup server secrets to data/backups/{server}/
	@echo -e "$(CYAN)→ Backing up secrets from $(or $(SERVER),all servers)...$(NC)"
	@echo -e "  Saves: secrets.json, users.json, sub_token"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/backup.yml $(LIMIT)
	@echo ""
	@echo -e "$(GREEN)✓ Backup saved to data/backups/$(or $(SERVER),<server>)/$(NC)"
	@echo -e "  $(YELLOW)This directory is in .gitignore — keep it safe!$(NC)"

pause-server: ## Backup secrets + destroy VM (IP preserved, ~130 RUB/mo)
ifndef SERVER
	$(error SERVER is required: make pause-server SERVER=edge-01)
endif
	@echo -e "$(YELLOW)$(BOLD)Pausing $(SERVER): backup → destroy VM (IP stays)$(NC)"
	@echo ""
	@$(MAKE) backup-server SERVER=$(SERVER)
	@echo ""
	@echo -e "$(YELLOW)$(BOLD)⚠️  About to destroy VM $(SERVER). IP will be preserved.$(NC)"
	@read -p "  Enter 'yes' to confirm: " confirm && \
		[ "$$confirm" = "yes" ] && \
		cd $(TF_DIR) && terraform destroy \
			-target='yandex_compute_instance.xray["$(SERVER)"]' \
			-target='yandex_vpc_subnet.main["$(SERVER)"]' \
		|| echo -e "$(YELLOW)Cancelled$(NC)"
	@echo ""
	@echo -e "$(GREEN)✓ $(SERVER) paused. IP preserved. Cost: ~130 RUB/mo$(NC)"
	@echo -e "  Resume: $(BOLD)make resume-server SERVER=$(SERVER)$(NC)"

resume-server: ## Recreate VM + restore secrets + full install
ifndef SERVER
	$(error SERVER is required: make resume-server SERVER=edge-01)
endif
	@echo -e "$(CYAN)→ Resuming $(SERVER)...$(NC)"
	@test -f data/backups/$(SERVER)/secrets.json || \
		(echo -e "$(RED)✗ No backup found at data/backups/$(SERVER)/secrets.json$(NC)" && \
		echo -e "  Run: make backup-server SERVER=$(SERVER) while server is still running" && exit 1)
	@echo ""
	@$(MAKE) apply SERVER=$(SERVER)
	@$(MAKE) wait-ssh SERVER=$(SERVER)
	@echo ""
	@echo -e "$(CYAN)→ Restoring secrets (preserving user links)...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/restore-secrets.yml --limit $(SERVER)
	@echo ""
	@$(MAKE) install SERVER=$(SERVER)
	@echo ""
	@echo -e "$(GREEN)✓ $(SERVER) resumed. All user links unchanged.$(NC)"

ssh: ## SSH connection to server (use SERVER= to pick)
	@echo -e "$(CYAN)→ Connecting to server...$(NC)"
	@cd $(TF_DIR) && \
		SERVER_NAME="$(or $(SERVER),edge-01)" && \
		IP=$$(terraform output -json server_ips | python3 -c "import sys,json; print(json.load(sys.stdin)['$$SERVER_NAME'])") && \
		USER=$$(terraform output -raw ssh_user) && \
		ssh -i ~/.ssh/xray-infra -o StrictHostKeyChecking=accept-new $$USER@$$IP
