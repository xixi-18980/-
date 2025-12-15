#!/bin/bash

# Spring REST自动化测试主脚本
# 支持员工管理和订单管理功能测试

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 显示标题
print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║    Spring REST API 自动化测试套件        ║"
    echo "║          版本 2.0.0                      ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js未安装"
        log_info "请访问: https://nodejs.org/"
        exit 1
    fi
    log_success "Node.js $(node --version)"
    
    # 检查Newman
    if ! command -v newman &> /dev/null; then
        log_warning "Newman未安装，正在安装..."
        npm install -g newman newman-reporter-html newman-reporter-junitfull
    fi
    log_success "Newman $(newman --version)"
    
    # 检查jq（用于解析JSON）
    if ! command -v jq &> /dev/null; then
        log_warning "jq未安装，正在安装..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        elif [[ -f /etc/debian_version ]]; then
            sudo apt-get install -y jq
        elif [[ -f /etc/redhat-release ]]; then
            sudo yum install -y jq
        fi
    fi
    log_success "jq $(jq --version)"
}

# 创建目录结构
setup_directories() {
    log_info "设置目录结构..."
    
    local dirs=(
        "postman/collections"
        "postman/environments"
        "postman/data"
        "scripts"
        "newman"
        "reports/html"
        "reports/json"
        "reports/junit"
        "ci-cd"
        "logs"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    log_success "目录结构创建完成"
}

# 创建默认环境文件
create_environment_file() {
    log_info "创建环境配置文件..."
    
    local env_file="postman/environments/local-environment.json"
    
    if [[ ! -f "$env_file" ]]; then
        cat > "$env_file" << 'EOF'
{
    "id": "local-environment",
    "name": "Spring REST Local",
    "values": [
        {
            "key": "base_url",
            "value": "http://localhost:8080",
            "type": "default",
            "enabled": true
        },
        {
            "key": "timestamp",
            "value": "",
            "type": "any",
            "enabled": true
        },
        {
            "key": "createdEmployeeId",
            "value": "",
            "type": "any",
            "enabled": true
        },
        {
            "key": "createdEmployeeName",
            "value": "",
            "type": "any",
            "enabled": true
        },
        {
            "key": "selfLink",
            "value": "",
            "type": "any",
            "enabled": true
        },
        {
            "key": "lastDeletedEmployeeId",
            "value": "",
            "type": "any",
            "enabled": true
        }
    ],
    "_postman_variable_scope": "environment",
    "_postman_exported_at": "",
    "_postman_exported_using": "Postman"
}
EOF
        log_success "环境文件创建: $env_file"
    else
        log_info "环境文件已存在: $env_file"
    fi
}

# 创建测试数据文件
create_test_data_file() {
    log_info "创建测试数据文件..."
    
    local data_file="postman/data/test-data.json"
    
    if [[ ! -f "$data_file" ]]; then
        cat > "$data_file" << 'EOF'
[
    {
        "test_id": "employee_001",
        "test_name": "创建普通员工",
        "firstName": "John",
        "lastName": "Doe",
        "role": "Software Engineer",
        "expected_status": 201
    },
    {
        "test_id": "employee_002",
        "test_name": "创建经理员工",
        "firstName": "Jane",
        "lastName": "Smith",
        "role": "Engineering Manager",
        "expected_status": 201
    },
    {
        "test_id": "order_001",
        "test_name": "创建电子产品订单",
        "description": "MacBook Pro 16-inch",
        "expected_status": 201
    },
    {
        "test_id": "order_002",
        "test_name": "创建办公用品订单",
        "description": "Office Chair",
        "expected_status": 201
    },
    {
        "test_id": "invalid_employee",
        "test_name": "无效员工数据测试",
        "firstName": "",
        "lastName": "",
        "role": "",
        "expected_status": 400
    }
]
EOF
        log_success "测试数据文件创建: $data_file"
    fi
}

# 检查应用状态
check_application_status() {
    log_info "检查Spring Boot应用状态..."
    
    local base_url="http://localhost:8080"
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -f "$base_url/employees" > /dev/null 2>&1; then
            log_success "应用正常运行在 $base_url"
            return 0
        elif curl -s -f "$base_url" > /dev/null 2>&1; then
            log_success "应用响应在 $base_url"
            return 0
        fi
        
        log_info "等待应用启动... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    log_error "应用未在 $base_url 启动"
    log_info "请确保Spring Boot应用已启动:"
    log_info "  cd tut-rest/complete && ./mvnw spring-boot:run"
    return 1
}

# 运行员工管理测试
run_employee_tests() {
    log_info "运行员工管理功能测试..."
    
    local collection="postman/collections/Tut-Rest-Tests.postman_collection.json"
    local environment="postman/environments/local-environment.json"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_prefix="employee-tests-$timestamp"
    
    # 只运行员工管理相关请求
    echo ""
    echo -e "${BLUE}员工管理测试配置:${NC}"
    echo "集合: $(basename "$collection")"
    echo "环境: $(basename "$environment")"
    echo "报告: $report_prefix"
    echo ""
    
    # 创建临时Collection只包含员工管理
    local temp_collection="postman/collections/employee-tests-temp.json"
    
    # 提取员工管理相关item
    jq 'del(.item[] | select(.name != "员工管理功能"))' "$collection" > "$temp_collection"
    
    newman run "$temp_collection" \
        --environment "$environment" \
        --iteration-count 1 \
        --reporters cli,json,html,junit \
        --reporter-json-export "reports/json/$report_prefix.json" \
        --reporter-html-export "reports/html/$report_prefix.html" \
        --reporter-junit-export "reports/junit/$report_prefix.xml" \
        --delay-request 1000 \
        --timeout 90000 \
        --timeout-request 15000 \
        --timeout-script 10000 \
        --suppress-exit-code
    
    local exit_code=$?
    
    # 清理临时文件
    rm -f "$temp_collection"
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "员工管理测试完成"
    else
        log_warning "员工管理测试中有失败用例"
    fi
    
    return $exit_code
}

# 运行订单管理测试
run_order_tests() {
    log_info "运行订单管理功能测试..."
    
    local collection="postman/collections/Tut-Rest-Tests.postman_collection.json"
    local environment="postman/environments/local-environment.json"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_prefix="order-tests-$timestamp"
    
    echo ""
    echo -e "${BLUE}订单管理测试配置:${NC}"
    echo "集合: $(basename "$collection")"
    echo "环境: $(basename "$environment")"
    echo "报告: $report_prefix"
    echo ""
    
    # 创建临时Collection只包含订单管理
    local temp_collection="postman/collections/order-tests-temp.json"
    
    # 提取订单管理相关item
    jq 'del(.item[] | select(.name != "订单管理功能"))' "$collection" > "$temp_collection"
    
    newman run "$temp_collection" \
        --environment "$environment" \
        --iteration-count 1 \
        --reporters cli,json,html,junit \
        --reporter-json-export "reports/json/$report_prefix.json" \
        --reporter-html-export "reports/html/$report_prefix.html" \
        --reporter-junit-export "reports/junit/$report_prefix.xml" \
        --delay-request 1000 \
        --timeout 90000 \
        --timeout-request 15000 \
        --timeout-script 10000 \
        --suppress-exit-code
    
    local exit_code=$?
    
    # 清理临时文件
    rm -f "$temp_collection"
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "订单管理测试完成"
    else
        log_warning "订单管理测试中有失败用例"
    fi
    
    return $exit_code
}

# 运行接口测试（带测试脚本的）
run_interface_tests() {
    log_info "运行接口测试（带验证脚本）..."
    
    local collection="postman/collections/Tut-Rest-Tests.postman_collection.json"
    local environment="postman/environments/local-environment.json"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_prefix="interface-tests-$timestamp"
    
    echo ""
    echo -e "${BLUE}接口测试配置:${NC}"
    echo "集合: $(basename "$collection")"
    echo "环境: $(basename "$environment")"
    echo "报告: $report_prefix"
    echo ""
    
    # 创建临时Collection只包含接口测试
    local temp_collection="postman/collections/interface-tests-temp.json"
    
    # 提取接口测试相关item
    jq 'del(.item[] | select(.name != "接口测试"))' "$collection" > "$temp_collection"
    
    newman run "$temp_collection" \
        --environment "$environment" \
        --iteration-count 1 \
        --reporters cli,json,html,junit \
        --reporter-json-export "reports/json/$report_prefix.json" \
        --reporter-html-export "reports/html/$report_prefix.html" \
        --reporter-junit-export "reports/junit/$report_prefix.xml" \
        --delay-request 1500 \
        --timeout 120000 \
        --timeout-request 20000 \
        --timeout-script 15000
    
    local exit_code=$?
    
    # 清理临时文件
    rm -f "$temp_collection"
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "接口测试完成"
    else
        log_warning "接口测试中有失败用例"
    fi
    
    return $exit_code
}

# 运行完整测试套件
run_full_test_suite() {
    log_info "运行完整测试套件..."
    
    local collection="postman/collections/Tut-Rest-Tests.postman_collection.json"
    local environment="postman/environments/local-environment.json"
    local data_file="postman/data/test-data.json"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local report_prefix="full-suite-$timestamp"
    
    echo ""
    echo -e "${BLUE}完整测试套件配置:${NC}"
    echo "集合: $(basename "$collection")"
    echo "环境: $(basename "$environment")"
    echo "数据: $(basename "$data_file")"
    echo "报告: $report_prefix"
    echo ""
    
    # 检查是否使用数据驱动
    local newman_cmd="newman run \"$collection\" \
        --environment \"$environment\" \
        --iteration-count 1 \
        --reporters cli,json,html,junit \
        --reporter-json-export \"reports/json/$report_prefix.json\" \
        --reporter-html-export \"reports/html/$report_prefix.html\" \
        --reporter-junit-export \"reports/junit/$report_prefix.xml\" \
        --delay-request 1000 \
        --timeout 180000 \
        --timeout-request 30000 \
        --timeout-script 20000"
    
    if [[ -f "$data_file" ]]; then
        newman_cmd="$newman_cmd --iteration-data \"$data_file\""
        log_info "使用数据驱动测试: $(basename "$data_file")"
    fi
    
    eval $newman_cmd
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "完整测试套件执行完成"
    else
        log_error "完整测试套件执行失败"
    fi
    
    return $exit_code
}

# 生成测试报告摘要
generate_test_summary() {
    log_info "生成测试报告摘要..."
    
    # 查找最新的JSON报告
    local latest_report=$(ls -t reports/json/*.json 2>/dev/null | head -1)
    
    if [[ -z "$latest_report" ]]; then
        log_warning "未找到测试报告"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                  测试报告摘要                            ${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 使用jq解析报告
    local total_tests=$(jq '.run.stats.tests.total // 0' "$latest_report")
    local failed_tests=$(jq '.run.stats.tests.failed // 0' "$latest_report")
    local passed_tests=$((total_tests - failed_tests))
    
    local total_requests=$(jq '.run.stats.requests.total // 0' "$latest_report")
    local failed_requests=$(jq '.run.stats.requests.failed // 0' "$latest_report")
    
    local total_time=$(( $(jq '.run.timings.completed // 0' "$latest_report") - $(jq '.run.timings.started // 0' "$latest_report") ))
    total_time=$((total_time / 1000))  # 转换为秒
    
    # 计算通过率
    local pass_rate=0
    if [[ $total_tests -gt 0 ]]; then
        pass_rate=$((passed_tests * 100 / total_tests))
    fi
    
    # 显示统计信息
    echo -e "📊 ${BLUE}统计信息:${NC}"
    echo "----------------------------------------"
    printf "%-20s: %4d\n" "总请求数" "$total_requests"
    printf "%-20s: %4d\n" "失败请求" "$failed_requests"
    printf "%-20s: %4d\n" "总测试数" "$total_tests"
    printf "%-20s: %4d\n" "通过测试" "$passed_tests"
    printf "%-20s: %4d\n" "失败测试" "$failed_tests"
    printf "%-20s: %4d%%\n" "通过率" "$pass_rate"
    printf "%-20s: %4d秒\n" "总耗时" "$total_time"
    echo ""
    
    # 显示失败详情
    if [[ $failed_tests -gt 0 ]]; then
        echo -e "❌ ${RED}失败详情:${NC}"
        echo "----------------------------------------"
        
        jq -r '
        .run.failures[] | 
        "测试: " + (.source.name // "Unknown") + "\n" +
        "错误: " + (.error.message // "Unknown error") + "\n" +
        "断言: " + (.error.test // "Unknown test") + "\n" +
        "----------------------------------------"
        ' "$latest_report" 2>/dev/null || echo "无法解析失败详情"
        
        echo ""
    fi
    
    # 显示报告文件位置
    local html_report=$(find reports/html -name "*.html" -newer "$latest_report" 2>/dev/null | head -1)
    local junit_report=$(find reports/junit -name "*.xml" -newer "$latest_report" 2>/dev/null | head -1)
    
    echo -e "📁 ${BLUE}报告文件:${NC}"
    echo "----------------------------------------"
    [[ -f "$latest_report" ]] && echo "JSON报告: $latest_report"
    [[ -f "$html_report" ]] && echo "HTML报告: $html_report"
    [[ -f "$junit_report" ]] && echo "JUnit报告: $junit_report"
    echo ""
    
    # 返回测试状态
    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}✅ 所有测试通过！${NC}"
        return 0
    else
        echo -e "${RED}❌ 有 $failed_tests 个测试失败${NC}"
        return 1
    fi
}

# 清理旧报告
cleanup_old_reports() {
    log_info "清理旧测试报告..."
    
    # 保留最近5个报告
    for dir in reports/html reports/json reports/junit; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -name "*.html" -o -name "*.json" -o -name "*.xml" | \
            sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
        fi
    done
    
    log_success "清理完成"
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --setup          仅设置环境，不运行测试"
    echo "  --employees      只运行员工管理测试"
    echo "  --orders         只运行订单管理测试"
    echo "  --interface      只运行接口测试"
    echo "  --full           运行完整测试套件（默认）"
    echo "  --summary        只生成报告摘要"
    echo "  --clean          清理旧报告"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                    # 运行完整测试"
    echo "  $0 --employees        # 只测试员工管理"
    echo "  $0 --summary          # 生成最新报告摘要"
    echo ""
}

# 主函数
main() {
    print_banner
    
    # 默认运行完整测试
    local run_mode="full"
    local skip_deps=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --setup)
                run_mode="setup"
                shift
                ;;
            --employees)
                run_mode="employees"
                shift
                ;;
            --orders)
                run_mode="orders"
                shift
                ;;
            --interface)
                run_mode="interface"
                shift
                ;;
            --full)
                run_mode="full"
                shift
                ;;
            --summary)
                run_mode="summary"
                skip_deps=true
                shift
                ;;
            --clean)
                run_mode="clean"
                skip_deps=true
                shift
                ;;
            --skip-deps)
                skip_deps=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 根据模式执行
    case $run_mode in
        setup)
            check_dependencies
            setup_directories
            create_environment_file
            create_test_data_file
            log_success "环境设置完成"
            ;;
        employees)
            [[ "$skip_deps" = false ]] && check_dependencies
            check_application_status
            run_employee_tests
            generate_test_summary
            cleanup_old_reports
            ;;
        orders)
            [[ "$skip_deps" = false ]] && check_dependencies
            check_application_status
            run_order_tests
            generate_test_summary
            cleanup_old_reports
            ;;
        interface)
            [[ "$skip_deps" = false ]] && check_dependencies
            check_application_status
            run_interface_tests
            generate_test_summary
            cleanup_old_reports
            ;;
        full)
            [[ "$skip_deps" = false ]] && check_dependencies
            check_application_status
            run_full_test_suite
            generate_test_summary
            cleanup_old_reports
            ;;
        summary)
            generate_test_summary
            ;;
        clean)
            cleanup_old_reports
            ;;
    esac
}

# 运行主函数
main "$@"
