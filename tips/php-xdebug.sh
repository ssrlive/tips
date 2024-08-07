#!/bin/bash

# 在 Ubuntu 安裝 PHP 和 xdebug

# 檢查是否有 root 權限
function check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

function set_php_official_repository() {
    # 安裝 PHP 官方存儲庫
    sudo apt install software-properties-common -y
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update -y
}

function update_system() {
    apt update -y
    apt upgrade -y
}

function remove_old_php() {
    apt-get remove apache2 php php-fpm php-xdebug -y
    apt-get purge php.* -y
    apt-get autoremove -y
}

function install_php_n_xdebug() {
    # 安裝新版本 PHP 和 xdebug
    apt install apache2 php php-fpm php-xdebug -y

    # 檢查 PHP 配置信息
    xdebug_config=$(php -i | grep 'xdebug.ini')
    if [ -z "$xdebug_config" ]; then
        echo "xdebug.ini not found"
        exit 1
    else
        echo "xdebug.ini found at $xdebug_config"
    fi

    # 配置 xdebug
    cat > "$xdebug_config" << EOF
zend_extension=xdebug.so
xdebug.mode=debug
xdebug.start_with_request=yes
EOF

    # 重啟 apache2 服務
    systemctl restart apache2
}

function check_xdebug() {
    # 檢查 xdebug 配置
    step_debugger_status=$(php -i | grep 'Step Debugger')
    if [[ $step_debugger_status == "Step Debugger => ✔ enabled" ]]; then
        return 0
    else
        return -1
    fi
    return 0
}

function main() {
    check_root
    if check_xdebug; then
        echo "PHP and xdebug already installed."
    else
        set_php_official_repository
        update_system
        remove_old_php
        install_php_n_xdebug

        if check_xdebug; then
            echo "PHP and xdebug installed successfully."
        else
            echo "PHP and xdebug installation failed."
        fi
    fi
}

main
