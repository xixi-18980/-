#!/bin/bash

# 自动化测试环境设置脚本

set -e

echo "=== Spring REST自动化测试环境设置 ==="
echo ""

# 检查是否在项目根目录
if [[ ! -f "run-tests.sh" ]]; then
    echo "错误: 请在项目根目录运行此脚本"
    exit 1
fi

# 1. 设置文件权限
echo "1. 设置脚本执行权限..."
chmod +x run-tests.sh
chmod +x cleanup-tests.sh
chmod +x scripts/*.sh 2>/dev/null || true
echo "✓ 权限设置完成"

# 2. 复制Collection文件
echo ""
echo "2. 检查Postman Collection文件..."

if [[ -f "../Tut-Rest-Tests.postman_collection.json" ]]; then
    cp "../Tut-Rest-Tests.postman_collection.json" "postman/collections/"
    echo "✓ Collection文件已复制"
elif [[ -f "postman/collections/Tut-Rest-Tests.postman_collection.json" ]]; then
    echo "✓ Collection文件已存在"
else
    echo "⚠️ 警告: 未找到Collection文件"
    echo "请将Tut-Rest-Tests.postman_collection.json放入postman/collections/目录"
fi

# 3. 创建目录结构
echo ""
echo "3. 创建目录结构..."
mkdir -p postman/{collections,environments,data}
mkdir -p scripts
mkdir -p newman
mkdir -p reports/{html,json,junit}
mkdir -p logs
mkdir -p ci-cd
echo "✓ 目录结构创建完成"

# 4. 创建默认环境文件
echo ""
echo "4. 创建默认环境配置..."

cat > postman/environments/local-environment.json << 'EOF'
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
        }
    ],
    "_postman_variable_scope": "environment"
}
EOF
echo "✓ 环境配置文件创建完成"

# 5. 创建测试数据
echo ""
echo "5. 创建测试数据文件..."

cat > postman/data/test-data.json << 'EOF'
[
    {
        "test_case": "创建员工测试1",
        "firstName": "John",
        "lastName": "Doe",
        "role": "Software Engineer",
        "expectedStatus": 201
    },
    {
        "test_case": "创建员工测试2",
        "firstName": "Jane",
        "lastName": "Smith",
        "role": "QA Engineer",
        "expectedStatus": 201
    },
    {
        "test_case": "创建订单测试1",
        "description": "Laptop Computer",
        "expectedStatus": 201
    },
    {
        "test_case": "创建订单测试2",
        "description": "Office Desk",
        "expectedStatus": 201
    }
]
EOF
echo "✓ 测试数据文件创建完成"

# 6. 安装Node.js依赖
echo ""
echo "6. 检查Node.js依赖..."

if ! command -v node &> /dev/null; then
    echo "❌ Node.js未安装"
    echo "请先安装Node.js: https://nodejs.org/"
    exit 1
fi

echo "✓ Node.js已安装: $(node --version)"

if ! command -v npm &> /dev/null; then
    echo "❌ npm未安装"
    exit 1
fi

echo "✓ npm已安装: $(npm --version)"

# 7. 安装Newman和相关报告器
echo ""
echo "7. 安装Newman测试工具..."

if ! command -v newman &> /dev/null; then
    echo "正在安装Newman..."
    npm install -g newman
else
    echo "✓ Newman已安装: $(newman --version)"
fi

# 安装报告器
echo "安装HTML报告器..."
npm install -g newman-reporter-html

echo "安装JUnit报告器..."
npm install -g newman-reporter-junitfull

# 8. 创建package.json
echo ""
echo "8. 创建项目配置文件..."

cat > package.json << 'EOF'
{
  "name": "spring-rest-automation-tests",
  "version": "2.0.0",
  "description": "Spring REST API自动化测试套件",
  "scripts": {
    "test": "./run-tests.sh",
    "test:employees": "./run-tests.sh --employees",
    "test:orders": "./run-tests.sh --orders",
    "test:interface": "./run-tests.sh --interface",
    "setup": "./setup-environment.sh",
    "clean": "./cleanup-tests.sh",
    "summary": "./run-tests.sh --summary",
    "report": "node scripts/generate-report.js"
  },
  "devDependencies": {
    "newman": "^6.0.0"
  },
  "keywords": [
    "api-testing",
    "spring-boot",
    "rest-api",
    "automation",
    "postman",
    "newman"
  ],
  "author": "Automation Team",
  "license": "MIT",
  "engines": {
    "node": ">=14.0.0"
  }
}
EOF

# 安装项目依赖
npm install

echo "✓ 项目配置完成"

# 9. 创建辅助脚本
echo ""
echo "9. 创建辅助脚本..."

# 启动应用脚本
cat > scripts/start-application.sh << 'EOF'
#!/bin/bash

# 启动Spring Boot应用

set -e

echo "=== 启动Spring Boot应用 ==="

# 检查应用目录
APP_DIR="../../tut-rest/complete"
if [[ ! -d "$APP_DIR" ]]; then
    echo "错误: 应用目录不存在"
    echo "请先克隆项目: git clone https://github.com/spring-guides/tut-rest.git"
    exit 1
fi

cd "$APP_DIR"

# 检查是否已运行
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo "应用已在运行"
    exit 0
fi

echo "启动应用..."
./mvnw spring-boot:run > ../../spring-rest-automation-tests/logs/app.log 2>&1 &

APP_PID=$!
echo $APP_PID > ../../spring-rest-automation-tests/scripts/app.pid

echo "应用启动中，PID: $APP_PID"
echo "日志文件: logs/app.log"

# 等待应用启动
for i in {1..30}; do
    if curl -s http://localhost:8080/employees > /dev/null 2>&1; then
        echo "✓ 应用启动成功"
        exit 0
    fi
    sleep 2
    echo -n "."
done

echo "❌ 应用启动超时"
kill $APP_PID 2>/dev/null || true
exit 1
EOF

chmod +x scripts/start-application.sh

# 停止应用脚本
cat > scripts/stop-application.sh << 'EOF'
#!/bin/bash

# 停止Spring Boot应用

set -e

echo "=== 停止Spring Boot应用 ==="

PID_FILE="scripts/app.pid"

if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    echo "停止应用进程: $PID"
    kill $PID 2>/dev/null && rm -f "$PID_FILE" && echo "✓ 应用已停止"
else
    echo "应用未运行或PID文件不存在"
fi
EOF

chmod +x scripts/stop-application.sh

# 验证删除脚本
cat > scripts/verify-deletion.sh << 'EOF'
#!/bin/bash

# 验证员工删除

set -e

echo "=== 验证员工删除 ==="

LAST_ID=$(jq -r '.values[] | select(.key=="lastDeletedEmployeeId") | .value' postman/environments/local-environment.json 2>/dev/null || echo "")

if [[ -z "$LAST_ID" || "$LAST_ID" == "null" ]]; then
    echo "没有找到最近删除的员工ID"
    exit 0
fi

echo "验证员工ID $LAST_ID 是否已删除..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/employees/$LAST_ID)

if [[ "$RESPONSE" == "404" ]]; then
    echo "✓ 员工 $LAST_ID 已成功删除"
else
    echo "⚠️ 员工 $LAST_ID 可能仍存在 (HTTP $RESPONSE)"
fi
EOF

chmod +x scripts/verify-deletion.sh

echo "✓ 辅助脚本创建完成"

# 10. 创建README.md
echo ""
echo "10. 创建项目文档..."

cat > README.md << 'EOF'
# Spring REST API自动化测试套件

基于Postman和Newman的Spring REST API自动化测试解决方案。

## 项目结构
