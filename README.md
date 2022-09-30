# Deploying a 5G Core with Monitoring (using Open5GS + Prometheus) for Beginners

During these lasts weeks I've been busy trying to add monitoring to a small 5G Core testbed environment we have at work. Until now we worked using [Open5GS](https://open5gs.org/) for the core network, while using [UERANSIM](https://github.com/aligungr/UERANSIM) for the RAN network. Open5GS does offer a way of integrating [Prometheus](https://prometheus.io/), a monitoring solution, so it extracts metrics from network functions (NFs) in such a way they can be visualized in a graphic interface and/or stored for later used.

However, while an official tutorial exists on how to [integrate Prometheus into Open5GS](https://open5gs.org/open5gs/docs/tutorial/04-metrics-prometheus/), as well as several unofficial guides, I feel that all these usually rely on the assumption that the reader is also familiar to deploying and using Prometheus. Additionally, as of the time of the writing of the post, the integration of both tools is still in development and the official tutorial still misses a few issues that might arise during installation.

The purpose of this post is to give guidance to those developers that might be somewhat familiar with Open5GS (or any other similar 5G Core solution) but are completely new to Prometheus. We will first introduce quickly how Prometheus works when the network is running, how we can extract metrics from it, and end by giving a detailed set-by-step guide on how to deploy a set of virtual machines (VMs) that run the 5G Core with metrics enabled, simulated UEs and RANs, and a Prometheus scrapper.

## How does Prometheus Work?

In our context, Prometheus has two components:
- A Prometheus server: it measures and generates the metrics, exposes them to a public address
- A Prometheus scrapper: it reads, processes and store the data exposed by the server

<img src="images/prometheus tutorial.png" title="Diagram showcasing a Prometheus Server and Scapper in context" width=300px></img>

The previous example shows what happens when Prometheus is integrated into Open5GS. When the core is launched, network functions that support metrics, such as the AMF, will also launch a Prometheus server. This server will obtain some metrics from the network function (e.g. number of active UEs) and other from the operating system itself (e.g. amount of seconds spent by the open5gs-amf instance running in the CPU).

The server will expose an address (IP + port, the latter usually 9090) in which the scrapper will be configured to access to obtain the recorded metrics. Specifically, to access the metrics the scrapper will to an HTTP GET request "/metrics" of the given address and will obtain an HTTP response in plain text as the following (Note that you can also access this URL from a browser!):
```
# HELP ran_ue RAN UEs
# TYPE ran_ue gauge
ran_ue 0

# HELP amf_session AMF Sessions
# TYPE amf_session gauge
amf_session 0

# HELP gnb gNodeBs
# TYPE gnb gauge
gnb 0

# HELP process_max_fds Maximum number of open file descriptors.
# TYPE process_max_fds gauge
process_max_fds 1024

# HELP process_virtual_memory_max_bytes Maximum amount of virtual memory available in bytes.
# TYPE process_virtual_memory_max_bytes gauge
process_virtual_memory_max_bytes -1

# HELP process_cpu_seconds_total Total user and system CPU time spent in seconds.
# TYPE process_cpu_seconds_total gauge
process_cpu_seconds_total 0

# HELP process_virtual_memory_bytes Virtual memory size in bytes.
# TYPE process_virtual_memory_bytes gauge
process_virtual_memory_bytes 155578368

# HELP process_resident_memory_bytes Resident memory size in bytes.
# TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 17956864

# HELP process_start_time_seconds Start time of the process since unix epoch in seconds.
# TYPE process_start_time_seconds gauge
process_start_time_seconds 492542263

# HELP process_open_fds Number of open file descriptors.
# TYPE process_open_fds gauge
process_open_fds 24
```

You can use the scrapper to store the values in a file, or present the information with diagrams in GUI as done in the ```prom/prometheus``` docker image:

<img src="images/prometheus gui 2.png" title="Image of prometheus GUI: targets" width=1200px></img>

<img src="images/prometheus gui 1.png" title="Image of prometheus GUI: graphs" width=1200px></img>

**It is important to know that, at the time of writing of this post, the only NFs that supports metrics are the AMF, SMF and MME.**

## Example deployment of Open5GS + Prometheus + UERANSIM

In this example, we are going to show how deploy a set up of a 5G Core with metrics enabled for the AMF and SMF network functions, and simulated UEs and RANs. In our sample deployment we will three VMs as follows:

<img src="images/5g deployment diagram.png" title="Diagram of sample deployment" width=500px></img>

- VM #1 will include the Open5GS core with metrics enabled (this include also the Prometheus Servers)
- VM #2 will include the simulated UEs and RANs using UERANSIM
- VM #3 will include the Prometheus scrapper

Here each, we assume each VM will have an IP address reachable from one another. For the sake example, we will assume the following addresses for each VM:
- VM #1 --> 10.0.0.1 
- VM #2 --> 10.0.0.2
- VM #3 --> 10.0.0.3

We have decided to use 3 VMs for this example because of two important reasons. First, as an example of a potential 5G testbed it is best to separate the hardware resources that simulated the core and network edge. If you want to complicate it further you could also consider splitting the core into two VMs, one which manages the network functions relative to the control plane (e.g. SMF, AUSF) and another which manages the user plane (e.g. UDF). I believe it is also important in separating metric scrapping so it also does starve resources away from the core or RAN. The second reason is that in the case you wished to run everything on the same machine you can follow the same steps as follows, but omitting the steps in which modify the IP addresses in the configuration files.

### Step 1: Install UERANSIM at VM #2

First we install the dependencies:
```
sudo apt update
sudo apt upgrade
sudo apt install make g++ libsctp-dev lksctp-tools
iproute2 sudo snap install cmake -classic
```

Then we clone the repository at our preferred directory:
```
git clone https://github.com/aligungr/UERANSIM
cd UERANSIM
make
```

While UERANSIM is ready to run, we first must make some changes to configuration files that come by default in the repository. For those unaware, UERANSIM comes with several configuration files located at UERANSIM/config, for different 5G Core implementations. The ones we are interested on are the configuration files of the gNBs (open5gs-gnb.yaml) and UEs (open5gs-ue.yaml) for Open5GS. Open both of them and perform the following changes:

- By default, the files use MCC and MNC values of 999 and 70 respectively. It is important that these values match with those configured in the core network as well. If we wish to change those values (e.g. use 901 and 70) we will need to change the mcc and mnc fields of both files (and the SUPI field in the UE configuration file too).
    - open5gs-gnb.yaml
    ```
    # BEFORE
    mcc: '999'          # Mobile Country Code value
    mnc: '70'           # Mobile Network Code value (2 or 3 digits)
    
    # AFTER
    mcc: '901'          # Mobile Country Code value
    mnc: '70'           # Mobile Network Code value (2 or 3 digits)
    ```
    - open5gs-ue.yaml:
    ```
    # BEFORE
    supi: 'imsi-999700000000001'
    # Mobile Country Code value of HPLMN
    mcc: '999'
    # Mobile Network Code value of HPLMN (2 or 3 digits)
    mnc: '70'

    # AFTER
    supi: 'imsi-901700000000001'
    # Mobile Country Code value of HPLMN
    mcc: '901'
    # Mobile Network Code value of HPLMN (2 or 3 digits)
    mnc: '70'
    ```
- In open5gs-gnb.yaml we must also change all the references to the local IP with our public IP, as well as changing the AMF's IP with VM #1's IP.
```
# BEFORE
linkIp: 127.0.0.1   # gNB's local IP address for Radio Link Simulation (Usually same with local IP)
ngapIp: 127.0.0.1   # gNB's local IP address for N2 Interface (Usually same with local IP)
gtpIp: 127.0.0.1    # gNB's local IP address for N3 Interface (Usually same with local IP)
# List of AMF address information
amfConfigs:
  - address: 127.0.0.5
    port: 38412

# AFTER
linkIp: 10.0.0.2   # gNB's local IP address for Radio Link Simulation (Usually same with local IP)
ngapIp: 10.0.0.2   # gNB's local IP address for N2 Interface (Usually same with local IP)
gtpIp:  10.0.0.2    # gNB's local IP address for N3 Interface (Usually same with local IP)
# List of AMF address information
amfConfigs:
  - address: 10.0.0.1
    port: 38412
```
- In open5gs-ue.yaml we must also change the ```gnbSearchList``` value so it reflects the public IP of the current VM:
```
# BEFORE
gnbSearchList:
  - 127.0.0.1

# AFTER
gnbSearchList:
  - 10.0.0.2
```

Once the configuration files have been changed, both the gNBs and UEs can be run with the following commands:
```
# Launch gNB 
sudo {PATH_2_UERANSIM}/UERANSIM/build/nr-gnb -c {PATH_2_UERANSIM}/UERANSIM/config/open5gs-gnb.yaml &

# Launch UE
sudo {PATH_2_UERANSIM}/UERANSIM/build/nr-ue -c {PATH_2_UERANSIM}/UERANSIM/config/open5gs-ue-$i.yaml &

# Launch multiple UEs (with increasingly values of MSIN)
sudo {PATH_2_UERANSIM}/UERANSIM/build/nr-ue -n {NUMBER_UES} -c {PATH_2_UERANSIM}/UERANSIM/config/open5gs-ue-$i.yaml &

# Stop gNB
sudo pkill nr-gnb

# Stop UE
sudo pkill nr-ue
```

### Step 2: Download and compile Open5GS at VM #1

Since we need Prometheus support at the core we are forced to install open5gs by downloading and compiling the source code rather than using a packet manager. The first step is to install MongoDB following the instructions at https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-ubuntu/. Once installed remember to run it:
```
sudo systemctl start mongodb
```

Then, we’ll download, compile and install open5gs with Prometheus support. The following steps show how to do so, as well as installing any dependencies and configuring the compilation to add Prometheus support:

```
sudo apt install python3-pip python3-setuptools python3-wheel ninja-build build-essential flex bison git libsctp-dev libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev libnghttp2-dev libtins-dev libtalloc-dev meson
git clone https://github.com/open5gs/open5gs
cd open5gs
meson build --prefix=`pwd`/install && meson configure -Dmetrics_impl=prometheus build
ln -s `pwd`/subprojects/ `pwd`/../subprojects
ninja -C build
cd build
ninja install
```

After completing the compilation, we can apply some changes to the NFs' configuration files (found at open5gs/install/etc/open5gs/). These changes include:
- Changing in all the appropriate files the MCC and MNC. This can be done quickly with the sed command (remember that by default open5gs uses MCC=999, MNC=70):
```
cd {PATH_2_open5gs}/open5gs/install/etc/open5gs/
sed -i -e "s/mcc: 999/mcc: 901/g" ./*
```
- Make the AMF listen for NGAP messages (messages from the RAN) outside the VM. This is done by changing the subfield ```ngap``` within ```amf``` inside the amf.yaml file by replacing the local IP address with the VM's public one:
```
# BEFORE
   ngap:
      - addr: 127.0.0.5

# AFTER
   ngap:
      - addr: 10.0.0.1
```
- Set up the Prometheus server addresses for both the AMF and SMF. This includes replacing the default local IP address with the public one, so that the scrapper in VM #3 can access it, and making sure they don't share the same port (otherwise one server will block the other one from running!)
  - amf.yaml
  ```
  # BEFORE
     metrics:
        addr: 127.0.0.5
        port: 9090
  # AFTER
     metrics:
        addr: 10.0.0.1
        port: 9090
  ```
  - smf.yaml
  ```
  # BEFORE
     metrics:
        addr: 127.0.0.4
        port: 9090
  # AFTER
     metrics:
        addr: 10.0.0.1
        port: 9091
  ```

After those changes we need to move the different files from the installation folder to their correct locations to execute the core from the terminal:
```
# Move the configuration files to /etc/open5gs
cd {PATH_2_open5gs}/open5gs/install/etc/open5gs/
sudo cp ./* /etc/open5gs/

# Move the libcm_prom.so file in open5gs/install/lib to /usr/lib/
cd ../../lib
sudo cp libcm_prom.so /usr/lib/

# Move the compiled NF's executables to /usr/bin
cd ../bin 
sudo cp ./* /usr/bin/
```

The core is ready to use. To run the code we simply execute the following commands in the background. It can clutter the terminal quickly, hence it would be best to have their output redirected away from STDOUT or run them in a virtual terminal like tmux:
```
sudo pkill open5gs-*
open5gs-mmed &
open5gs-sgwcd &
open5gs-smfd &
open5gs-amfd &
open5gs-sgwud &
open5gs-upfd &
open5gs-hssd &
open5gs-pcrfd &
open5gs-nrfd &
open5gs-ausfd &
open5gs-udmd &
open5gs-pcfd &
open5gs-nssfd &
open5gs-bsfd &
open5gs-udrd &
```

To stop the core at any moment simply run:
```
sudo pkill open5gs-*
```

Also, to run UEs we must register them beforehand. While this can be done using a GUI, when dealing with adding many UEs with the default configuration it is more practical to use the ```open5gs-dbctl``` tool in open5gs/misc/db. To do so we simply use the following template of a bash script [add_ues.sh](add_ues.sh), fill in the gaps and run it. We must also verify that the key and opc fields match those present in UERANSIM open5gs-ue.yaml, otherwise the UEs will not be able to authenticate in the core.
```
#!/bin/bash
n=901700000000001

key='465B5CE8B199B49FAA5F0A2EE238A6BC'
opc='E8ED289DEBA952E4283B54E88E6183CA'

for i in $(seq 0 {NUM_UES}); do
    {PATH_2_open5gs}/open5gs/misc/db/open5gs-dbctl add $n $key $opc
    n=$(($n+1))
done
```

### Step 3: Setting up the Prometheus Scrapper in VM #3

Luckily, we can use a premade scrapper present in the docker image ```prom/prometheus```. The only requisite is to have docker engine installed and running: https://docs.docker.com/engine/install/ubuntu/#installation-methods.

To configure the scrapper, we will need to define a [prometheus.yml](prometheus.yml) file with our configuration. Here we show a configuration file that would scan the addresses we specified before for the AMF and SMF functions with the highest frequency available for Prometheus (updates every second):
```
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.

  # Attach these labels to any time series or alerts when communicating with
  # external systems (federation, remote storage, Alertmanager).
  external_labels:
    monitor: 'codelab-monitor'

scrape_configs:
  - job_name: open5gs-amfd
    scrape_interval: 1s
    static_configs:
      - targets: ["10.0.0.1:9090"]
  - job_name: open5gs-smfd
    scrape_interval: 1s
    static_configs:
      - targets: ["10.0.0.1:9091"]
```

To run the docker we must only remember to expose the port 9090 so we can access the GUI and bind our configuration file to the configuration file within the image:
```
docker run -d -p 9090:9090 -v {PATH_2_PROMETHEUS_CONFIG}/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus
```

Once running, we can access Prometheus' GUI via http://10.0.0.3:9090.

If we wished to build our on scrapper instead, we would instead write a program that would perform periodic HTTP GET requests at http://10.0.0.1:9090/metrics and http://10.0.0.1:9091/metrics for the AMF and SMF respectively.

### Step 4: Running everything
To run everything correctly, the elements must run in the following order:
1. Initialize the core
2. Initialize the prometheus GUI
3. Launch the gNBs
4. Launch the UEs

## References

If you had any issues following this guide, or you simply want more information about the Open5GS + Prometheus or the sample deployment, I recommend reading the following posts:
- https://open5gs.org/open5gs/docs/troubleshoot/01-simple-issues/ 
- https://open5gs.org/open5gs/docs/guide/02-building-open5gs-from-sources/
- https://open5gs.org/open5gs/docs/tutorial/04-metrics-prometheus/
- https://github.com/open5gs/open5gs/issues/1559
- https://github.com/s5uishida/open5gs_5gc_ueransim_metrics_sample_config
- https://nickvsnetworking.com/my-first-5g-core-open5gs-and-ueransim/
