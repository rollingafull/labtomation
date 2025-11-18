# Actualizar Playbooks en VM Labtomation Existente

Este documento explica cómo actualizar los playbooks en una VM de Labtomation que ya está ejecutándose.

## 📋 Tabla de Contenidos

- [Cuándo Actualizar](#cuándo-actualizar)
- [Método 1: Script Automático](#método-1-script-automático-recomendado)
- [Método 2: Manual con rsync](#método-2-manual-con-rsync)
- [Método 3: Recrear VM](#método-3-recrear-vm-desde-cero)
- [Verificación](#verificación)

---

## 🔄 Cuándo Actualizar

Necesitas actualizar los playbooks cuando:
- ✅ Se han corregido errores en los playbooks del repositorio
- ✅ Se han agregado nuevas funcionalidades
- ✅ Se han actualizado roles o tareas
- ✅ El playbook en la VM muestra errores que ya fueron corregidos

**Señales de que necesitas actualizar:**
- Los errores que ves no coinciden con el código en el repo
- Cambios recientes en el repo no se reflejan al ejecutar playbooks
- El error menciona código/sintaxis que ya fue corregido

---

## 🚀 Método 1: Script Automático (Recomendado)

### Paso 1: Obtener la IP de la VM

```bash
# Desde el host Proxmox, lista las VMs
qm list

# Obtén la IP de la VM labtomation
qm guest cmd <VMID> network-get-interfaces
```

### Paso 2: Ejecutar el Script de Actualización

```bash
# Desde el host Proxmox
cd /path/to/labtomation/setup

# Ejecutar con la IP de tu VM
./update_vm_playbooks.sh 192.168.X.X

# O especificar una clave SSH diferente
./update_vm_playbooks.sh 192.168.X.X /path/to/ssh_key
```

### Paso 3: Verificar

```bash
# Conéctate a la VM
ssh -i ~/.ssh/lab_id_ed25519 labtomation@192.168.X.X

# Verifica que los archivos están actualizados
cd /opt/labtomation/playbooks
ls -la requirements.yml
cat roles/proxmox_bootstrap/tasks/create_api_token.yml | grep "Extract token"
```

### Paso 4: Ejecutar Bootstrap

```bash
# Desde dentro de la VM
cd /opt/labtomation/playbooks
ansible-playbook bootstrap_proxmox_cluster.yml
```

---

## 🔧 Método 2: Manual con rsync

Si prefieres hacerlo manualmente:

### Desde el Host Proxmox

```bash
# 1. Navegar al directorio del repo
cd /path/to/labtomation/setup

# 2. Crear backup en la VM (opcional pero recomendado)
ssh -i ~/.ssh/lab_id_ed25519 labtomation@192.168.X.X \
  "sudo cp -r /opt/labtomation/playbooks /opt/labtomation/playbooks.backup"

# 3. Sincronizar playbooks actualizados
rsync -avz --delete \
  -e "ssh -i ~/.ssh/lab_id_ed25519" \
  ./playbooks/ \
  labtomation@192.168.X.X:/tmp/playbooks_update/

# 4. Mover a la ubicación final
ssh -i ~/.ssh/lab_id_ed25519 labtomation@192.168.X.X << 'EOF'
  sudo rm -rf /opt/labtomation/playbooks
  sudo mv /tmp/playbooks_update /opt/labtomation/playbooks
  sudo chown -R labtomation:labtomation /opt/labtomation/playbooks
  sudo chmod -R u+rwX,go+rX /opt/labtomation/playbooks
EOF
```

---

## 🔄 Método 3: Recrear VM desde Cero

Si hay muchos cambios o prefieres empezar limpio:

```bash
# Desde el host Proxmox
cd /path/to/labtomation/setup

# Recrear la VM con --force
./labtomation.sh --force

# Esto:
# 1. Destruye la VM existente
# 2. Crea una nueva VM
# 3. Copia todos los archivos actualizados
# 4. Ejecuta el setup completo
```

**⚠️ Advertencia**: Esto eliminará:
- Toda la configuración de Vault
- Tokens y secretos guardados
- Configuración personalizada

---

## ✅ Verificación

### Verificar que los Archivos Están Actualizados

```bash
# Conéctate a la VM
ssh -i ~/.ssh/lab_id_ed25519 labtomation@<VM_IP>

# Verifica archivos clave
cd /opt/labtomation/playbooks

# 1. Verificar requirements.yml existe
ls -la requirements.yml

# 2. Verificar que create_api_token.yml tiene el nuevo regex
grep "Extract token secret" roles/proxmox_bootstrap/tasks/create_api_token.yml

# Debe mostrar:
# - name: Extract token secret from table output
#   ansible.builtin.set_fact:
#     api_token_full: "{{ token_output.stdout | regex_search(...) }}"

# 3. Verificar que create_api_role.yml NO tiene VM.Monitor
grep "role_privileges:" roles/proxmox_bootstrap/tasks/create_api_role.yml

# NO debe contener VM.Monitor
# Debe tener: VM.Console (nuevo)

# 4. Verificar bootstrap_proxmox_cluster.yml tiene pre-flight checks
head -80 bootstrap_proxmox_cluster.yml | grep "Pre-Flight Checks"
```

### Verificar Sintaxis

```bash
# Desde dentro de la VM
cd /opt/labtomation/playbooks
ansible-playbook bootstrap_proxmox_cluster.yml --syntax-check
```

Deberías ver:
```
playbook: bootstrap_proxmox_cluster.yml
[WARNING]: No inventory was parsed...
```

Sin errores de sintaxis.

---

## 🐛 Troubleshooting

### Error: "Permission denied"

```bash
# Verifica que la clave SSH tiene los permisos correctos
chmod 600 ~/.ssh/lab_id_ed25519
```

### Error: "Connection refused"

```bash
# Verifica que la VM está ejecutándose
qm status <VMID>

# Verifica la IP correcta
qm guest cmd <VMID> network-get-interfaces
```

### Los Cambios No Se Reflejan

```bash
# Verifica que estás editando los archivos correctos
# Los archivos fuente están en:
/path/to/labtomation/setup/playbooks/

# Los archivos en la VM están en:
/opt/labtomation/playbooks/

# Debes copiar desde el primero al segundo
```

### Backup de Emergencia

Si algo sale mal, puedes restaurar el backup:

```bash
ssh -i ~/.ssh/lab_id_ed25519 labtomation@<VM_IP>

# Listar backups
ls -la /opt/labtomation/playbooks.backup.*

# Restaurar un backup específico
sudo rm -rf /opt/labtomation/playbooks
sudo cp -r /opt/labtomation/playbooks.backup.YYYYMMDD_HHMMSS /opt/labtomation/playbooks
sudo chown -R labtomation:labtomation /opt/labtomation/playbooks
```

---

## 📚 Referencias

- [CHANGELOG.md](../../CHANGELOG.md) - Registro de cambios
- [PROXMOX_README.md](../playbooks/PROXMOX_README.md) - Documentación de Proxmox
- [README.md](../../README.md) - Documentación principal

---

**Última actualización**: 2025-10-30
