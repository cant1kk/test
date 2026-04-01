#!/bin/bash

#############################################################################
# FPTN VPN Server - Installation Script for Ubuntu 22.04
# https://github.com/batchar2/fptn
#############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script version
VERSION="1.3.0"

# Installation directory
INSTALL_DIR="/opt/fptn"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
ENV_FILE="$INSTALL_DIR/.env"
DATA_DIR="$INSTALL_DIR/fptn-server-data"

# Docker Compose command (will be set by detect_docker_compose_version)
COMPOSE_CMD=""
COMPOSE_VERSION=""

#############################################################################
# Utility Functions
#############################################################################

print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           FPTN VPN Server - Installation Script               ║"
    echo "║                    Version: $VERSION                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [ -n "$default" ]; then
        read -p "$(echo -e ${BLUE}$prompt ${NC}[${GREEN}$default${NC}]: )" result
        echo "${result:-$default}"
    else
        read -p "$(echo -e ${BLUE}$prompt${NC}: )" result
        echo "$result"
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [ "$default" = "y" ]; then
        read -p "$(echo -e ${BLUE}$prompt${NC} [Y/n]: )" result
        result="${result:-y}"
    else
        read -p "$(echo -e ${BLUE}$prompt${NC} [y/N]: )" result
        result="${result:-n}"
    fi
    
    [[ "$result" =~ ^[Yy]$ ]]
}

#############################################################################
# Docker Compose Version Detection
#############################################################################

detect_docker_compose_version() {
    log_info "Определение версии Docker Compose..."
    
    # Check for Docker Compose v2 (docker compose)
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
        COMPOSE_VERSION="v2"
        local version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_success "Обнаружен Docker Compose v2: $version"
        return 0
    fi
    
    # Check for Docker Compose v1 (docker-compose)
    if command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        COMPOSE_VERSION="v1"
        local version=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        log_warn "Обнаружен Docker Compose v1: $version (устаревшая версия)"
        
        # Suggest upgrade to v2
        echo ""
        log_warn "Docker Compose v1 устарел и больше не поддерживается с июля 2023 года."
        log_info "Рекомендуется обновить до Docker Compose v2 для лучшей производительности и безопасности."
        echo ""
        
        if prompt_yes_no "Хотите обновить Docker Compose до v2 сейчас?" "y"; then
            upgrade_docker_compose_v2
            return $?
        else
            log_info "Продолжаем с Docker Compose v1..."
            return 0
        fi
    fi
    
    # Neither version found
    log_error "Docker Compose не установлен"
    return 1
}

upgrade_docker_compose_v2() {
    log_info "Обновление Docker Compose до v2..."
    
    # Remove old docker-compose v1 if installed via pip or curl
    if command -v docker-compose &>/dev/null; then
        log_info "Удаление Docker Compose v1..."
        
        # Try to remove via pip
        pip uninstall -y docker-compose 2>/dev/null || true
        pip3 uninstall -y docker-compose 2>/dev/null || true
        
        # Remove binary if installed via curl
        rm -f /usr/local/bin/docker-compose 2>/dev/null || true
        rm -f /usr/bin/docker-compose 2>/dev/null || true
    fi
    
    # Install Docker Compose v2 plugin
    log_info "Установка Docker Compose v2..."
    
    apt-get update -qq
    apt-get install -y -qq docker-compose-plugin
    
    # Verify installation
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
        COMPOSE_VERSION="v2"
        local version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_success "Docker Compose v2 успешно установлен: $version"
        return 0
    else
        log_error "Не удалось установить Docker Compose v2"
        log_info "Продолжаем с Docker Compose v1..."
        COMPOSE_CMD="docker-compose"
        COMPOSE_VERSION="v1"
        return 1
    fi
}

run_compose() {
    local args="$@"
    
    if [ "$COMPOSE_VERSION" = "v2" ]; then
        # Docker Compose v2: supports --env-file flag
        cd "$INSTALL_DIR"
        $COMPOSE_CMD --env-file "$ENV_FILE" $args
    else
        # Docker Compose v1: reads .env automatically from current directory
        cd "$INSTALL_DIR"
        $COMPOSE_CMD $args
    fi
}

#############################################################################
# System Requirements Check
#############################################################################

check_system_requirements() {
    log_info "Проверка системных требований..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Скрипт должен быть запущен с правами root (sudo)"
        exit 1
    fi
    
    # Check Ubuntu version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_warn "Обнаружена ОС: $ID. Рекомендуется Ubuntu 22.04"
        elif [[ "$VERSION_ID" != "22.04" ]]; then
            log_warn "Обнаружена версия Ubuntu: $VERSION_ID. Рекомендуется 22.04"
        fi
    fi
    
    # Check available memory
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_total / 1024 / 1024))
    if [ $mem_gb -lt 1 ]; then
        log_warn "Доступно RAM: ${mem_gb}GB. Рекомендуется минимум 1GB"
    fi
    
    # Check disk space
    local disk_free=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ $disk_free -lt 5 ]; then
        log_warn "Свободно места на диске: ${disk_free}GB. Рекомендуется минимум 5GB"
    fi
    
    log_success "Проверка системных требований завершена"
}

#############################################################################
# Docker Installation
#############################################################################

install_docker() {
    log_info "Проверка установки Docker..."
    
    if command -v docker &> /dev/null; then
        log_success "Docker уже установлен: $(docker --version)"
        
        # Detect Docker Compose version after Docker is confirmed
        detect_docker_compose_version
        return 0
    fi
    
    log_info "Установка Docker..."
    
    # Update package index
    apt-get update -qq
    
    # Install prerequisites
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine with Compose v2 plugin
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker успешно установлен: $(docker --version)"
    
    # Detect Docker Compose version
    detect_docker_compose_version
}

#############################################################################
# Interactive Configuration
#############################################################################

configure_server() {
    log_info "Интерактивная настройка FPTN VPN сервера"
    echo ""
    
    # Get server public IP
    local detected_ip=$(curl -s ifconfig.me || echo "")
    SERVER_IP=$(prompt_input "Введите публичный IP адрес сервера" "$detected_ip")
    
    # Get server port
    SERVER_PORT=$(prompt_input "Введите порт для VPN сервера" "443")
    
    # Enable probing detection
    if prompt_yes_no "Включить защиту от сканирования (DPI detection)?" "y"; then
        ENABLE_DETECT_PROBING="true"
    else
        ENABLE_DETECT_PROBING="false"
    fi
    
    # Default proxy domain
    DEFAULT_PROXY_DOMAIN=$(prompt_input "Домен для проксирования нелегитимного трафика" "cdnvideo.com")
    
    # Allowed SNI list
    echo -e "${BLUE}Список разрешенных SNI доменов (через запятую, оставьте пустым для разрешения всех):${NC}"
    read -p "> " ALLOWED_SNI_LIST
    
    # Disable BitTorrent
    if prompt_yes_no "Блокировать BitTorrent трафик?" "y"; then
        DISABLE_BITTORRENT="true"
    else
        DISABLE_BITTORRENT="false"
    fi
    
    # Max sessions per user
    MAX_SESSIONS=$(prompt_input "Максимальное количество активных сессий на пользователя" "3")
    
    # DNS server selection
    echo -e "${BLUE}Выберите DNS сервер:${NC}"
    echo "  1) dnsmasq (легковесный, рекомендуется)"
    echo "  2) unbound (рекурсивный, валидирующий)"
    read -p "Выбор [1]: " dns_choice
    dns_choice="${dns_choice:-1}"
    
    if [ "$dns_choice" = "2" ]; then
        USING_DNS_SERVER="unbound"
    else
        USING_DNS_SERVER="dnsmasq"
    fi
    
    # DNS settings for dnsmasq
    if [ "$USING_DNS_SERVER" = "dnsmasq" ]; then
        DNS_IPV4_PRIMARY=$(prompt_input "Первичный DNS IPv4" "8.8.8.8")
        DNS_IPV4_SECONDARY=$(prompt_input "Вторичный DNS IPv4" "8.8.4.4")
        DNS_IPV6_PRIMARY=$(prompt_input "Первичный DNS IPv6" "2001:4860:4860::8888")
        DNS_IPV6_SECONDARY=$(prompt_input "Вторичный DNS IPv6" "2001:4860:4860::8844")
    fi
    
    # Prometheus secret key
    if prompt_yes_no "Включить мониторинг Prometheus?" "y"; then
        PROMETHEUS_KEY=$(openssl rand -hex 16)
        ENABLE_PROMETHEUS="true"
        log_info "Сгенерирован ключ Prometheus: $PROMETHEUS_KEY"
    else
        PROMETHEUS_KEY=""
        ENABLE_PROMETHEUS="false"
    fi
    
    # Clustering options
    if prompt_yes_no "Использовать удаленный сервер авторизации (кластер)?" "n"; then
        USE_REMOTE_AUTH="true"
        REMOTE_AUTH_HOST=$(prompt_input "Адрес удаленного сервера авторизации" "")
        REMOTE_AUTH_PORT=$(prompt_input "Порт удаленного сервера авторизации" "443")
    else
        USE_REMOTE_AUTH="false"
        REMOTE_AUTH_HOST=""
        REMOTE_AUTH_PORT="443"
    fi
    
    echo ""
    log_success "Конфигурация завершена"
}

#############################################################################
# Create Configuration Files
#############################################################################

create_env_file() {
    log_info "Создание файла конфигурации .env..."
    
    mkdir -p "$INSTALL_DIR"
    
    cat > "$ENV_FILE" << EOF
# ============================================
# FPTN SERVER CONFIGURATION
# Generated: $(date)
# ============================================

# Server settings
FPTN_PORT=$SERVER_PORT
SERVER_EXTERNAL_IPS=$SERVER_IP

# Security settings
ENABLE_DETECT_PROBING=$ENABLE_DETECT_PROBING
DEFAULT_PROXY_DOMAIN=$DEFAULT_PROXY_DOMAIN
ALLOWED_SNI_LIST=$ALLOWED_SNI_LIST
DISABLE_BITTORRENT=$DISABLE_BITTORRENT

# Session limits
MAX_ACTIVE_SESSIONS_PER_USER=$MAX_SESSIONS

# DNS settings
USING_DNS_SERVER=$USING_DNS_SERVER
DNS_IPV4_PRIMARY=${DNS_IPV4_PRIMARY:-8.8.8.8}
DNS_IPV4_SECONDARY=${DNS_IPV4_SECONDARY:-8.8.4.4}
DNS_IPV6_PRIMARY=${DNS_IPV6_PRIMARY:-2001:4860:4860::8888}
DNS_IPV6_SECONDARY=${DNS_IPV6_SECONDARY:-2001:4860:4860::8844}

# Monitoring
PROMETHEUS_SECRET_ACCESS_KEY=$PROMETHEUS_KEY

# Clustering
USE_REMOTE_SERVER_AUTH=$USE_REMOTE_AUTH
REMOTE_SERVER_AUTH_HOST=$REMOTE_AUTH_HOST
REMOTE_SERVER_AUTH_PORT=$REMOTE_AUTH_PORT
EOF
    
    chmod 600 "$ENV_FILE"
    log_success "Файл .env создан: $ENV_FILE"
}

create_docker_compose() {
    log_info "Создание docker-compose.yml..."
    
    cat > "$COMPOSE_FILE" << 'EOF'
services:
  fptn-server:
    restart: unless-stopped
    image: fptnvpn/fptn-vpn-server:latest
    container_name: fptn-server
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
      - NET_RAW
      - SYS_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
      - net.ipv4.conf.all.rp_filter=0
      - net.ipv4.conf.default.rp_filter=0
    ulimits:
      nproc:
        soft: 524288
        hard: 524288
      nofile:
        soft: 524288
        hard: 524288
      memlock:
        soft: 524288
        hard: 524288
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "${FPTN_PORT}:443/tcp"
    volumes:
      - ./fptn-server-data:/etc/fptn
    environment:
      - ENABLE_DETECT_PROBING=${ENABLE_DETECT_PROBING}
      - DEFAULT_PROXY_DOMAIN=${DEFAULT_PROXY_DOMAIN}
      - ALLOWED_SNI_LIST=${ALLOWED_SNI_LIST}
      - DISABLE_BITTORRENT=${DISABLE_BITTORRENT}
      - PROMETHEUS_SECRET_ACCESS_KEY=${PROMETHEUS_SECRET_ACCESS_KEY}
      - USE_REMOTE_SERVER_AUTH=${USE_REMOTE_SERVER_AUTH}
      - REMOTE_SERVER_AUTH_HOST=${REMOTE_SERVER_AUTH_HOST}
      - REMOTE_SERVER_AUTH_PORT=${REMOTE_SERVER_AUTH_PORT}
      - MAX_ACTIVE_SESSIONS_PER_USER=${MAX_ACTIVE_SESSIONS_PER_USER}
      - SERVER_EXTERNAL_IPS=${SERVER_EXTERNAL_IPS}
      - USING_DNS_SERVER=${USING_DNS_SERVER}
      - DNS_IPV4_PRIMARY=${DNS_IPV4_PRIMARY}
      - DNS_IPV4_SECONDARY=${DNS_IPV4_SECONDARY}
      - DNS_IPV6_PRIMARY=${DNS_IPV6_PRIMARY}
      - DNS_IPV6_SECONDARY=${DNS_IPV6_SECONDARY}
    healthcheck:
      test: ["CMD", "sh", "-c", "pgrep dnsmasq && pgrep fptn-server"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    
    log_success "Файл docker-compose.yml создан: $COMPOSE_FILE"
}

#############################################################################
# Docker Image Management
#############################################################################

pull_docker_image() {
    log_info "Проверка Docker образа FPTN..."
    
    # Check if image already exists
    if docker images fptnvpn/fptn-vpn-server:latest --format "{{.Repository}}" | grep -q "fptnvpn/fptn-vpn-server"; then
        log_success "Docker образ уже скачан"
        return 0
    fi
    
    log_info "Скачивание Docker образа fptnvpn/fptn-vpn-server:latest..."
    log_warn "Это может занять несколько минут в зависимости от скорости интернета..."
    
    if docker pull fptnvpn/fptn-vpn-server:latest; then
        log_success "Docker образ успешно скачан"
        return 0
    else
        log_error "Не удалось скачать Docker образ"
        return 1
    fi
}

#############################################################################
# SSL Certificate Generation
#############################################################################

generate_ssl_certificates() {
    log_info "Генерация SSL сертификатов..."
    
    mkdir -p "$DATA_DIR"
    
    # Check if certificates already exist
    if [ -f "$DATA_DIR/server.key" ] && [ -f "$DATA_DIR/server.crt" ]; then
        log_warn "SSL сертификаты уже существуют"
        if ! prompt_yes_no "Пересоздать сертификаты?" "n"; then
            log_info "Используем существующие сертификаты"
            return 0
        fi
    fi
    
    log_info "Генерация приватного ключа (это может занять несколько секунд)..."
    # Generate private key with timeout
    if ! timeout 60 run_compose run --rm fptn-server \
        sh -c "cd /etc/fptn && openssl genrsa -out server.key 2048"; then
        log_error "Не удалось сгенерировать приватный ключ (timeout или ошибка)"
        log_info "Попробуйте запустить вручную: cd /opt/fptn && docker-compose run --rm fptn-server sh -c 'cd /etc/fptn && openssl genrsa -out server.key 2048'"
        return 1
    fi
    
    log_info "Генерация самоподписанного сертификата..."
    # Generate self-signed certificate with timeout
    if ! timeout 60 run_compose run --rm fptn-server \
        sh -c "cd /etc/fptn && openssl req -new -x509 -key server.key -out server.crt -days 365 -subj '/C=US/ST=State/L=City/O=FPTN/CN=fptn-server'"; then
        log_error "Не удалось сгенерировать сертификат (timeout или ошибка)"
        log_info "Попробуйте запустить вручную: cd /opt/fptn && docker-compose run --rm fptn-server sh -c 'cd /etc/fptn && openssl req -new -x509 -key server.key -out server.crt -days 365 -subj \"/C=US/ST=State/L=City/O=FPTN/CN=fptn-server\"'"
        return 1
    fi
    
    # Verify certificates were created
    if [ ! -f "$DATA_DIR/server.key" ] || [ ! -f "$DATA_DIR/server.crt" ]; then
        log_error "SSL сертификаты не были созданы!"
        log_info "Проверьте логи Docker: docker logs fptn-server"
        return 1
    fi
    
    log_info "Получение отпечатка сертификата..."
    # Get certificate fingerprint
    local fingerprint=$(timeout 30 run_compose run --rm fptn-server \
        sh -c "openssl x509 -noout -fingerprint -md5 -in /etc/fptn/server.crt | cut -d'=' -f2 | tr -d ':' | tr 'A-F' 'a-f'" 2>/dev/null | tr -d '\r')
    
    log_success "SSL сертификаты созданы"
    if [ -n "$fingerprint" ]; then
        log_info "MD5 Fingerprint: $fingerprint"
    fi
}

#############################################################################
# Server Management
#############################################################################

start_server() {
    log_info "Запуск FPTN VPN сервера..."
    
    run_compose up -d
    
    sleep 5
    
    # Check server status
    if run_compose ps | grep -q "Up"; then
        log_success "Сервер успешно запущен"
        return 0
    else
        log_error "Ошибка запуска сервера"
        return 1
    fi
}

stop_server() {
    log_info "Остановка FPTN VPN сервера..."
    run_compose down
    log_success "Сервер остановлен"
}

restart_server() {
    log_info "Перезапуск FPTN VPN сервера..."
    run_compose restart
    log_success "Сервер перезапущен"
}

server_status() {
    cd "$INSTALL_DIR"
    echo ""
    log_info "Статус FPTN VPN сервера:"
    run_compose ps
    echo ""
}

server_logs() {
    run_compose logs -f
}

#############################################################################
# User Management
#############################################################################

add_user() {
    local username="$1"
    local bandwidth="$2"
    
    if [ -z "$username" ]; then
        username=$(prompt_input "Введите имя пользователя" "")
    fi
    
    if [ -z "$bandwidth" ]; then
        bandwidth=$(prompt_input "Введите ограничение скорости (Mbps)" "100")
    fi
    
    log_info "Добавление пользователя: $username (bandwidth: ${bandwidth}Mbps)..."
    
    run_compose exec fptn-server fptn-passwd --add-user "$username" --bandwidth "$bandwidth"
    
    log_success "Пользователь $username добавлен"
}

delete_user() {
    local username="$1"
    
    if [ -z "$username" ]; then
        username=$(prompt_input "Введите имя пользователя для удаления" "")
    fi
    
    log_info "Удаление пользователя: $username..."
    
    run_compose exec fptn-server fptn-passwd --delete-user "$username"
    
    log_success "Пользователь $username удален"
}

list_users() {
    log_info "Список пользователей:"
    
    run_compose exec fptn-server fptn-passwd --list-users
}

generate_token() {
    local username="$1"
    local password="$2"
    
    if [ -z "$username" ]; then
        username=$(prompt_input "Введите имя пользователя" "")
    fi
    
    if [ -z "$password" ]; then
        read -s -p "$(echo -e ${BLUE}Введите пароль${NC}: )" password
        echo ""
    fi
    
    log_info "Генерация токена для пользователя: $username..."
    
    run_compose run --rm fptn-server \
        token-generator --user "$username" --password "$password" --server-ip "$SERVER_IP" --port "$SERVER_PORT"
}

change_password() {
    local username="$1"
    
    if [ -z "$username" ]; then
        username=$(prompt_input "Введите имя пользователя" "")
    fi
    
    log_info "Изменение пароля для пользователя: $username..."
    
    run_compose exec fptn-server fptn-passwd --change-password "$username"
    
    log_success "Пароль изменен для пользователя $username"
}

#############################################################################
# Monitoring Setup
#############################################################################

setup_monitoring() {
    if [ "$ENABLE_PROMETHEUS" != "true" ]; then
        log_info "Мониторинг не включен, пропуск установки Prometheus/Grafana"
        return 0
    fi
    
    log_info "Настройка мониторинга (Prometheus + Grafana)..."
    
    # Create monitoring docker-compose
    cat > "$INSTALL_DIR/docker-compose.monitoring.yml" << EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: fptn-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    container_name: fptn-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false

volumes:
  prometheus-data:
  grafana-data:
EOF
    
    # Create Prometheus config
    cat > "$INSTALL_DIR/prometheus.yml" << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'fptn-server'
    static_configs:
      - targets: ['fptn-server:443']
    params:
      key: ['$PROMETHEUS_KEY']
EOF
    
    # Start monitoring stack
    cd "$INSTALL_DIR"
    if [ "$COMPOSE_VERSION" = "v2" ]; then
        docker compose -f docker-compose.monitoring.yml up -d
    else
        docker-compose -f docker-compose.monitoring.yml up -d
    fi
    
    log_success "Мониторинг настроен"
    log_info "Prometheus: http://$SERVER_IP:9090"
    log_info "Grafana: http://$SERVER_IP:3000 (admin/admin)"
}

#############################################################################
# Installation Process
#############################################################################

install_fptn() {
    print_header
    
    check_system_requirements
    install_docker
    configure_server
    create_env_file
    create_docker_compose
    pull_docker_image
    
    # Generate SSL certificates
    if ! generate_ssl_certificates; then
        log_error "Не удалось сгенерировать SSL сертификаты"
        echo ""
        log_warn "Вы можете создать их вручную:"
        echo "  cd /opt/fptn"
        echo "  docker-compose run --rm fptn-server sh -c 'cd /etc/fptn && openssl genrsa -out server.key 2048'"
        echo "  docker-compose run --rm fptn-server sh -c 'cd /etc/fptn && openssl req -new -x509 -key server.key -out server.crt -days 365 -subj \"/C=US/ST=State/L=City/O=FPTN/CN=fptn-server\"'"
        echo "  docker-compose up -d"
        echo ""
        exit 1
    fi
    
    start_server
    
    echo ""
    log_success "Установка FPTN VPN сервера завершена!"
    echo ""
    
    # Create first user
    if prompt_yes_no "Создать первого пользователя?" "y"; then
        add_user
        echo ""
        if prompt_yes_no "Сгенерировать токен подключения?" "y"; then
            generate_token
        fi
    fi
    
    # Setup monitoring
    if [ "$ENABLE_PROMETHEUS" = "true" ]; then
        echo ""
        if prompt_yes_no "Установить Prometheus и Grafana?" "y"; then
            setup_monitoring
        fi
    fi
    
    echo ""
    log_info "Управление сервером:"
    echo "  $0 status      - Статус сервера"
    echo "  $0 logs        - Просмотр логов"
    echo "  $0 add-user    - Добавить пользователя"
    echo "  $0 gen-token   - Сгенерировать токен"
    echo "  $0 list-users  - Список пользователей"
    echo ""
}

#############################################################################
# Backup and Restore
#############################################################################

backup_config() {
    local backup_file="fptn-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    log_info "Создание резервной копии..."
    
    cd "$INSTALL_DIR"
    tar -czf "/root/$backup_file" .env fptn-server-data/
    
    log_success "Резервная копия создана: /root/$backup_file"
}

#############################################################################
# Update
#############################################################################

update_server() {
    log_info "Обновление FPTN VPN сервера..."
    
    cd "$INSTALL_DIR"
    
    # Backup before update
    backup_config
    
    # Pull latest image
    run_compose pull
    
    # Restart with new image
    run_compose up -d
    
    log_success "Сервер обновлен до последней версии"
}

#############################################################################
# Uninstall
#############################################################################

uninstall_fptn() {
    log_warn "Это удалит FPTN VPN сервер и все данные!"
    
    if ! prompt_yes_no "Вы уверены?" "n"; then
        log_info "Отмена удаления"
        return 0
    fi
    
    log_info "Удаление FPTN VPN сервера..."
    
    # Stop and remove containers
    if [ -f "$COMPOSE_FILE" ]; then
        cd "$INSTALL_DIR"
        run_compose down -v
    fi
    
    # Remove monitoring if exists
    if [ -f "$INSTALL_DIR/docker-compose.monitoring.yml" ]; then
        cd "$INSTALL_DIR"
        if [ "$COMPOSE_VERSION" = "v2" ]; then
            docker compose -f docker-compose.monitoring.yml down -v
        else
            docker-compose -f docker-compose.monitoring.yml down -v
        fi
    fi
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    log_success "FPTN VPN сервер удален"
}

#############################################################################
# Main Menu
#############################################################################

show_menu() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     FPTN VPN Server Management         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) Установить FPTN VPN сервер"
    echo "  2) Статус сервера"
    echo "  3) Запустить сервер"
    echo "  4) Остановить сервер"
    echo "  5) Перезапустить сервер"
    echo "  6) Просмотр логов"
    echo ""
    echo "  7) Добавить пользователя"
    echo "  8) Удалить пользователя"
    echo "  9) Список пользователей"
    echo " 10) Сгенерировать токен"
    echo " 11) Изменить пароль"
    echo ""
    echo " 12) Резервная копия"
    echo " 13) Обновить сервер"
    echo " 14) Удалить сервер"
    echo ""
    echo "  0) Выход"
    echo ""
}

#############################################################################
# Main Script Logic
#############################################################################

main() {
    # Check if running with command line arguments
    if [ $# -gt 0 ]; then
        case "$1" in
            install)
                install_fptn
                ;;
            status)
                server_status
                ;;
            start)
                start_server
                ;;
            stop)
                stop_server
                ;;
            restart)
                restart_server
                ;;
            logs)
                server_logs
                ;;
            add-user)
                add_user "$2" "$3"
                ;;
            delete-user)
                delete_user "$2"
                ;;
            list-users)
                list_users
                ;;
            gen-token)
                generate_token "$2" "$3"
                ;;
            change-password)
                change_password "$2"
                ;;
            backup)
                backup_config
                ;;
            update)
                update_server
                ;;
            uninstall)
                uninstall_fptn
                ;;
            *)
                echo "Использование: $0 {install|status|start|stop|restart|logs|add-user|delete-user|list-users|gen-token|change-password|backup|update|uninstall}"
                exit 1
                ;;
        esac
    else
        # Interactive menu
        while true; do
            show_menu
            read -p "Выберите действие: " choice
            
            case $choice in
                1) install_fptn ;;
                2) server_status ;;
                3) start_server ;;
                4) stop_server ;;
                5) restart_server ;;
                6) server_logs ;;
                7) add_user ;;
                8) delete_user ;;
                9) list_users ;;
                10) generate_token ;;
                11) change_password ;;
                12) backup_config ;;
                13) update_server ;;
                14) uninstall_fptn ;;
                0) 
                    log_info "Выход"
                    exit 0
                    ;;
                *)
                    log_error "Неверный выбор"
                    ;;
            esac
            
            echo ""
            read -p "Нажмите Enter для продолжения..."
        done
    fi
}

# Run main function
main "$@"
