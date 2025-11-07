#!/bin/bash

# Agentic Loop Protocol 环境初始化脚本
# 功能：检查并安装必要工具、启动虚拟环境、设置环境变量

# set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO   ]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR. ]${NC} $1"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查并安装 uv
install_uv() {
    if ! command_exists uv; then
        log_info "正在安装 uv..."
        # 使用官方安装脚本
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # 重新加载 PATH
        export PATH="$HOME/.cargo/bin:$PATH"
        
        # 添加到 shell 配置文件
        if [[ -f "$HOME/.bashrc" ]]; then
            echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.zshrc"
        fi
        
        log_success "uv 安装完成"
    else
        log_success "uv 已安装"
    fi
}

# 检查并安装 git
install_git() {
    if ! command_exists git; then
        log_info "正在安装 git..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y git
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install git
        else
            log_error "请手动安装 git: https://git-scm.com/downloads"
            exit 1
        fi
        log_success "git 安装完成"
    else
        log_success "git 已安装"
    fi
}

# 检查并安装 git-flow
install_git_flow() {
    if ! git flow version >/dev/null 2>&1; then
        log_info "正在安装 git-flow..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get install -y git-flow
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install git-flow-avh
        else
            log_error "请手动安装 git-flow"
            exit 1
        fi
        log_success "git-flow 安装完成"
    else
        log_success "git-flow 已安装"
    fi
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

# 初始化 git-flow（如果需要）
init_git_flow() {
    if [ -d ".git" ] && ! git config --get gitflow.branch.master >/dev/null 2>&1; then
        log_info "初始化 git-flow..."
        git flow init -d
        log_success "git-flow 初始化完成"
    fi
}

# 主函数
main() {
    log_info "开始初始化 Agentic Loop Protocol 开发环境..."
    echo "================================================"
    
    # 检查并安装必要的工具
    install_git
    install_uv
    install_git_flow
    
    # 设置虚拟环境
    setup_virtual_env
    
    # 安装依赖
    install_dependencies
    
    # 设置环境变量
    setup_environment_variables
    
    # 初始化 git-flow
    init_git_flow
    
    echo "================================================"
    log_success "环境初始化完成！"
}

# 运行主函数
main "$@"
