#!/usr/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

function install_required_packages() {
    if ! command -v curl >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y curl
    fi
}

function resolve_acme_sh_path() {
    local acme_path

    acme_path="$(command -v acme.sh 2>/dev/null || true)"
    if [ -n "$acme_path" ] && [ -x "$acme_path" ]; then
        printf '%s\n' "$acme_path"
        return 0
    fi

    acme_path="${HOME}/.acme.sh/acme.sh"
    if [ -x "$acme_path" ]; then
        printf '%s\n' "$acme_path"
        return 0
    fi

    return 1
}

function share_dir_with_other_user() {
    local cert_dir="$1"
    local other_user="$2"

    # 取回当前脚本的路径
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local share_dir_script="${script_dir}/share_dir.sh"

    if [ ! -f "$share_dir_script" ]; then
        echo "Warning: share_dir.sh script not found in $(dirname "$share_dir_script"). Attempting to download it from GitHub..."
        curl -o "$share_dir_script" -L https://github.com/ssrlive/tips/raw/refs/heads/master/tips/share_dir.sh
        if [ "$?" -ne 0 ]; then
            echo "Warning: Failed to download share_dir.sh script."
        else
            chmod +x "$share_dir_script"
        fi
    fi

    if [ -f "$share_dir_script" ]; then
        # 执行命令 ${share_dir_script} 将指定路径的权限设置为 当前用户 和 `$other_user` 账号都可读写
        bash "$share_dir_script" "$cert_dir" "$other_user"
    fi
}

function install_or_update_acme_sh() {
    local acme_path

    if ! acme_path="$(resolve_acme_sh_path)"; then
        curl -s https://get.acme.sh | sh -s
    else
        "${acme_path}" --upgrade --auto-upgrade
    fi
}

# if the first argument is provided, return it as the host address;
# otherwise, attempt to resolve the host's IP address using external services or fallback to the hostname.
function resolve_hostaddr() {
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  local hostaddr

  hostaddr=$(curl -4 -sS https://ip.sb 2>/dev/null || true)
  if [ -n "$hostaddr" ]; then
    printf '%s\n' "$hostaddr"
    return 0
  fi

  hostaddr=$(curl -6 -sS https://ip.sb 2>/dev/null || true)
  if [ -n "$hostaddr" ]; then
    printf '%s\n' "$hostaddr"
    return 0
  fi

  hostname -f 2>/dev/null || hostname
}

function main() {
    install_required_packages
    install_or_update_acme_sh

    local acme_sh_path="$(resolve_acme_sh_path)"
    if [ -z "$acme_sh_path" ]; then
        echo "Error: acme.sh was installed, but its executable path could not be resolved." >&2
        exit 1
    fi

    local hostaddr=$(resolve_hostaddr "$1")
    if [ -z "$hostaddr" ]; then
        echo "Error: Unable to resolve host IP address."
        exit 1
    fi

    # 取回当前账号的 home 目录
    local home_dir=$(eval echo "~$USER")

    # 拼装 acme.sh 的生成的证书的默认存储路径
    local cert_dir="${home_dir}/.acme.sh/${hostaddr}_ecc"
    mkdir -p "$cert_dir"

    # 将证书存储路径的权限设置为 当前用户 和 `www-data` 账号都可读写
    share_dir_with_other_user "${cert_dir}" "www-data"

    # 使用 acme.sh 以 standalone 模式申请证书（因此必须首先停止 nginx 服务）, 申请的证书默认存储在
    # ~/.acme.sh/${hostaddr}_ecc 目录下, 申请的证书有效期为 7 天, 因此续订间隔设为 5 天

    "${acme_sh_path}" --issue --standalone  \
        -d "${hostaddr}"                    \
        --server letsencrypt                \
        --certificate-profile shortlived    \
        --days 5                            \
        --force                             \
        --keylength ec-256                  \
        --pre-hook "systemctl stop nginx"   \
        --post-hook "systemctl start nginx"
}

main "$@"
