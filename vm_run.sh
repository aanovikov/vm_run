#!/bin/bash

# Проверяем, запущен ли скрипт с правами суперпользователя
if [ "$(id -u)" != "0" ]; then
    echo -e "\e[31mСкрипт должен быть запущен с правами root. Exit\e[0m"
    exit 1
fi

PROXYUSER_HOME="/home/proxyuser"
VM_REQUIRE=4  # Желаемое количество виртуальных машин

# Подсчет количества файлов VMX, соответствующих шаблону 'win*.vmx'
VM_COUNT=$(find "$PROXYUSER_HOME/vmware" -type f -name "win*.vmx" | wc -l)

# Проверка, достаточно ли виртуальных машин
if [ "$VM_COUNT" -lt "$VM_REQUIRE" ]; then
    echo -e "\e[31mДолжно быть $VM_REQUIRE виртуалки. Найдено только $VM_COUNT. Exit\e[0m"
    exit 1
fi

# после отработки 01_initial_script в папке ~/cfg_files запускаем команду:
echo -e "\e[90mФормирование списка адаптеров...\e[0m"
cat config.yaml | grep -E 'id[0-9]{1,3}:' | sed 's/:$//; s/^[ \t]*//; s/[ \t]*$//' > adapters
echo -e "\e[32mСписок адаптеров сформирован.\e[0m"

# Проверяем, существует ли файл adapters
if [ ! -f "adapters" ]; then
    echo -e "\e[31mФайл 'adapters' не найден. Exit\e[0m"
    exit 1
fi

# Проверяем, запущен ли процесс VMware, исключая vmware-tray
VMWARE_PID=$(pgrep -f "/usr/lib/vmware/bin/vmware$|/usr/lib/vmware/bin/vmware-vmx")
if [ -n "$VMWARE_PID" ]; then
    echo -e "\e[31mVMware запущен, его нужно выключить вручную. PID: $VMWARE_PID. Exit\e[0m"
    exit 1
else
    echo -e "\e[32mVMware не запущен.\e[0m"
fi

# Удаление из VM адаптеров ethernet кроме ethernet0
echo -e "\e[90mУдаление виртуальных сетей и адаптеров\e[0m"
sudo -u proxyuser sed -i '/ethernet0/!{/ethernet/d}' $PROXYUSER_HOME/vmware/winxp/winxp.vmx

# Удалить сети
sed -i '/id[0-9][0-9]*/d' /etc/vmware/networking

# Переменная для начального значения vnet_number для создания сетей
vnet_number=9

# Переменная для начального значения veth_number для создания адаптера
veth_number=0

# Чтение файла adapters и создание сети для каждого адаптера
while read -r adapter; do
  vnet_number=$((vnet_number + 1))  # Инкремент номера vnet
  veth_number=$((veth_number + 1))  # Инкремент номера veth

  echo -e "\e[90mДобавление маппинга для адаптера $adapter с vnet_number $vnet_number...\e[0m"
  sed -i "\$a\\add_bridge_mapping $adapter $vnet_number" /etc/vmware/networking

  echo -e "\e[90mДобавление сети в VM для адаптера $adapter...\e[0m"
  sudo -u proxyuser sed -i "\$a\\
ethernet$veth_number.connectionType = \"custom\"\\
ethernet$veth_number.addressType = \"generated\"\\
ethernet$veth_number.vnet = \"/dev/vmnet$vnet_number\"\\
ethernet$veth_number.present = \"TRUE\"" $PROXYUSER_HOME/vmware/winxp/winxp.vmx
done < adapters

# Перезапуск сети
echo -e "\e[90mПерезапуск сетевых сервисов...\e[0m"
vmware-networks --stop && vmware-networks --start
echo -e "\e[32mСетевые сервисы перезапущены.\e[0m"

echo -e "\e[90mПауза 5 секунд\e[0m"
sleep 5

# Запуск Windows
echo -e "\e[90mЗапуск Windows...\e[0m"
sudo -u proxyuser vmrun -T ws start $PROXYUSER_HOME/vmware/winxp/winxp.vmx nogui
echo -e "\e[32mWindows запущена.\e[0m"