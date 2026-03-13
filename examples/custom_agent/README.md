# Cross Compile the Micro XRCE-DDS Agent

Before running the Micro-ROS demo on the CR8 core, you need to cross-compile the custom Micro XRCE-DDS Agent for the Linux CA55 core.

1. Make sure your machine have the Docker engine installed and running.

   You can use Windows, Linux, or macOS as your host machine.
   For the best experience, it is recommended to use a **Ubuntu 24.04 host machine** for cross-compilation.
   If you are using Windows or macOS, please ensure that Docker Desktop is properly set up and configured to use Linux containers.

2. Clone the `Micro-XRCE-DDS-Agent` to your local machine:

   ```bash
   git clone https://github.com/renesas-rdk/Micro-XRCE-DDS-Agent.git
   ```

3. Pull the Docker image provided by Renesas RDK for cross-compilation:

   ```bash
   docker pull ghcr.io/renesas-rdk/rzv2h_ubuntu_xbuild:latest
   ```

4. Create a new Docker container:

   ```bash
   docker run -it --rm -v /path/to/Micro-XRCE-DDS-Agent:/home/ubuntu/Micro-XRCE-DDS-Agent ghcr.io/renesas-rdk/rzv2h_ubuntu_xbuild:latest
   ```

   Replace `/path/to/Micro-XRCE-DDS-Agent` with the actual path on your host machine where the repository is located.

5. Access to the Micro-XRCE-DDS-Agent directory **inside the Docker container**:

   ```bash
   cd ~/Micro-XRCE-DDS-Agent/
   ```

6. Build the project:

   ```bash
   mkdir build && cd build

   cmake .. -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAINS_WS/cross.cmake \
            -DUAGENT_BUILD_USAGE_EXAMPLES=ON \
            -DUAGENT_LOGGER_PROFILE=OFF \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX=./arm64-install

   make -j$(nproc)
   make install
   ```

   Note that the ``-DUAGENT_LOGGER_PROFILE`` is set to OFF due to incompatibility during cross-building. If you want to see the logs, please build the libraries natively on the RZ/V2H RDK without the ``-DUAGENT_LOGGER_PROFILE=OFF`` flag.

7. Wait until the build process completes.

8. Deploy the output to the target board by copying the output artifact:

   - On the **Host machine**:

     ```bash
     # Copy the built CustomXRCEAgent binary to the arm64-install folder for deployment
     cp ./examples/custom_agent/CustomXRCEAgent arm64-install/bin
     # Compress the arm64-install folder
     tar -cf libdds_agent.tar.bz2 -C arm64-install .
     ```

   - Then copy `libdds_agent.tar.bz2` to the target board using **scp** or another file transfer method.

   - On the **Target machine**:

     ```bash
     # Extract the archive
     mkdir tmp-install
     sudo tar -xf libdds_agent.tar.bz2 -C tmp-install
     # Install libdds_agent to the system
     cd tmp-install
     sudo cp -r * /usr/local/
     sudo ldconfig
     ```

Please refer to the [ RZ/V2H RDK Documentation - Multi OS section](https://renesas-rdk.github.io/rzv2h_rdk_documentation/latest/index.html) for instructions on how to run the demo using the custom Micro XRCE-DDS Agent.