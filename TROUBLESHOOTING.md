# Решение проблем с правами доступа к образам дисков

## Проблема: Permission denied при создании виртуальной машины

### Ошибка
```
Could not open '/var/lib/libvirt/pools/dns-server/dns-server-base.qcow2': Permission denied
```

### Причина
QEMU/KVM работает от пользователя `libvirt-qemu` или `qemu`, но не может прочитать файлы образов дисков из-за неправильных прав доступа.

### Решения

#### 1. Включить dynamic_ownership в libvirt (Рекомендуется)

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

#### 2. Пересоздать storage pool

После изменения конфигурации, пересоздайте pool:

```bash
cd examples/local

# Удалить старый pool из состояния
terraform destroy -target=module.dns_server.libvirt_pool.vm_pool

# Пересоздать все ресурсы
terraform apply
```

#### 3. Исправить права вручную (Временное решение)

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

#### 4. Проверить AppArmor/SELinux

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
