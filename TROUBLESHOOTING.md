# Решение проблем с правами доступа к образам дисков

## Проблема: Permission denied при создании виртуальной машины

### Ошибка
```
Could not open '/var/lib/libvirt/pools/dns-server/dns-server-base.qcow2': Permission denied
```

### Причина
QEMU/KVM работает от пользователя `libvirt-qemu` или `qemu`, но не может прочитать файлы образов дисков из-за неправильных прав доступа.

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
