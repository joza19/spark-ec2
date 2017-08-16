#!/bin/bash
# Creates an AMI for the Spark EC2 scripts starting with Ubuntu

set -e

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

apt-get install -y sudo 
sudo apt-get -y update
sudo apt-get -y upgrade 

# Dev tools
sudo apt-get install -y openjdk-8-jdk gcc build-essential ant git

# Perf tools
sudo apt-get install -y dstat iotop strace sysstat htop linux-tools-generic  #linux-tools-generic including perf

# Glibc debug 
# sudo debuginfo-install -q -y glibc (CentOS)
echo "deb http://ddebs.ubuntu.com $(lsb_release -cs) main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-updates main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-proposed main restricted universe multiverse" | \
sudo tee -a /etc/apt/sources.list.d/ddebs.list

sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 428D7C01 C8CAB6595FDFF622
sudo apt-get update
sudo apt-get install -y libc6-dbg libc6-dbgsym

# Kernel debug
# sudo debuginfo-install -q -y kernel
sudo apt-get install linux-image-$(uname -r)-dbgsym -y

# sudo yum --enablerepo='*-debug*' install -q -y java-1.8.0-openjdk-debuginfo.x86_64 (CentOS)
sudo apt-get install -y openjdk-8-dbg

# PySpark and MLlib deps
sudo apt-get install -y python-matplotlib python-tornado python-scipy # libgfortran already installed

# SparkR deps
sudo echo "deb http://cran.rstudio.com/bin/linux/ubuntu xenial/" | sudo tee -a /etc/apt/sources.list
gpg --keyserver keyserver.ubuntu.com --recv-key E084DAB9
gpg -a --export E084DAB9 | sudo apt-key add -
sudo apt-get update
sudo apt-get install r-base r-base-dev -y

# Other handy tools 
sudo apt-get install -y pssh

# Ganglia
# sudo yum install -y ganglia ganglia-web ganglia-gmond ganglia-gmetad (CentOS) , Ask you to restart Apache2 -> DEBIAN_FRONTEND=noninteractive
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ganglia-monitor rrdtool gmetad ganglia-webfrontend

# Root ssh config
sudo sed -i 's/PermitRootLogin.*/PermitRootLogin without-password/g' \
  /etc/ssh/sshd_config

sudo sed -i 's/disable_root.*/disable_root: 0/g' /etc/cloud/cloud.cfg

# Set up ephemeral mounts

sudo sed -i 's/mounts.*//g' /etc/cloud/cloud.cfg
sudo sed -i 's/.*ephemeral.*//g' /etc/cloud/cloud.cfg
sudo sed -i 's/.*swap.*//g' /etc/cloud/cloud.cfg

echo "mounts:" >> /etc/cloud/cloud.cfg
echo " - [ ephemeral0, /mnt, auto, \"defaults,noatime\", "\
  "\"0\", \"0\" ]" >> /etc/cloud.cloud.cfg
for x in {1..23}; do
  echo " - [ ephemeral$x, /mnt$((x + 1)), auto, "\
    "\"defaults,noatime\", \"0\", \"0\" ]" >> /etc/cloud/cloud.cfg
done

# Install Maven (for Hadoop)
wget "http://archive.apache.org/dist/maven/maven-3/3.2.3/binaries/apache-maven-3.2.3-bin.tar.gz";
tar xvzf apache-maven-3.2.3-bin.tar.gz
mv apache-maven-3.2.3 /opt/

# Edit bash profile & Cuda Variable
echo "export PS1=\"\\u@\\h \\W]\\$ \"" >> ~/.profile
echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64" >> ~/.profile
echo "export M2_HOME=/opt/apache-maven-3.2.3" >> ~/.profile
echo "export PATH=\$PATH:\$M2_HOME/bin:/root/spark/bin:/root/ephemeral-hdfs/bin:/usr/local/cuda/bin" >> ~/.profile
echo "export LD_LIBRARY_PATH=/usr/local/cuda/lib64" >> ~/.profile

source ~/.profile

# Install protoc version 2.5.0
mkdir /tmp/protobuf_install
cd /tmp/protobuf_install
wget https://github.com/google/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz
tar xzvf protobuf-2.5.0.tar.gz
cd  protobuf-2.5.0
./configure
make -j4
make check
sudo make install
sudo ldconfig
protoc --version

# Build Hadoop to install native libs
sudo mkdir /root/hadoop-native
cd /tmp
sudo apt-get install -y cmake libssl-dev
wget "http://apache.mirror.cdnetworks.com/hadoop/common/hadoop-2.8.0/hadoop-2.8.0-src.tar.gz"
tar xvzf hadoop-2.8.0-src.tar.gz
cd hadoop-2.8.0-src
mvn package -Pdist,native -DskipTests -Dtar
sudo mv hadoop-dist/target/hadoop-2.8.0/lib/native/* /root/hadoop-native

## Cuda , Driver (K520)
cd /root/
wget https://developer.nvidia.com/compute/cuda/8.0/Prod2/local_installers/cuda-repo-ubuntu1604-8-0-local-ga2_8.0.61-1_amd64-deb
sudo dpkg -i cuda-repo-ubuntu1604-8-0-local-ga2_8.0.61-1_amd64-deb
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get clean
sudo apt-get install -y cuda

# NVBLAS configuration
tee /root/nvblas.conf <<EOF
NVBLAS_LOGFILE  /root/nvblas.log
NVBLAS_CPU_BLAS_LIB  libblas.so
NVBLAS_GPU_LIST ALL0
NVBLAS_TILE_DIM 2048
NVBLAS_AUTOPIN_MEM_ENABLE
EOF

echo "export NVBLAS_CONFIG_FILE=/root/nvblas.conf" >> /etc/environment

# Create /usr/bin/realpath which is used by R to find Java installations
# NOTE: /usr/bin/realpath is missing in CentOS AMIs. See
# http://superuser.com/questions/771104/usr-bin-realpath-not-found-in-centos-6-5
echo '#!/bin/bash' > /usr/bin/realpath
echo 'readlink -e "$@"' >> /usr/bin/realpath
chmod a+x /usr/bin/realpath









