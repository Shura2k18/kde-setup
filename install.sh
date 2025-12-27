#!/bin/bash

set -e

echo "=== Post-Install Setup ==="

if [[ $EUID -eq 0 ]]; then
  echo "Бовдур, не запускай від root!!!"
  exit 1
fi

ask() {
  local prompt="$1"
  local default="${2:-y}"
  read -rp "$prompt [y/N]: " ans
  ans=${ans:-$default}
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# Вибір системи
echo "Оберіть тип системи:"
echo "  1) Arch / Manjaro / EndeavourOS"
echo "  2) Debian / Ubuntu / Linux Mint"
read -rp "Ваш вибір (1/2): " SYS_CHOICE

if [[ "$SYS_CHOICE" == "1" ]]; then
  SYS_TYPE="arch"
elif [[ "$SYS_CHOICE" == "2" ]]; then
  SYS_TYPE="debian"
else
  echo "Невірний вибір, вихід."
  exit 1
fi

###############################################################################
# 1. Встановлення пакетів (з pkglist.txt)
###############################################################################
if ask "Встановити базові пакети з pkglist?"; then
  echo "🔍 Шукаю файли pkglist*.txt ..."

  shopt -s nullglob
  pkglists=( pkglist*.txt )
  shopt -u nullglob

  if (( ${#pkglists[@]} == 0 )); then
    echo "⚠ Файлів pkglist*.txt не знайдено. Пропускаю встановлення пакетів."

  elif (( ${#pkglists[@]} == 1 )); then
    pkglist="${pkglists[0]}"
    echo "✔ Знайдено один файл: $pkglist"

    if [[ "$SYS_TYPE" == "arch" ]]; then
      sudo pacman -Syu
      sudo pacman -S --needed - < "$pkglist"
    else
      sudo apt update
      xargs -a "$pkglist" sudo apt install -y
    fi

  else
    echo "🔎 Знайдено декілька pkglist файлів:"
    select pkglist in "${pkglists[@]}"; do
      if [[ -n "$pkglist" ]]; then
        echo "✔ Обрано: $pkglist"

        if [[ "$SYS_TYPE" == "arch" ]]; then
          sudo pacman -S --needed - < "$pkglist"
        else
          sudo apt update
          xargs -a "$pkglist" sudo apt install -y
        fi
        break
      else
        echo "❌ Невірний вибір, спробуй ще раз."
      fi
    done

    if ask "Встановити yay?"; then
      git clone https://aur.archlinux.org/yay.git
      cd yay
      makepkg -si
      cd ..
      rm -rf yay
    else
      echo "Пропущено встановлення yay"
    fi
  fi
else
  echo "Пропущено встановлення пакетів."
fi

###############################################################################
# 2. Встановлення та налаштування konsave + відновлення KDE-конфігу
###############################################################################
if ask "Встановити konsave та відновити KDE конфіг?"; then
  if [[ "$SYS_TYPE" == "arch" ]]; then
    sudo pacman -S --needed python python-pip python-pipx
  else
    sudo apt update
    sudo apt install -y python3 python3-pip pipx
  fi
  pipx ensurepath

  pipx install konsave
  pipx inject konsave setuptools

  echo "Restoring KDE configuration..."
  shopt -s nullglob
  knsv_files=( *.knsv )
  shopt -u nullglob

  if (( ${#knsv_files[@]} == 0 )); then
    echo "⚠ Файлів *.knsv не знайдено. Пропускаю відновлення KDE-конфігу."
  elif (( ${#knsv_files[@]} == 1 )); then
    knsv="${knsv_files[0]}"
    profile_name="${knsv%.knsv}"

    echo "✔ Знайдено один файл: $knsv"
    ~/.local/bin/konsave -i "$knsv"
    ~/.local/bin/konsave -a "$profile_name"
  else
    echo "🔎 Знайдено декілька *.knsv файлів:"
    select knsv in "${knsv_files[@]}"; do
      if [[ -n "$knsv" ]]; then
        profile_name="${knsv%.knsv}"
        ~/.local/bin/konsave -i "$knsv"
        ~/.local/bin/konsave -a "$profile_name"
        break
      else
        echo "❌ Невірний вибір, спробуй ще раз."
      fi
    done
  fi
else
  echo "Пропущено konsave/KDE конфіг."
fi

###############################################################################
# 3. Увімкнення NumLock у SDDM
###############################################################################
if ask "Увімкнути NumLock у SDDM автоматично?"; then
  sudo mkdir -p /etc/sddm.conf.d
  echo -e "[General]\nNumlock=on" | sudo tee /etc/sddm.conf.d/numlock.conf >/dev/null
  if ask "Перезапустити SDDM зараз (може завершити поточну сесію)?"; then
    sudo systemctl restart sddm
  else
    echo "Перезапуск SDDM пропущено. Застосуй зміни пізніше: sudo systemctl restart sddm"
  fi
else
  echo "Пропущено налаштування NumLock."
fi

###############################################################################
# 4. Встановлення Zsh, Oh My Zsh, Powerlevel10k, плагінів (ОСТАННІЙ КРОК)
###############################################################################
if ask "Встановити Zsh, Oh My Zsh, Powerlevel10k і плагіни (останній крок)?"; then
  echo "=== Встановлення Zsh та оточення ==="

  # 4.1 Встановити zsh + залежності
  if [[ "$SYS_TYPE" == "arch" ]]; then
    sudo pacman -S --needed zsh git curl
  else
    sudo apt update
    sudo apt install -y zsh git curl
  fi

  # 4.2 Зробити zsh shell'ом за замовчуванням
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo
    echo "⚠ Зараз Oh My Zsh спитає, чи зробити zsh оболонкою за замовчуванням."
    echo "⚠ Відповідай Y — це те, що ти хочеш."
    echo

    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  # 4.3 Тема Powerlevel10k
  if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      "$ZSH_CUSTOM/themes/powerlevel10k"
  fi

  # 4.4 Плагіни
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  fi

  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  fi

  if [ ! -d "$ZSH_CUSTOM/plugins/you-should-use" ]; then
    git clone https://github.com/MichaelAquilina/zsh-you-should-use.git \
      "$ZSH_CUSTOM/plugins/you-should-use"
  fi

  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-bat" ]; then
    git clone https://github.com/fdellwing/zsh-bat.git \
      "$ZSH_CUSTOM/plugins/zsh-bat"
  fi

  # 4.5 Оновити ~/.zshrc
  ZSHRC="$HOME/.zshrc"

  if [ ! -f "$ZSHRC" ] && [ -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" ]; then
    cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$ZSHRC"
  fi

  if grep -q '^ZSH_THEME=' "$ZSHRC"; then
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >>"$ZSHRC"
  fi

  if grep -q '^plugins=' "$ZSHRC"; then
    sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting you-should-use zsh-bat)/' "$ZSHRC"
  else
    echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting you-should-use zsh-bat)' >>"$ZSHRC"
  fi

  echo
  echo "Zsh/Oh My Zsh/Powerlevel10k/плагіни встановлено."
  echo "Перезапусти термінал або виконай: source ~/.zshrc"
  echo "Щоб налаштувати Powerlevel10k, запусти: p10k configure"
else
  echo "Пропущено встановлення Zsh та плагінів."
fi

###############################################################################
# 5. Встановлення tlp + tlp-rdw для ноутбуків
###############################################################################
if ask "Чи хочеш встановити tlp + tlp-rdw для ноутбуків? (для економії зарядки)"; then
  if [[ "$SYS_TYPE" == "arch" ]]; then
    sudo pacman -S --needed tlp tlp-rdw
  else
    sudo apt update
    sudo apt install -y tlp tlp-rdw
  fi
  sudo systemctl disable --now power-profiles-daemon.service
  sudo systemctl mask power-profiles-daemon.service
  sudo systemctl enable --now tlp.service
else
  echo "Пропущено налаштування встановлення tlp."
fi

echo
echo "Вітаннячка, ти таки все встановив)))"
echo "Перезапусти пристрій, щоб налаштування застосувалися."
