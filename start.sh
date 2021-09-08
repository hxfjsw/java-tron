#!/bin/bash
# build FullNode config
FULL_NODE_DIR="FullNode"
FULL_NODE_CONFIG="main_net_config.conf"
DEFAULT_FULL_NODE_CONFIG='config.conf'
FULL_NODE_SHELL="start.sh"
JAR_NAME="FullNode.jar"
FULL_START_OPT=''
GITHUB_BRANCH='master'

# start service option
MAX_STOP_TIME=60
# modify this option to allow the minimum memory to be started, unit MB
ALLOW_MIN_MEMORY=8192
# JVM option
MAX_DIRECT_MEMORY=1g
JVM_MS=4g
JVM_MX=4g

SPECIFY_MEMORY=0
RUN=false
UPGRADE=false

# rebuild manifest
REBUILD_MANIFEST=true
REBUILD_DIR="$PWD/output-directory/database"
REBUILD_MANIFEST_SIZE=0
REBUILD_BATCH_SIZE=80000

# download and upgrade
DOWNLOAD=false
RELEASE_URL='https://github.com/tronprotocol/java-tron/releases'
QUICK_START=false

getLatestReleaseVersion() {
  default_version='GreatVoyage-v4.3.0'
  full_node_version=`git ls-remote --tags git@github.com:tronprotocol/java-tron.git |grep GreatVoyage- | awk -F '/' 'END{print $3}'`
  if [[ -n $full_node_version ]]; then
   echo $full_node_version
  else
   echo $default_version
  fi
}

checkVersion() {
 github_release_version=$(`echo getLatestReleaseVersion`)
 if [[ -n $github_release_version ]]; then
  echo "info: github latest version: $github_release_version"
  echo $github_release_version
 else
   echo ''
 fi
}

upgrade() {
  latest_version=$(`echo getLatestReleaseVersion`)
  echo "info: latest version: $latest_version"
  if [[ -n $latest_version ]]; then
    old_jar="$PWD/$JAR_NAME"
    if [[ -f $old_jar ]]; then
      echo "info: backup $old_jar"
      mv $PWD/$JAR_NAME $PWD/$JAR_NAME'_bak'
    fi
    download $RELEASE_URL/download/$latest_version/$JAR_NAME $JAR_NAME
    if [[ $? == 0 ]]; then
      echo "info: download version $latest_version success"
    fi
  else
    echo 'info: nothing to upgrade'
  fi
}

download() {
  local url=$1
  local file_name=$2
  if type wget >/dev/null 2>&1; then
    wget --no-check-certificate -q $url
  elif type curl >/dev/null 2>&1; then
    echo "curl -OLJ $url"
    curl -OLJ $url
  else
    echo 'info: no exists wget or curl, make sure the system can use the "wget" or "curl" command'
  fi
}

mkdirFullNode() {
  if [ ! -d $FULL_NODE_DIR ]; then
    echo "info: mkdir $FULL_NODE_DIR"
    mkdir $FULL_NODE_DIR
    $(cp $0 $FULL_NODE_DIR)
    cd $FULL_NODE_DIR
  elif [ -d $FULL_NODE_DIR ]; then
    cd $FULL_NODE_DIR
  fi

}

quickStart() {
  mkdirFullNode
  full_node_version=$(`echo getLatestReleaseVersion`)
  echo "info: check latest version: $full_node_version"
  echo 'info: download config'
  download https://raw.githubusercontent.com/tronprotocol/tron-deployment/$GITHUB_BRANCH/$FULL_NODE_CONFIG $FULL_NODE_CONFIG
  mv $FULL_NODE_CONFIG 'config.conf'

  echo "info: download $full_node_version"
  download $RELEASE_URL/download/$full_node_version/$JAR_NAME $JAR_NAME
}

cloneCode() {
  if type git >/dev/null 2>&1; then
    git_clone=$(git clone -b $GITHUB_BRANCH git@github.com:tronprotocol/java-tron.git)
    if [[ git_clone == 0 ]]; then
      echo 'info: git clone java-tron success'
    fi
  else
    echo 'info: no exists git, make sure the system can use the "git" command'
  fi
}

cloneBuild() {
  cloneCode
  echo "info: build java-tron"
  sh 'java-tron/'gradlew clean build -x test
  mkdirFullNode
  if [[ $? == 0 ]];then
    cp 'java-tron/build/libs/FullNode.jar' 'FullNode/'
  fi
}

checkPid() {
  if [[ $JAR_NAME =~ '/' ]]; then
    JAR_NAME=$(echo $JAR_NAME |awk -F '/' '{print $NF}')
  fi
  pid=$(ps -ef | grep -v start | grep $JAR_NAME | grep -v grep | awk '{print $2}')
  return $pid
}

stopService() {
  count=1
  while [ $count -le $MAX_STOP_TIME ]; do
    checkPid
    if [ $pid ]; then
      kill -15 $pid
      sleep 1
    else
      echo "info: java-tron stop"
      return
    fi
    count=$(($count + 1))
    if [ $count -eq $MAX_STOP_TIME ]; then
      kill -9 $pid
      sleep 1
    fi
  done
  sleep 5
}

checkAllowMemory() {
  os=`uname`
#  totalMemory=`getTotalMemory`
  totalMemory=$(`echo getTotalMemory`)
  total=`expr $totalMemory / 1024`
  if [[ $os == 'Darwin' ]]; then
    return
  fi

  if [[ $total -lt $ALLOW_MIN_MEMORY ]]; then
    echo "warn: the memory $total MB cannot be smaller than the minimum memory $ALLOW_MIN_MEMORY MB"
    exit
  elif [[ $SPECIFY_MEMORY -gt 0 ]] &&
   [[ $SPECIFY_MEMORY -lt $ALLOW_MIN_MEMORY ]]; then
    echo "warn: the specified memory $SPECIFY_MEMORY MB cannot be smaller than the minimum memory $ALLOW_MIN_MEMORY MB"
    echo 'warn: start abort'
    exit
  fi
}

setTCMalloc() {
  os=`uname`
  if [[ $os == 'Linux' ]] || [[ $os == 'linux' ]] ; then
    lib_tc_malloc="/usr/lib64/libtcmalloc.so"
    if [[ -f $lib_tc_malloc ]]; then
      export LD_PRELOAD="$lib_tc_malloc"
      export TCMALLOC_RELEASE_RATE=10
    else
      echo 'info: recommended for linux systems using tcmalloc as the default memory management tool'
    fi
  fi
}

getTotalMemory() {
  os=`uname`
  if [[ $os == 'Linux' ]] || [[ $os == 'linux' ]] ; then
    total=$(cat /proc/meminfo | grep MemTotal | awk -F ' ' '{print $2}')
    echo $total
    return
  elif [[  $os == 'Darwin' ]]; then
    total=$(sysctl -a | grep mem |grep hw.memsize |awk -F ' ' '{print $2}')
    echo `expr $total / 1024`
  fi
}

setJVMMemory() {
  os=`uname`
  if [[ $os == 'Linux' ]] || [[ $os == 'linux' ]] ; then
    if [[ $SPECIFY_MEMORY >0 ]]; then
      max_direct=$(echo "$SPECIFY_MEMORY/1024*0.1" | bc | awk -F. '{print $1"g"}')
      if [[ "$max_direct" != "g" ]]; then
        MAX_DIRECT_MEMORY=$max_direct
      fi
      JVM_MX=$(echo "$SPECIFY_MEMORY/1024*0.6" | bc | awk -F. '{print $1"g"}')
      JVM_MS=$JVM_MX
    else
      total=$(`echo getTotalMemory`)
      MAX_DIRECT_MEMORY=$(echo "$total/1024/1024*0.1" | bc | awk -F. '{print $1"g"}')
      JVM_MX=$(echo "$total/1024/1024*0.6" | bc | awk -F. '{print $1"g"}')
      JVM_MS=$JVM_MX
    fi

  elif [[ $os == 'Darwin' ]]; then
    MAX_DIRECT_MEMORY='1g'
  fi
}

startService() {
  echo $(date) >>start.log
  logtime=$(date +%Y-%m-%d_%H-%M-%S)

  if [[ ! $JAR_NAME =~ '-c' ]]; then
     FULL_START_OPT="$FULL_START_OPT -c $DEFAULT_FULL_NODE_CONFIG"
  fi

  nohup java -Xms$JVM_MS -Xmx$JVM_MX -XX:+UseConcMarkSweepGC -XX:+PrintGCDetails -Xloggc:./gc.log \
    -XX:+PrintGCDateStamps -XX:+CMSParallelRemarkEnabled -XX:ReservedCodeCacheSize=256m -XX:+UseCodeCacheFlushing \
    -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m \
    -XX:MaxDirectMemorySize=$MAX_DIRECT_MEMORY -XX:+HeapDumpOnOutOfMemoryError \
    -XX:NewRatio=2 -jar \
    $JAR_NAME $FULL_START_OPT >>start.log 2>&1 &
  checkPid
  echo "info: start java-tron with pid $pid on $HOSTNAME"
  echo "info: stop service execution: sh start.sh --stop"
}

rebuildManifest() {
  if [[ $REBUILD_MANIFEST = false ]]; then
    echo 'info: disable rebuild manifest!'
    return
  fi

  if [[ ! -d $REBUILD_DIR ]]; then
    echo "info: database not exists, skip rebuild manifest"
    return
  fi

  ARCHIVE_JAR='ArchiveManifest.jar'
  if [[ -f $ARCHIVE_JAR ]]; then
    echo 'info: execute rebuild manifest.'
    java -jar $ARCHIVE_JAR -d $REBUILD_DIR -m $REBUILD_MANIFEST_SIZE -b $REBUILD_BATCH_SIZE
  else
    echo 'info: download the rebuild manifest plugin from the github'
    download $RELEASE_URL/download/GreatVoyage-v4.3.0/$ARCHIVE_JAR $ARCHIVE_JAR
    if [[ $download == 0 ]]; then
      echo 'info: download success, rebuild manifest'
      java -jar $ARCHIVE_JAR $REBUILD_DIR -m $REBUILD_MANIFEST_SIZE -b $REBUILD_BATCH_SIZE
    fi
  fi
  if [[ $? == 0 ]]; then
    echo 'info: rebuild manifest success'
  else
    echo 'info: rebuild manifest fail, log in logs/archive.log'
  fi
}

restart() {
  stopService
  checkAllowMemory
  rebuildManifest
  setTCMalloc
  setJVMMemory
  startService
}

//加校验

//3个例子
1.本地起
2.拉代码
3.拉release
  加验验
while [ -n "$1" ]; do
  case "$1" in
  -c)
    DEFAULT_FULL_NODE_CONFIG=$2
    FULL_START_OPT="$FULL_START_OPT $1 $2"
    shift 2
    ;;
  -d)
    REBUILD_DIR=$2/database
    FULL_START_OPT="$FULL_START_OPT $1 $2"
    shift 2
    ;;
  -j)
    JAR_NAME=$2
    shift 2
    ;;
  -m)
    REBUILD_MANIFEST_SIZE=$2
    shift 2
    ;;
  -n)
    JAR_NAME=$2
    shift 2
    ;;
  -b)
    REBUILD_BATCH_SIZE=$2
    shift 2
    ;;
  -cb)
    cloneBuild
    shift 1
    ;;
  --download)
    DOWNLOAD=true
    shift 1
    ;;
  --deploy)
    QUICK_START=true
    shift 1
    ;;
  --release)
    QUICK_START=true
    shift 1
    ;;
  --clone)
    cloneCode
    exit
    ;;
  -mem)
    SPECIFY_MEMORY=$2
    shift 2
    ;;
  --disable-rewrite-manifes)
    REBUILD_MANIFEST=false
    shift 1
    ;;
  -dr)
    REBUILD_MANIFEST=false
    shift 1
    ;;
  --upgrade)
    UPGRADE=true
    shift 1
    ;;
  --run)
    RUN=true
    shift 1
    ;;
  --stop)
    stopService
    exit
    ;;
  *)
    echo "warn: option $1 does not exist"
    exit
    ;;
  esac
done

if [[ $QUICK_START == true ]]; then
  quickStart
  if [[ $? == 0 ]] ; then
    if [[ $RUN == true ]]; then
      cd $FULL_NODE_DIR
      FULL_START_OPT=''
      restart
    fi
  fi
  exit
fi

if [[ $UPGRADE == true ]]; then
  upgrade
  exit
fi

if [[ $RUN == true ]]; then
  restart
  exit
fi

if [[ $DOWNLOAD == true ]]; then
  latest=$(`echo getLatestReleaseVersion`)
  download $RELEASE_URL/download/$latest/$JAR_NAME $latest
  exit
fi

restart