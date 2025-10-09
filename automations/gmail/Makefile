.PHONY: help setup install install-dev run clean test lint format check

# Default Python version
PYTHON := python3
VENV := .venv
VENV_BIN := $(VENV)/bin
PIP := $(VENV_BIN)/pip
PYTHON_VENV := $(VENV_BIN)/python

# Check if uv is available for faster package management
UV_AVAILABLE := $(shell command -v uv 2> /dev/null)

help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Set up the development environment
ifdef UV_AVAILABLE
	@echo "Using uv for faster environment setup..."
	uv venv $(VENV)
	uv pip install google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client
else
	@echo "Using standard venv and pip..."
	$(PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client
endif
	@echo ""
	@echo "Virtual environment created at: $(VENV)"
	@echo "To activate: source $(VENV_BIN)/activate"

install: setup ## Install production dependencies only (alias for setup)

install-dev: setup ## Install development dependencies (alias for setup)

run: ## Run the Gmail authentication script
	$(PYTHON_VENV) gmail_authentication.py

auth: run ## Alias for run - authenticate with Gmail API

test: ## Run tests
	$(PYTHON_VENV) -m pytest tests/ -v

lint: ## Run linting
	$(PYTHON_VENV) -m ruff check .
	$(PYTHON_VENV) -m mypy .

format: ## Format code
	$(PYTHON_VENV) -m black .
	$(PYTHON_VENV) -m ruff check --fix .

check: lint test ## Run all checks (lint + test)

clean: ## Clean up generated files and virtual environment
	rm -rf $(VENV)
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/
	find . -type d -name __pycache__ -delete
	find . -type f -name "*.pyc" -delete

install-uv: ## Install uv package manager (optional, for faster installs)
	curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtual environment if it doesn't exist
$(VENV):
	make setup