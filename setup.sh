#!/bin/bash

# ==============================================================================
# Agentic Loop Protocol 环境初始化脚本
# 功能：检查并安装必要工具、启动虚拟环境、设置环境变量
# ==============================================================================

# set -e  # 遇到错误立即退出

# ==============================================================================
# 颜色定义
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# 日志函数
# ==============================================================================

# 输出信息日志
log_info() {
    echo -e "${BLUE}[INFO   ]${NC} $1"
}

# 输出成功日志
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 输出警告日志
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 输出错误日志
log_error() {
    echo -e "${RED}[ERROR  ]${NC} $1"
}

# ==============================================================================
# 工具函数
# ==============================================================================

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ==============================================================================
# 安装函数
# ==============================================================================

# 检查并安装 git
install_git() {
    log_info "检查 git 安装状态..."
    if ! command_exists git; then
        log_info "正在安装 git..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo yum install -y git
        else
            log_error "不支持的操作系统，请手动安装 git: https://git-scm.com/downloads"
            exit 1
        fi

        if command_exists git; then
            local git_version=$(git --version)
            log_success "git 安装完成 (版本: $git_version)"
        else
            log_error "git 安装失败，请手动安装: https://git-scm.com/downloads"
            exit 1
        fi
    else
        local git_version=$(git --version)
        log_success "git 已安装 (版本: $git_version)"
    fi
}

# 检查并安装 uv
install_uv() {
    log_info "检查 uv 安装状态..."
    if ! command_exists uv; then
        log_info "正在安装 uv..."
        if pip install uv; then
            log_success "uv 安装完成"
        else
            log_error "uv 安装失败，请手动安装: https://github.com/astral-sh/uv"
            return 1
        fi
        
        # 验证安装是否成功
        if command_exists uv; then
            local uv_version=$(uv --version)
            log_success "uv 验证成功 (版本: $uv_version)"
            return 0
        else
            log_error "uv 安装后验证失败，请手动安装: https://github.com/astral-sh/uv"
            exit 1
        fi
    else
        local uv_version=$(uv --version)
        log_success "uv 已安装 (版本: $uv_version)"
    fi
}

# 下载并安装 git-flow
download_git_flow() {
    # 设置函数返回时自动清理
    trap '_cleanup_git_flow_files; trap - RETURN' RETURN
    
    # 下载安装脚本
    if ! wget --no-check-certificate -q https://raw.github.com/petervanderdoes/gitflow/develop/contrib/gitflow-installer.sh; then
        return 1
    fi

    # 添加执行权限
    chmod +x gitflow-installer.sh
    
    # 执行安装
    if sudo ./gitflow-installer.sh install stable; then
        return 0
    else
        return 1
    fi
}

_cleanup_git_flow_files() {
    echo "正在清理文件..."
    rm -f gitflow-installer.sh
    rm -rf gitflow/
}

# 使用官方安装脚本安装 gitflow
install_git_flow() {
    log_info "检查 git-flow 安装状态..."
    if ! command_exists git flow; then
        log_info "正在安装 git-flow..."
        if download_git_flow; then
            log_success "git-flow 安装完成"
        else
            log_error "git-flow 安装失败，请手动安装: https://github.com/gittower/git-flow-next/"
            return 1
        fi

        # 验证安装
        if command_exists git flow; then
            local version=$(git flow version)
            log_success "git-flow 验证成功 (版本: $version)"
        else
            log_error "git-flow 安装后验证失败，请手动安装: https://github.com/gittower/git-flow-next/"
            return 1
        fi
    else
        local version=$(git flow version)
        log_success "git-flow 已安装 (版本: $version)"
    fi 
}

# ==============================================================================
# 环境设置函数
# ==============================================================================

# 设置环境变量
setup_environment_variables() {
    log_info "设置环境变量..."
    
    # 创建 .env 文件（如果不存在）
    if [ ! -f ".env" ]; then
        cat > .env << EOF
# Agentic Loop Protocol 环境变量
export PYTHONPATH="./alp"
export ALP_ENV=development
export ALP_LOG_LEVEL=INFO
EOF
        log_success "已创建 .env 文件"
    else
        log_success ".env 文件已存在"
    fi
    
    # 加载环境变量
    source .env
    log_success "环境变量已加载"
}

# 创建并激活虚拟环境
setup_virtual_env() {
    log_info "设置项目虚拟环境..."
    
    # 使用 uv 创建虚拟环境
    if [ ! -d ".venv" ]; then
        log_info "创建虚拟环境..."
        uv venv
        log_success "虚拟环境创建完成"
    else
        log_success "虚拟环境已存在"
    fi
    
    # 激活虚拟环境
    log_info "激活虚拟环境..."
    source .venv/bin/activate
    
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        log_success "虚拟环境激活成功"
        
        # 确保 uv 在虚拟环境中可用
        if ! command_exists uv; then
            log_warning "虚拟环境中 uv 不可用，正在修复..."
            if [[ -f "$HOME/.local/bin/uv" ]]; then
                ln -sf "$HOME/.local/bin/uv" ".venv/bin/uv"
                log_success "已创建 uv 软链接到虚拟环境"
            else
                log_error "无法修复虚拟环境中的 uv，请手动修复"
                exit 1
            fi
        fi
    else
        log_error "虚拟环境激活失败"
        exit 1
    fi
}

# 安装项目依赖
install_dependencies() {
    log_info "安装项目依赖..."
    
    # 如果存在 pyproject.toml，使用 uv 安装
    if [ -f "pyproject.toml" ]; then
        uv pip install -e .
    elif [ -f "requirements.txt" ]; then
        uv pip install -r requirements.txt
    else
        log_warning "未找到依赖文件，跳过依赖安装"
    fi
    
    log_success "依赖安装完成"
}


# 初始化 git-flow（如果需要）
init_git_flow() {
    if [ -d ".git" ] && ! git config --get gitflow.branch.master >/dev/null 2>&1; then
        log_info "初始化 git-flow..."
        git flow init -d
        log_success "git-flow 初始化完成"
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

# 主函数 - 协调所有初始化步骤
main() {
    log_info "开始初始化 Agentic Loop Protocol 开发环境..."
    echo "========================================================"
    
    # 设置环境变量
    setup_environment_variables

    # 检查并安装必要的工具
    install_git
    install_uv
    install_git_flow
    
    # 设置虚拟环境
    setup_virtual_env
    
    # 安装依赖
    install_dependencies
    
    # 初始化 git-flow
    init_git_flow
    
    echo "========================================================"
    log_success "环境初始化完成！"
}

# ==============================================================================
# 脚本入口点
# ==============================================================================

# 运行主函数
main "$@"
