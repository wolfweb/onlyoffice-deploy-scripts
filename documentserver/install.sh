#!/bin/bash

#带颜色输出
color_text() {
  local color=$1
  shift
  echo -e "\033[${color}m$@\033[0m"
}

update_ds_port(){
  nginx_conf="/etc/onlyoffice/documentserver/nginx/ds.conf"
  new_port=$1
  if [ -f $nginx_conf ]; then
    if grep -Pq "listen [0-9]+(\.[0-9]+){3}:[0-9]+" "$nginx_conf"; then
        # 配置文件中包含带有IP的端口
        sed -E -i "s/(listen [0-9]+(\.[0-9]+){3}):[0-9]+/\1:$new_port/" "$nginx_conf"
    elif grep -q "listen [0-9]+" "$nginx_conf"; then
        # 配置文件中只包含端口
        sed -E -i "s/listen [0-9]+/listen $new_port/" "$nginx_conf"
    fi
    sudo nginx -s reload
  fi
}

#获取包管理器
get_package_manager(){
  if command -v apt &> /dev/null; then
    echo "apt"
  elif command -v dnf &> /dev/null; then
    echo "dnf"
  elif command -v yum &> /dev/null; then
    echo "yum"
  else
    echo "None"
  fi
}

#检测postgresql是否安装
check_postgresql() {
  if ! command -v psql >/dev/null 2>&1; then
      echo "PostgreSQL not found. Installing PostgreSQL..."
      sudo $PACKAGE_MANAGER install -y postgresql
      color_text 32 "Please config the postgresql for onlyoffice-documentserver......"
      sudo -u postgres psql
  else
      echo "PostgreSQL is already installed."
  fi
}

#检测包管理器是否安装
install_package_manager() {
  local package_manager=$1
  echo "Checking package Manager => $package_manager"
  if ! command -v $package_manager >/dev/null 2>&1; then
    echo "$package_manager command not found. Installing $package_manager..."
    if [ "$package_manager" = "dpkg" ]; then
        sudo $PACKAGE_MANAGER install -y dpkg
    elif [ "$package_manager" = "rpm" ]; then
        sudo $PACKAGE_MANAGER install -y rpm
    fi
  fi
}

#执行安装包
install_package() {
  local filename=$1

  check_postgresql

  ensure_dependency_packages

  echo "Executing install $filename"

  if [ -f "$filename" ]; then
     if [ "${filename##*.}" = "deb" ]; then
       install_package_manager "dpkg"
       sudo dpkg -i "$filename"
     elif [ "${filename##*.}" = "rpm" ]; then
       install_package_manager "rpm"
       sudo rpm -i "$filename"
     fi
  fi
}

#更具cpu架构以及包前缀生成包文件名
get_install_file() {
  package_base="$1"
  package_name="$2"
  architecture=$(uname -m)
  case "$architecture" in
    aarch64 | arm64)
      if [ "$package_base" = "RPM" ]; then
        echo "$package_name.aarch64.rpm"
      else
        echo "${package_name}_arm64.deb"
      fi
    ;;
    x86_64 | amd64)
      if [ "$package_base" = "RPM" ]; then
        echo "$package_name.x86_64.rpm"
      else
        echo "${package_name}_amd64.deb"
      fi
    ;;
  esac
}

#获取操作系统的包管理器
get_package_base() {
  if [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ] || [ -f /etc/SuSE-release ]; then
    echo "RPM"
  fi

  if [ -f /etc/debian_version ] || grep -qi 'ubuntu' /etc/os-release; then
    sudo dpkg --configure -a
    echo "DEB"
  fi
}

#依赖项安装
ensure_dependency_packages(){
  sudo $PACKAGE_MANAGER install -y libasound2
  sudo $PACKAGE_MANAGER install -y libcairo2
  sudo $PACKAGE_MANAGER install -y libgtk-3-0
  sudo $PACKAGE_MANAGER install -y libxss1
  sudo $PACKAGE_MANAGER install -y libxtst6
  sudo $PACKAGE_MANAGER install -y nginx-extras
  sudo $PACKAGE_MANAGER install -y postgresql-client
  sudo $PACKAGE_MANAGER install -y pwgen
  sudo $PACKAGE_MANAGER install -y ttf-mscorefonts-installer
  sudo $PACKAGE_MANAGER install -y xvfb
}

packname="onlyoffice-documentserver"
PACKAGE_MANAGER=$(get_package_manager)
if [ "$PACKAGE_MANAGER" = "None" ]; then
  echo "Not support operater system yet"
  exit 1
fi
echo "System update"
#sudo $PACKAGE_MANAGER update -y
#sudo $PACKAGE_MANAGER upgrade -y

package_base=$(get_package_base)
file=$(get_install_file "$package_base" "$packname")
echo "Get install package File => ${file}, execute installing..."
install_package $file

color_text 32 "Please enter the port number"
read parm
color_text 32 "Updating nginx listen port $parm"
update_ds_port $parm
