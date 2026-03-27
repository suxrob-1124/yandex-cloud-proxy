# =============================================================
#  Makefile — single entry point
#
#  Usage:        make help
#  Requirements: terraform, ansible, python3
# =============================================================

SHELL         := /bin/bash
.DEFAULT_GOAL := help

TF_DIR        := terraform
ANSIBLE_DIR   := ansible
INVENTORY     := $(ANSIBLE_DIR)/inventory/hosts.yml
SCRIPTS_DIR   := scripts

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
        check-deps check-whitelist update-whitelist

# =============================================================
#  Help
# =============================================================

help: ## Show all commands
	@echo ""
	@echo -e "  $(CYAN)$(BOLD)Xray VLESS+Reality Infrastructure$(NC)"
	@echo ""
	@echo -e "  $(GREEN)Infrastructure (Terraform):$(NC)"
	@echo -e "    make $(BOLD)init$(NC)          Initialize Terraform (first run)"
	@echo -e "    make $(BOLD)plan$(NC)          Show change plan"
	@echo -e "    make $(BOLD)apply$(NC)         Create / update infrastructure in YC"
	@echo -e "    make $(BOLD)destroy$(NC)       ⚠️  Destroy all infrastructure"
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
	@echo -e "  $(GREEN)Combined:$(NC)"
	@echo -e "    make $(BOLD)deploy$(NC)        Full deploy: Terraform + Ansible"
	@echo -e "    make $(BOLD)ssh$(NC)           SSH connection to server"
	@echo ""
	@echo -e "  $(GREEN)Utilities:$(NC)"
	@echo -e "    make $(BOLD)check-deps$(NC)    Check that all utilities are installed"
	@echo -e "    make $(BOLD)check-whitelist$(NC) Check IP against whitelists"
	@echo -e "    make $(BOLD)update-whitelist$(NC) Update whitelists from GitHub"
	@echo ""
	@echo -e "  $(GREEN)Monitoring (optional):$(NC)"
	@echo -e "    Configure: cp ansible/vars/telegram.yml.example ansible/vars/telegram.yml"
	@echo -e "    Then:      make install"
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
	cd $(TF_DIR) && terraform apply
	@$(MAKE) inventory
	@echo ""
	@echo -e "$(GREEN)✓ Infrastructure created$(NC)"
	@echo -e "  Next step: $(BOLD)make install$(NC)"

destroy: ## Delete VM and network (IP is preserved, links remain unchanged)
	@echo -e "$(YELLOW)$(BOLD)⚠️  Will delete VM and network. IP will remain.$(NC)"
	@read -p "  Enter 'yes' to confirm: " confirm && \
		[ "$$confirm" = "yes" ] && \
		cd $(TF_DIR) && terraform destroy \
			-target=yandex_compute_instance.xray \
			-target=yandex_vpc_subnet.main \
			-target=yandex_vpc_security_group.xray \
			-target=yandex_vpc_network.main \
		|| echo -e "$(YELLOW)Cancelled$(NC)"

destroy-all: ## ⚠️  Delete EVERYTHING including IP (only when shutting down the project)
	@echo -e "$(RED)$(BOLD)⚠️  Will delete EVERYTHING including IP! User links will break!$(NC)"
	@read -p "  Enter 'yes' to confirm: " confirm && \
		[ "$$confirm" = "yes" ] && \
		yc vpc address update --name edge-01-ip --deletion-protection=false 2>/dev/null || true && \
		cd $(TF_DIR) && terraform destroy \
		|| echo -e "$(YELLOW)Cancelled$(NC)"

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

wait-ssh: ## Wait for SSH readiness on the server
	@echo -e "$(CYAN)→ Waiting for SSH on the server...$(NC)"
	@IP=$$(cd $(TF_DIR) && terraform output -raw server_ip) && \
		ssh-keygen -R $$IP 2>/dev/null; \
		for i in $$(seq 1 30); do \
			nc -z -w2 $$IP 22 2>/dev/null && break; \
			echo -e "  $(YELLOW)SSH not ready yet, waiting... ($$i/30)$(NC)"; \
			sleep 5; \
		done && \
		nc -z -w2 $$IP 22 2>/dev/null && \
		echo -e "  $(GREEN)✓ SSH available$(NC)" || \
		(echo -e "  $(RED)✗ SSH did not start within 150 seconds$(NC)" && exit 1)

install: inventory wait-ssh ## Full server installation and configuration
	@echo -e "$(CYAN)→ Installing Ansible collections...$(NC)"
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml
	@echo -e "$(CYAN)→ Running installation via Ansible...$(NC)"
	@echo -e "  $(YELLOW)This will take 3-5 minutes$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install.yml -v
	@echo ""
	@echo -e "$(GREEN)✓ Installation complete$(NC)"

sync-users: ## Sync users (add / disable)
	@echo -e "$(CYAN)→ Syncing users...$(NC)"
	@echo -e "  Reading: $(BOLD)$(ANSIBLE_DIR)/vars/users.yml$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/users.yml
	@echo ""
	@echo -e "$(GREEN)✓ Users synced$(NC)"


show-users: ## Show subscription links for all users
	@echo ""
	@echo -e "  $(CYAN)$(BOLD)Users and links$(NC)"
	@echo ""
	@SERVER_IP=$$(cd $(TF_DIR) && terraform output -raw server_ip) && \
		SERVER_IP=$$SERVER_IP python3 $(SCRIPTS_DIR)/show_users.py

show-qr: ## Show links + QR codes for mobile clients
	@echo ""
	@echo -e "  $(CYAN)$(BOLD)Users, links and QR codes$(NC)"
	@echo ""
	@SERVER_IP=$$(cd $(TF_DIR) && terraform output -raw server_ip) && \
		SERVER_IP=$$SERVER_IP python3 $(SCRIPTS_DIR)/show_users.py --qr


status: ## Check status of all servers
	@echo -e "$(CYAN)→ Checking server status...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/status.yml
	@echo ""

rotate-keys: ## Rotate Reality keys (client configs will update automatically)
	@echo -e "$(CYAN)→ Rotating Reality keys...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/rotate_keys.yml
	@echo ""
	@echo -e "$(GREEN)✓ Keys updated$(NC)"
	@echo -e "  $(YELLOW)Users press Update in their client$(NC)"

rotate-warp: ## Re-register WARP credentials
	@echo -e "$(CYAN)→ Rotating WARP credentials...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/rotate_warp.yml
	@echo ""
	@echo -e "$(GREEN)✓ WARP updated$(NC)"

logs: ## Show last 50 lines of Xray logs
	@echo -e "$(CYAN)→ Xray logs...$(NC)"
	@echo ""
	cd $(ANSIBLE_DIR) && ansible xray_servers -b -m command \
		-a "journalctl -u xray -n 50 --no-pager"

check-whitelist: ## Check server IP against mobile operator whitelists
	@SERVER_IP=$$(cd $(TF_DIR) && terraform output -raw server_ip) && \
		MASQUERADE_HOST=$$(grep masquerade_host $(ANSIBLE_DIR)/inventory/group_vars/all.yml | awk '{print $$2}' | tr -d '"') && \
		SERVER_IP=$$SERVER_IP MASQUERADE_HOST=$$MASQUERADE_HOST python3 $(SCRIPTS_DIR)/check_whitelist.py

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
	@echo -e "  SSH connection:"
	@cd $(TF_DIR) && echo -e "  $(CYAN)$$(terraform output -raw ssh_command)$(NC)"
	@echo ""
	@echo -e "  Next steps:"
	@echo -e "    Add users: edit $(BOLD)ansible/vars/users.yml$(NC)"
	@echo -e "    Apply:     $(BOLD)make sync-users$(NC)"

ssh: ## SSH connection to server
	@echo -e "$(CYAN)→ Connecting to server...$(NC)"
	@cd $(TF_DIR) && \
		IP=$$(terraform output -raw server_ip) && \
		USER=$$(terraform output -raw ssh_user) && \
		ssh -i ~/.ssh/xray-infra -o StrictHostKeyChecking=accept-new $$USER@$$IP
