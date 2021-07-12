#Download base image python buster
FROM nvidia/opencl

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV DEBIAN_FRONTEND=noninteractive 
ENV DEBCONF_NONINTERACTIVE_SEEN=true

RUN apt-get update
RUN apt install -y apt-utils
RUN apt install -y software-properties-common
RUN add-apt-repository -y ppa:deadsnakes/ppa

RUN apt-get install -y python3.8-dev && \
    apt-get install -y python3-pip && \
    apt-get install -y python3-tk && \
    apt-get install -y ocl-icd* opencl-headers &&\
    apt-get install -y libclfft* &&\
    apt-get install -y git &&\
    apt-get install -y pocl-opencl-icd

RUN apt-get install -y pkg-config
RUN apt-get install -y libhdf5-dev

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT 50000
RUN useradd -d "$JENKINS_HOME" -u 971 -m -s /bin/bash jenkins
VOLUME /var/jenkins_home

ENV PATH="/var/jenkins_home/.local:${PATH}"

RUN python3.8 -m pip install cython 
RUN python3.8 -m pip install mako
RUN python3.8 -m pip install pybind11
RUN git clone https://github.com/inducer/pyopencl.git
RUN cd pyopencl && python3.8 configure.py --cl-pretend-version=1.2
RUN cd pyopencl && python3.8 setup.py install

    
RUN git clone https://github.com/geggo/gpyfft.git &&\
    python3.8 -m pip install gpyfft/. &&\
    python3.8 -m pip install pytest &&\
    python3.8 -m pip install pytest-cov &&\
    python3.8 -m pip install pylint &&\
    python3.8 -m pip install pylint_junit &&\
    python3.8 -m pip install pytest-integration
