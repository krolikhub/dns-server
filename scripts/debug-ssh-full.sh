#!/bin/bash
#
# ПОЛНЫЙ ДЕБАГ SSH СОЕДИНЕНИЯ
# Этот скрипт показывает ВСЁ что происходит с SSH на каждом шаге
#

set +e  # Не останавливаемся при ошибках

VM_NAME="dns-server"
VM_IP="192.168.200.100"
SSH_PORT="22"
SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/id_rsa"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    ПОЛНЫЙ ДЕБАГ SSH СОЕДИНЕНИЯ                               ║"
echo "║                                                                              ║"
echo "║  Этот скрипт покажет ВСЁ что происходит с SSH и почему не подключается      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

step=1
print_step() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ ШАГ $step: $1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    ((step++))
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ============================================================================
# ШАГ 1: ПРОВЕРКА СТАТУСА VM
# ============================================================================
print_step "ПРОВЕРКА СТАТУСА ВИРТУАЛЬНОЙ МАШИНЫ"

if ! command -v virsh &> /dev/null; then
    print_warning "virsh не установлен - пропускаем проверку VM"
    VM_EXISTS="unknown"
else
    print_info "Проверяем существует ли VM '$VM_NAME'..."

    if sudo virsh list --all | grep -q "$VM_NAME"; then
        print_success "VM '$VM_NAME' найдена"

        echo ""
        print_info "Полный список всех VM:"
        sudo virsh list --all | sed 's/^/  /'

        echo ""
        print_info "Статус VM '$VM_NAME':"
        VM_STATE=$(sudo virsh domstate "$VM_NAME" 2>&1)
        echo "  $VM_STATE"

        if [ "$VM_STATE" == "running" ]; then
            print_success "VM запущена"
            VM_EXISTS="running"
        else
            print_error "VM НЕ ЗАПУЩЕНА!"
            print_info "Попробуйте запустить: sudo virsh start $VM_NAME"
            VM_EXISTS="stopped"
        fi

        echo ""
        print_info "Информация о VM:"
        sudo virsh dominfo "$VM_NAME" | sed 's/^/  /'

    else
        print_error "VM '$VM_NAME' НЕ НАЙДЕНА"
        print_info "Создайте VM через: cd examples/local && terraform apply"
        VM_EXISTS="no"
        exit 1
    fi
fi

# ============================================================================
# ШАГ 2: ПРОВЕРКА СЕТЕВОГО ПОДКЛЮЧЕНИЯ
# ============================================================================
print_step "ПРОВЕРКА СЕТЕВОГО ПОДКЛЮЧЕНИЯ К VM"

print_info "Пингуем VM IP: $VM_IP"
if ping -c 3 -W 2 "$VM_IP" &> /dev/null; then
    print_success "Ping успешен - VM доступна в сети"
    NETWORK_OK="yes"
else
    print_error "Ping не проходит - VM недоступна в сети"
    print_warning "Возможные причины:"
    echo "  1. VM не запущена"
    echo "  2. Сеть не настроена"
    echo "  3. IP адрес неверный"
    NETWORK_OK="no"
fi

echo ""
print_info "Проверяем доступность SSH порта $SSH_PORT..."
if timeout 3 bash -c "echo > /dev/tcp/$VM_IP/$SSH_PORT" 2>/dev/null; then
    print_success "Порт $SSH_PORT ОТКРЫТ - SSH сервер слушает"
    SSH_PORT_OPEN="yes"
else
    print_error "Порт $SSH_PORT ЗАКРЫТ - SSH сервер не отвечает"
    print_warning "Возможные причины:"
    echo "  1. SSH сервер не запущен"
    echo "  2. Firewall блокирует порт"
    echo "  3. VM еще не загрузилась полностью"
    SSH_PORT_OPEN="no"
fi

echo ""
print_info "Проверяем SSH баннер (что отвечает сервер)..."
SSH_BANNER=$(timeout 3 nc -w 2 "$VM_IP" "$SSH_PORT" < /dev/null 2>/dev/null | head -n 1)
if [ -n "$SSH_BANNER" ]; then
    print_success "SSH сервер отвечает: $SSH_BANNER"
else
    print_error "SSH сервер не отвечает (нет баннера)"
fi

# ============================================================================
# ШАГ 3: ПРОВЕРКА SSH КЛЮЧЕЙ НА ЛОКАЛЬНОЙ МАШИНЕ
# ============================================================================
print_step "ПРОВЕРКА SSH КЛЮЧЕЙ НА ЛОКАЛЬНОЙ МАШИНЕ"

print_info "Проверяем наличие SSH ключей..."
echo ""

if [ -f "$SSH_KEY" ]; then
    print_success "Приватный ключ найден: $SSH_KEY"
    ls -lh "$SSH_KEY" | sed 's/^/  /'

    echo ""
    print_info "Права доступа к приватному ключу:"
    PERMS=$(stat -c "%a" "$SSH_KEY")
    echo "  Текущие права: $PERMS"
    if [ "$PERMS" == "600" ] || [ "$PERMS" == "400" ]; then
        print_success "Права корректные"
    else
        print_warning "Права могут быть слишком открытыми (рекомендуется 600)"
        print_info "Исправить: chmod 600 $SSH_KEY"
    fi
else
    print_error "Приватный ключ НЕ найден: $SSH_KEY"
fi

echo ""
if [ -f "$SSH_KEY.pub" ]; then
    print_success "Публичный ключ найден: $SSH_KEY.pub"
    echo ""
    print_info "Содержимое публичного ключа:"
    cat "$SSH_KEY.pub" | sed 's/^/  /'
else
    print_warning "Публичный ключ не найден: $SSH_KEY.pub"
fi

echo ""
print_info "Список всех SSH ключей в ~/.ssh/:"
ls -lh ~/.ssh/*.pub 2>/dev/null | sed 's/^/  /' || echo "  Нет публичных ключей"

# ============================================================================
# ШАГ 4: ПОПЫТКА ПОДКЛЮЧЕНИЯ С ДЕТАЛЬНЫМ ВЫВОДОМ
# ============================================================================
print_step "ПОПЫТКА SSH ПОДКЛЮЧЕНИЯ С МАКСИМАЛЬНОЙ ДЕТАЛИЗАЦИЕЙ"

print_info "Пробуем подключиться с verbose режимом (покажет все шаги)..."
echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "КОМАНДА: ssh -vvv -o ConnectTimeout=10 -o StrictHostKeyChecking=no $SSH_USER@$VM_IP exit"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

SSH_OUTPUT=$(timeout 15 ssh -vvv -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" exit 2>&1)
SSH_EXITCODE=$?

echo "$SSH_OUTPUT" | sed 's/^/  /'

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "Exit code: $SSH_EXITCODE"
echo "════════════════════════════════════════════════════════════════════════════════"

# Анализируем вывод
echo ""
print_info "АНАЛИЗ ВЫВОДА SSH:"
echo ""

if echo "$SSH_OUTPUT" | grep -q "Connection refused"; then
    print_error "ПРОБЛЕМА: Connection refused - SSH сервер не принимает соединения"
    echo "  Причины:"
    echo "    - SSH сервер не запущен"
    echo "    - Неправильный порт"
fi

if echo "$SSH_OUTPUT" | grep -q "Connection timed out"; then
    print_error "ПРОБЛЕМА: Connection timed out - VM не отвечает"
    echo "  Причины:"
    echo "    - VM не запущена"
    echo "    - Сетевые проблемы"
    echo "    - Firewall блокирует"
fi

if echo "$SSH_OUTPUT" | grep -q "Permission denied (publickey)"; then
    print_error "ПРОБЛЕМА: Permission denied (publickey) - разрешена только аутентификация по ключу"
    echo "  Это означает что:"
    echo "    - PasswordAuthentication отключен (=no)"
    echo "    - SSH принимает только ключи"
    echo "    - Пароли не запрашиваются"
fi

if echo "$SSH_OUTPUT" | grep -q "no mutual signature algorithm"; then
    print_error "ПРОБЛЕМА: Несовместимые алгоритмы подписи"
fi

if echo "$SSH_OUTPUT" | grep -q "Host key verification failed"; then
    print_warning "ПРОБЛЕМА: Host key verification failed - ключ хоста изменился"
    echo "  Исправить: ssh-keygen -R $VM_IP"
fi

if [ $SSH_EXITCODE -eq 0 ]; then
    print_success "SSH подключение УСПЕШНО!"
fi

# ============================================================================
# ШАГ 5: ТЕСТ ПОДКЛЮЧЕНИЯ ПО SSH КЛЮЧУ
# ============================================================================
print_step "ТЕСТ ПОДКЛЮЧЕНИЯ ПО SSH КЛЮЧУ"

if [ -f "$SSH_KEY" ]; then
    print_info "Пробуем подключиться используя SSH ключ..."
    echo ""
    echo "КОМАНДА: ssh -i $SSH_KEY -o StrictHostKeyChecking=no $SSH_USER@$VM_IP echo 'KEY AUTH WORKS'"
    echo ""

    KEY_AUTH_OUTPUT=$(timeout 10 ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$VM_IP" "echo 'KEY AUTH WORKS'" 2>&1)
    KEY_AUTH_EXIT=$?

    echo "$KEY_AUTH_OUTPUT" | sed 's/^/  /'
    echo ""

    if [ $KEY_AUTH_EXIT -eq 0 ] && echo "$KEY_AUTH_OUTPUT" | grep -q "KEY AUTH WORKS"; then
        print_success "Аутентификация по ключу РАБОТАЕТ!"
        KEY_AUTH_WORKS="yes"
    else
        print_error "Аутентификация по ключу НЕ работает"
        KEY_AUTH_WORKS="no"
    fi
else
    print_warning "SSH ключ не найден - пропускаем тест"
    KEY_AUTH_WORKS="no_key"
fi

# ============================================================================
# ШАГ 6: ПОЛУЧЕНИЕ SSH КОНФИГУРАЦИИ С VM
# ============================================================================
print_step "ПОЛУЧЕНИЕ SSH КОНФИГУРАЦИИ С ВИРТУАЛЬНОЙ МАШИНЫ"

if [ "$KEY_AUTH_WORKS" == "yes" ]; then
    print_success "Можем получить информацию с VM через SSH ключ"
    echo ""

    # Эффективная конфигурация SSH
    print_info "═══ ЭФФЕКТИВНАЯ SSH КОНФИГУРАЦИЯ (sshd -T) ═══"
    echo ""
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo sshd -T 2>&1" | grep -E '(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|pubkeyauthentication|usepam|challengeresponseauthentication)' | sed 's/^/  /'

    echo ""
    echo ""

    # Список конфиг файлов
    print_info "═══ СПИСОК КОНФИГУРАЦИОННЫХ ФАЙЛОВ SSH ═══"
    echo ""
    print_info "Содержимое /etc/ssh/sshd_config.d/:"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "ls -la /etc/ssh/sshd_config.d/ 2>&1" | sed 's/^/  /'

    echo ""
    echo ""

    # Содержимое конфигов
    print_info "═══ СОДЕРЖИМОЕ КОНФИГУРАЦИОННЫХ ФАЙЛОВ ═══"
    echo ""

    CONFIG_FILES=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "ls /etc/ssh/sshd_config.d/*.conf 2>/dev/null" 2>/dev/null)

    if [ -n "$CONFIG_FILES" ]; then
        for conf_file in $CONFIG_FILES; do
            print_info "Файл: $conf_file"
            echo "────────────────────────────────────────────────────────────────────────────"
            ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo cat $conf_file 2>&1" | sed 's/^/  /'
            echo "────────────────────────────────────────────────────────────────────────────"
            echo ""
        done
    else
        print_warning "Нет конфигурационных файлов в sshd_config.d/"
    fi

    echo ""
    print_info "═══ ОСНОВНОЙ КОНФИГ /etc/ssh/sshd_config (только PasswordAuthentication) ═══"
    echo ""
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo grep -E '^[^#]*PasswordAuthentication' /etc/ssh/sshd_config 2>&1" | sed 's/^/  /'

    echo ""
    echo ""

    # Статус SSH сервиса
    print_info "═══ СТАТУС SSH СЕРВИСА ═══"
    echo ""
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo systemctl status ssh --no-pager -l 2>&1" | sed 's/^/  /'

    echo ""
    echo ""

    # Логи SSH
    print_info "═══ ПОСЛЕДНИЕ 20 СТРОК ЛОГОВ SSH ═══"
    echo ""
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo journalctl -u ssh -n 20 --no-pager 2>&1" | sed 's/^/  /'

    echo ""
    echo ""

    # Проверка пользователя ubuntu
    print_info "═══ ИНФОРМАЦИЯ О ПОЛЬЗОВАТЕЛЕ $SSH_USER ═══"
    echo ""
    print_info "Запись в /etc/passwd:"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "getent passwd $SSH_USER 2>&1" | sed 's/^/  /'

    echo ""
    print_info "Запись в /etc/shadow (только статус пароля):"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo passwd -S $SSH_USER 2>&1" | sed 's/^/  /'

    PASSWORD_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "sudo passwd -S $SSH_USER 2>&1")
    if echo "$PASSWORD_STATUS" | grep -q " P "; then
        print_success "У пользователя $SSH_USER УСТАНОВЛЕН пароль"
    else
        print_error "У пользователя $SSH_USER НЕ УСТАНОВЛЕН пароль"
        print_info "Установить пароль: sudo passwd $SSH_USER"
    fi

    echo ""
    print_info "Проверяем ~/.ssh/authorized_keys:"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$VM_IP" "cat ~/.ssh/authorized_keys 2>&1" | sed 's/^/  /'

elif [ "$VM_EXISTS" == "running" ]; then
    print_warning "Не можем подключиться по SSH ключу"
    print_info "Попробуем получить информацию через virsh console..."
    echo ""

    if command -v virsh &> /dev/null; then
        print_info "Создаем скрипт для выполнения через virsh console..."

        CONSOLE_SCRIPT=$(cat <<'SCRIPT_EOF'
#!/bin/bash
echo "=== SSH CONFIGURATION DEBUG ==="
echo ""
echo "=== EFFECTIVE SSH CONFIG ==="
sshd -T | grep -E '(passwordauthentication|permitrootlogin|kbdinteractiveauthentication)'
echo ""
echo "=== CONFIG FILES ==="
ls -la /etc/ssh/sshd_config.d/
echo ""
echo "=== SSH SERVICE STATUS ==="
systemctl status ssh --no-pager
echo ""
echo "=== SSH LOGS ==="
journalctl -u ssh -n 10 --no-pager
SCRIPT_EOF
)

        print_warning "Для получения детальной информации нужен доступ по SSH ключу или через virsh console"
        print_info "Команда для virsh console: sudo virsh console $VM_NAME"
    fi
else
    print_error "VM не запущена - не можем получить конфигурацию"
fi

# ============================================================================
# ШАГ 7: ТЕСТ ПАРОЛЬНОЙ АУТЕНТИФИКАЦИИ
# ============================================================================
print_step "ТЕСТ ПАРОЛЬНОЙ АУТЕНТИФИКАЦИИ"

print_info "Проверяем запрашивается ли пароль при подключении..."
echo ""

print_info "КОМАНДА: ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $SSH_USER@$VM_IP"
echo ""
print_warning "Эта команда попытается подключиться ТОЛЬКО по паролю"
echo ""

# Используем timeout и expect для теста
if command -v expect &> /dev/null; then
    print_info "Используем expect для автоматического ввода пароля..."

    EXPECT_SCRIPT=$(cat <<'EXPECT_EOF'
set timeout 10
spawn ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no ubuntu@192.168.200.100 echo "PASSWORD AUTH WORKS"
expect {
    "password:" {
        send "ubuntu\r"
        expect {
            "PASSWORD AUTH WORKS" {
                puts "\n=== PASSWORD AUTH SUCCESS ==="
                exit 0
            }
            "Permission denied" {
                puts "\n=== PASSWORD WRONG OR AUTH FAILED ==="
                exit 1
            }
            timeout {
                puts "\n=== TIMEOUT AFTER PASSWORD ==="
                exit 1
            }
        }
    }
    "Permission denied (publickey)" {
        puts "\n=== PASSWORD AUTH DISABLED ==="
        exit 2
    }
    timeout {
        puts "\n=== CONNECTION TIMEOUT ==="
        exit 3
    }
}
EXPECT_EOF
)

    echo "$EXPECT_SCRIPT" > /tmp/ssh_test.exp
    EXPECT_OUTPUT=$(expect /tmp/ssh_test.exp 2>&1)
    EXPECT_EXIT=$?
    rm -f /tmp/ssh_test.exp

    echo "$EXPECT_OUTPUT" | sed 's/^/  /'
    echo ""

    case $EXPECT_EXIT in
        0)
            print_success "ПАРОЛЬНАЯ АУТЕНТИФИКАЦИЯ РАБОТАЕТ!"
            PASSWORD_AUTH_WORKS="yes"
            ;;
        2)
            print_error "ПАРОЛЬНАЯ АУТЕНТИФИКАЦИЯ ОТКЛЮЧЕНА (Permission denied publickey)"
            print_warning "Сервер НЕ ЗАПРАШИВАЕТ пароль - только ключи"
            PASSWORD_AUTH_WORKS="no"
            ;;
        *)
            print_error "ПАРОЛЬНАЯ АУТЕНТИФИКАЦИЯ не работает (код: $EXPECT_EXIT)"
            PASSWORD_AUTH_WORKS="no"
            ;;
    esac
else
    print_warning "expect не установлен - пропускаем автоматический тест"
    print_info "Попробуйте вручную: ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $SSH_USER@$VM_IP"
    PASSWORD_AUTH_WORKS="unknown"
fi

# ============================================================================
# ШАГ 8: ИТОГОВЫЙ АНАЛИЗ И РЕКОМЕНДАЦИИ
# ============================================================================
print_step "ИТОГОВЫЙ АНАЛИЗ И РЕКОМЕНДАЦИИ"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                              ИТОГОВЫЙ ОТЧЕТ                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Таблица статусов
printf "%-40s %s\n" "КОМПОНЕНТ" "СТАТУС"
echo "────────────────────────────────────────────────────────────────────────────────"
[ "$VM_EXISTS" == "running" ] && printf "%-40s ${GREEN}%s${NC}\n" "VM запущена:" "✓ ДА" || printf "%-40s ${RED}%s${NC}\n" "VM запущена:" "✗ НЕТ"
[ "$NETWORK_OK" == "yes" ] && printf "%-40s ${GREEN}%s${NC}\n" "Сеть доступна (ping):" "✓ ДА" || printf "%-40s ${RED}%s${NC}\n" "Сеть доступна (ping):" "✗ НЕТ"
[ "$SSH_PORT_OPEN" == "yes" ] && printf "%-40s ${GREEN}%s${NC}\n" "SSH порт открыт:" "✓ ДА" || printf "%-40s ${RED}%s${NC}\n" "SSH порт открыт:" "✗ НЕТ"
[ -f "$SSH_KEY" ] && printf "%-40s ${GREEN}%s${NC}\n" "SSH ключ найден:" "✓ ДА" || printf "%-40s ${YELLOW}%s${NC}\n" "SSH ключ найден:" "⚠ НЕТ"
[ "$KEY_AUTH_WORKS" == "yes" ] && printf "%-40s ${GREEN}%s${NC}\n" "Аутентификация по ключу:" "✓ РАБОТАЕТ" || printf "%-40s ${RED}%s${NC}\n" "Аутентификация по ключу:" "✗ НЕ РАБОТАЕТ"
[ "$PASSWORD_AUTH_WORKS" == "yes" ] && printf "%-40s ${GREEN}%s${NC}\n" "Парольная аутентификация:" "✓ РАБОТАЕТ" || printf "%-40s ${RED}%s${NC}\n" "Парольная аутентификация:" "✗ НЕ РАБОТАЕТ"
echo "────────────────────────────────────────────────────────────────────────────────"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                              РЕКОМЕНДАЦИИ                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Анализ и рекомендации
if [ "$PASSWORD_AUTH_WORKS" == "no" ]; then
    print_error "ОСНОВНАЯ ПРОБЛЕМА: Парольная аутентификация отключена на сервере"
    echo ""
    echo "  ЧТО ЭТО ОЗНАЧАЕТ:"
    echo "  ─────────────────"
    echo "  • SSH сервер настроен принимать ТОЛЬКО публичные ключи"
    echo "  • Пароли НЕ ЗАПРАШИВАЮТСЯ даже если они правильные"
    echo "  • В конфигурации SSH: PasswordAuthentication no"
    echo ""
    echo "  ПРИЧИНА:"
    echo "  ────────"
    echo "  • Cloud-init создал файл /etc/ssh/sshd_config.d/50-cloud-init.conf"
    echo "  • Этот файл содержит: PasswordAuthentication no"
    echo "  • SSH читает конфиги в алфавитном порядке"
    echo "  • Первая найденная директива побеждает"
    echo ""
    echo "  РЕШЕНИЕ:"
    echo "  ────────"
    if [ "$KEY_AUTH_WORKS" == "yes" ]; then
        print_success "У вас работает SSH ключ - можно исправить СЕЙЧАС!"
        echo ""
        echo "  Вариант 1: Автоматическое исправление (РЕКОМЕНДУЕТСЯ)"
        echo "    bash scripts/fix-existing-vm-ssh.sh"
        echo ""
        echo "  Вариант 2: Ручное исправление"
        echo "    ssh -i $SSH_KEY $SSH_USER@$VM_IP"
        echo "    sudo tee /etc/ssh/sshd_config.d/01-custom-auth.conf > /dev/null <<'EOF'"
        echo "    PasswordAuthentication yes"
        echo "    PermitRootLogin yes"
        echo "    KbdInteractiveAuthentication yes"
        echo "    PubkeyAuthentication yes"
        echo "    UsePAM yes"
        echo "    EOF"
        echo "    sudo rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf"
        echo "    sudo systemctl restart ssh"
    else
        print_warning "SSH ключ не работает - нужен другой подход"
        echo ""
        echo "  Вариант 1: Пересоздать VM (ПРОЩЕ ВСЕГО)"
        echo "    cd examples/local"
        echo "    bash ../../scripts/recreate-vm.sh"
        echo ""
        echo "  Вариант 2: Через virsh console"
        echo "    sudo virsh console $VM_NAME"
        echo "    # Затем выполнить команды из Варианта 2 выше"
    fi

elif [ "$PASSWORD_AUTH_WORKS" == "yes" ]; then
    print_success "ПАРОЛЬНАЯ АУТЕНТИФИКАЦИЯ РАБОТАЕТ!"
    echo ""
    echo "  Вы можете подключиться:"
    echo "    ssh $SSH_USER@$VM_IP"
    echo ""
    echo "  Пароль по умолчанию: ubuntu"

elif [ "$SSH_PORT_OPEN" == "no" ]; then
    print_error "SSH ПОРТ НЕ ОТКРЫТ"
    echo ""
    echo "  Возможные причины:"
    echo "  ──────────────────"
    echo "  1. SSH сервер не запущен на VM"
    echo "  2. VM еще не загрузилась (cloud-init работает)"
    echo "  3. Firewall блокирует порт 22"
    echo ""
    echo "  ЧТО ДЕЛАТЬ:"
    echo "  ───────────"
    echo "  1. Подождите 1-2 минуты (VM может еще загружаться)"
    echo "  2. Проверьте через console: sudo virsh console $VM_NAME"
    echo "  3. Проверьте статус SSH: sudo systemctl status ssh"

elif [ "$NETWORK_OK" == "no" ]; then
    print_error "VM НЕ ДОСТУПНА В СЕТИ"
    echo ""
    echo "  Проверьте:"
    echo "  ──────────"
    echo "  1. VM запущена: sudo virsh list"
    echo "  2. IP адрес правильный: sudo virsh domifaddr $VM_NAME"
    echo "  3. Сеть libvirt работает: sudo virsh net-list"

elif [ "$VM_EXISTS" != "running" ]; then
    print_error "VM НЕ ЗАПУЩЕНА"
    echo ""
    echo "  Запустить VM:"
    echo "    sudo virsh start $VM_NAME"
    echo ""
    echo "  Или пересоздать через Terraform:"
    echo "    cd examples/local"
    echo "    terraform apply"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         ПОЛЕЗНЫЕ КОМАНДЫ                                     ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Подключение по SSH ключу:"
echo "    ssh -i $SSH_KEY $SSH_USER@$VM_IP"
echo ""
echo "  Подключение по паролю (если работает):"
echo "    ssh $SSH_USER@$VM_IP"
echo ""
echo "  Консоль VM:"
echo "    sudo virsh console $VM_NAME"
echo "    (выход: Ctrl+])"
echo ""
echo "  Пересоздать VM:"
echo "    cd examples/local && bash ../../scripts/recreate-vm.sh"
echo ""
echo "  Исправить SSH на существующей VM:"
echo "    bash scripts/fix-existing-vm-ssh.sh"
echo ""
echo "  Логи cloud-init:"
echo "    ssh -i $SSH_KEY $SSH_USER@$VM_IP sudo tail -f /var/log/cloud-init-output.log"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                         КОНЕЦ ДЕБАГА                                         ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
