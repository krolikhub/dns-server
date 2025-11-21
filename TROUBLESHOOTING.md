# Решение проблем

## Проблема: Directory not empty при удалении storage pool

### Ошибка
```
Error: error deleting storage pool: failed to remove pool '/var/lib/libvirt/pools/dns-server': Directory not empty
```

### Причина
При выполнении `terraform destroy` libvirt не может удалить storage pool, потому что директория содержит файлы:
- Диски виртуальных машин (qcow2)
- Базовые образы
- Cloud-init ISO файлы
- Другие orphan-файлы

Это происходит когда:
1. Volumes не были корректно удалены из Terraform state
2. Файлы заблокированы запущенной VM
3. Остались файлы, не управляемые Terraform
4. Произошла ошибка при удалении volumes

### ⚡ БЫСТРОЕ РЕШЕНИЕ

#### Вариант 1: Автоматический скрипт (Рекомендуется)

```bash
# Запустите скрипт очистки
sudo ./scripts/cleanup-storage-pool.sh

# После успешной очистки:
cd examples/local
terraform state rm module.dns_server.libvirt_pool.vm_pool
terraform destroy
```

Скрипт автоматически:
- Остановит и удалит VM
- Удалит все volumes из pool
- Очистит директорию
- Удалит pool из libvirt

#### Вариант 2: Ручная очистка

```bash
# 1. Проверьте содержимое директории
sudo ls -lah /var/lib/libvirt/pools/dns-server/

# 2. Остановите VM (если запущена)
virsh destroy dns-server 2>/dev/null || true
virsh undefine dns-server 2>/dev/null || true

# 3. Удалите volumes из pool
virsh vol-list dns-server-pool 2>/dev/null | tail -n +3 | awk '{print $1}' | while read vol; do
  [ -n "$vol" ] && virsh vol-delete "$vol" --pool dns-server-pool
done

# 4. Удалите файлы вручную
sudo rm -rf /var/lib/libvirt/pools/dns-server/*

# 5. Удалите директорию
sudo rmdir /var/lib/libvirt/pools/dns-server

# 6. Удалите pool из libvirt
virsh pool-destroy dns-server-pool 2>/dev/null || true
virsh pool-undefine dns-server-pool 2>/dev/null || true

# 7. Удалите pool из Terraform state
cd examples/local
terraform state rm module.dns_server.libvirt_pool.vm_pool

# 8. Завершите destroy
terraform destroy
```

### Проверка после очистки

```bash
# Проверьте, что директория удалена
ls /var/lib/libvirt/pools/dns-server
# Должно быть: No such file or directory

# Проверьте, что pool удален из libvirt
virsh pool-list --all | grep dns-server
# Не должно быть результатов

# Проверьте Terraform state
cd examples/local
terraform state list | grep libvirt_pool
# Не должно быть результатов
```

### Предотвращение проблемы

Для корректного удаления всегда используйте:

```bash
# Полное удаление инфраструктуры
cd examples/local
terraform destroy

# Если возникают ошибки, удалите ресурсы по порядку:
terraform destroy -target=module.dns_server.libvirt_domain.dns_server
terraform destroy -target=module.dns_server.libvirt_volume.dns_server
terraform destroy -target=module.dns_server.libvirt_volume.base
terraform destroy -target=module.dns_server.libvirt_cloudinit_disk.cloudinit
terraform destroy -target=module.dns_server.libvirt_pool.vm_pool
terraform destroy
```

---

## Проблема: Permission denied при создании виртуальной машины

### Ошибка
```
Error: error creating libvirt domain: internal error: process exited while connecting to monitor:
qemu-system-x86_64: -blockdev {"driver":"file","filename":"/var/lib/libvirt/pools/dns-server/dns-server-base.qcow2",...}:
Could not open '/var/lib/libvirt/pools/dns-server/dns-server-base.qcow2': Permission denied
```

### Причина
QEMU/KVM работает от пользователя `libvirt-qemu` или `qemu`, но не может прочитать файлы образов дисков из-за блокировки со стороны AppArmor/SELinux security labels.

Даже если в коде Terraform присутствует XSLT трансформация для отключения security labels, она может не применяться корректно из-за:
- Конфигурации libvirt, которая принудительно использует security driver
- Terraform provider libvirt, который может добавлять security labels поверх XSLT трансформации
- Неправильной конфигурации qemu.conf

### ⚠️ ВАЖНО: Проверьте наличие xsltproc

**Самая распространенная причина этой ошибки** - отсутствие пакета `xsltproc`.

Модуль Terraform использует XSLT трансформации для отключения security labels в libvirt. Если `xsltproc` не установлен, трансформация не применяется, и QEMU получает ошибку Permission denied.

#### Проверка и установка xsltproc

```bash
# Проверить наличие xsltproc
which xsltproc

# Если не установлен, установите
apt-get install -y xsltproc

# Проверьте версию
xsltproc --version
```

После установки xsltproc повторите `terraform apply` - проблема должна исчезнуть.

### Автоматическая проверка всех зависимостей

Используйте скрипт для проверки всех предварительных требований:

```bash
./scripts/check-prerequisites.sh
```

Этот скрипт проверит наличие всех необходимых инструментов, включая `xsltproc`.

### ⚡ БЫСТРОЕ РЕШЕНИЕ

#### Вариант 1: Безопасный (Рекомендуется для production)

```bash
sudo ./scripts/fix-libvirt-permissions-safe.sh
# Выберите опцию 1 (БЕЗОПАСНЫЙ режим)
```

**Этот скрипт настроит:**
- QEMU работает от `libvirt-qemu` (не root) ✅
- AppArmor остается активным ✅
- Автоматическая настройка прав на директории ✅
- Максимальная безопасность ✅

#### Вариант 2: Быстрое решение (Только для разработки!)

```bash
sudo ./scripts/fix-libvirt-permissions.sh
```

⚠️ **ВНИМАНИЕ:** Этот скрипт запускает QEMU от root и отключает AppArmor.
**НЕ используйте на production серверах!**

Подробнее о рисках безопасности см. [SECURITY.md](SECURITY.md).

После выполнения скрипта запустите:
```bash
cd examples/local
terraform apply
```

### Решения

#### 1. Отключить security labels в конфигурации домена (Автоматически применено)

В модуле Terraform уже добавлена настройка, которая отключает SELinux/AppArmor security labels для домена:

```hcl
resource "libvirt_domain" "dns_server" {
  # ... другие настройки ...

  xml {
    xslt = <<EOF
<?xml version="1.0" ?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output omit-xml-declaration="yes" indent="yes"/>
  <xsl:template match="node()|@*">
     <xsl:copy>
       <xsl:apply-templates select="node()|@*"/>
     </xsl:copy>
  </xsl:template>

  <xsl:template match="/domain/seclabel">
    <seclabel type='none' model='none'/>
  </xsl:template>

  <xsl:template match="/domain[count(seclabel)=0]">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <seclabel type='none' model='none'/>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
EOF
  }
}
```

Это решение:
- Не требует изменения системных файлов
- Работает автоматически при `terraform apply`
- Отключает security labels для данного домена
- Позволяет QEMU получить доступ к файлам образов

**Просто выполните `terraform apply` - настройка уже применена в модуле.**

#### 2. Включить dynamic_ownership в libvirt (Альтернатива)

Проверьте конфигурацию libvirt:

```bash
# Откройте конфигурационный файл
sudo nano /etc/libvirt/qemu.conf

# Найдите и раскомментируйте/установите следующие параметры:
user = "root"
group = "root"
dynamic_ownership = 1

# Перезапустите libvirt
sudo systemctl restart libvirtd
```

Параметр `dynamic_ownership = 1` позволяет libvirt автоматически изменять владельца файлов образов при запуске ВМ на пользователя QEMU, а при остановке - обратно на root.

#### 3. Пересоздать storage pool (если нужно)

После изменения конфигурации, пересоздайте pool:

```bash
cd examples/local

# Удалить старый pool из состояния
terraform destroy -target=module.dns_server.libvirt_pool.vm_pool

# Пересоздать все ресурсы
terraform apply
```

#### 4. Исправить права вручную (Временное решение)

Если нужно быстро запустить ВМ:

```bash
# Измените владельца файлов на libvirt-qemu
sudo chown -R libvirt-qemu:libvirt-qemu /var/lib/libvirt/pools/dns-server/

# Или на qemu (зависит от дистрибутива)
sudo chown -R qemu:qemu /var/lib/libvirt/pools/dns-server/

# Установите правильные права
sudo chmod -R 755 /var/lib/libvirt/pools/dns-server/
sudo chmod 644 /var/lib/libvirt/pools/dns-server/*.qcow2
```

#### 5. Проверить AppArmor/SELinux (если предыдущие решения не помогли)

На Ubuntu проверьте AppArmor:

```bash
# Проверить статус
sudo aa-status | grep libvirt

# Если AppArmor блокирует, временно отключите профиль
sudo aa-complain /etc/apparmor.d/usr.sbin.libvirtd
sudo systemctl restart libvirtd
```

На RHEL/CentOS проверьте SELinux:

```bash
# Проверить статус
getenforce

# Посмотреть denied записи
sudo ausearch -m avc -ts recent | grep qemu

# Временно перевести в permissive mode
sudo setenforce 0
```

### Проверка после исправления

```bash
# Проверьте права на файлы
ls -la /var/lib/libvirt/pools/dns-server/

# Попробуйте создать ВМ снова
cd examples/local
terraform apply
```

## Дополнительные настройки

### Добавление пользователя в группу libvirt

```bash
# Добавить текущего пользователя в группу libvirt
sudo usermod -a -G libvirt $(whoami)
sudo usermod -a -G kvm $(whoami)

# Перелогиниться для применения изменений
su - $(whoami)
```

### Проверка конфигурации pool

```bash
# Список pools
virsh pool-list --all

# Информация о pool
virsh pool-info dns-server-pool

# XML конфигурация pool
virsh pool-dumpxml dns-server-pool
```

## Техническое объяснение проблемы

### Как работает security в libvirt

1. **AppArmor/SELinux** - системы обязательного контроля доступа (MAC)
   - Ограничивают доступ процессов к файлам, даже если пользователь имеет права
   - libvirt по умолчанию использует AppArmor профили для QEMU

2. **Security Labels** в libvirt
   - libvirt автоматически применяет security labels к доменам
   - Типы: `dynamic` (AppArmor), `static`, `none`
   - При `type='dynamic'` AppArmor блокирует доступ QEMU к файлам вне разрешенных директорий

3. **Почему возникает Permission denied**
   - QEMU процесс запускается с ограничениями AppArmor
   - AppArmor профиль блокирует чтение файлов из `/var/lib/libvirt/pools/dns-server/`
   - Даже если файл имеет права 644 и принадлежит правильному пользователю

### Решения в коде

Модуль использует **комбинированный подход**:

1. **XSLT трансформация** (main.tf:112-139)
   - Удаляет все существующие `seclabel` элементы из XML домена
   - Добавляет единственный `<seclabel type='none' model='none'/>`
   - Это отключает security driver для конкретного домена

2. **Конфигурация qemu.conf**
   - `security_driver = "none"` - глобально отключает security driver
   - `user = "root"` - запускает QEMU от root (полный доступ)
   - `dynamic_ownership = 1` - автоматически изменяет владельца файлов при запуске VM

3. **type = "qemu"** (main.tf:76)
   - Использует QEMU эмуляцию вместо KVM
   - Необходимо для систем без аппаратной виртуализации (WSL2, вложенные VM)
   - Не влияет на security labels

### Почему недостаточно только XSLT

Terraform provider libvirt может:
- Игнорировать XSLT трансформацию, если она конфликтует с настройками провайдера
- Применять свои security labels после XSLT
- Использовать глобальные настройки из qemu.conf, которые переопределяют XSLT

Поэтому **рекомендуется** использовать оба подхода:
- XSLT в коде Terraform (уже есть)
- Настройка qemu.conf (выполняется скриптом)

### Альтернативы (не рекомендуется)

1. **Изменение AppArmor профиля**
   ```bash
   sudo aa-complain /usr/sbin/libvirtd
   ```
   Минус: снижает общую безопасность системы

2. **Полное отключение AppArmor**
   ```bash
   sudo systemctl stop apparmor
   sudo systemctl disable apparmor
   ```
   Минус: критическая уязвимость безопасности

3. **Изменение владельца файлов вручную**
   ```bash
   sudo chown -R libvirt-qemu:libvirt-qemu /var/lib/libvirt/pools/
   ```
   Минус: временное решение, сбросится при пересоздании pool

## Проверка после исправления

```bash
# 1. Проверьте конфигурацию qemu.conf
grep -E "^(user|group|dynamic_ownership|security_driver)" /etc/libvirt/qemu.conf

# 2. Проверьте, что libvirtd перезапущен
sudo systemctl status libvirtd

# 3. Попробуйте создать VM
cd examples/local
terraform apply

# 4. Проверьте security model домена после создания
virsh dominfo dns-server | grep -i security
# Должно быть: Security model: none

# 5. Проверьте XML домена
virsh dumpxml dns-server | grep seclabel
# Должно быть: <seclabel type='none' model='none'/>
```
