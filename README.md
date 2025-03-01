# Dropbear + Stunnel Docker Image

## Overview
This Docker image provides a **secure SSH and TLS tunneling environment** using **Dropbear** (a lightweight SSH server) and **Stunnel** (a TLS wrapper). It enables users to establish encrypted connections while maintaining a lightweight SSH server for efficient remote access.

## Features
- **Dropbear SSH server** running on port **5000**
- **Stunnel TLS proxy** listening on port **4442**
- Automatic SSL certificate generation if not provided
- Optimized for low-resource environments
- Built-in cron job support
- Suitable for **secure remote access** and **tunneling applications**

## Getting Started
### Prerequisites
Ensure that **Docker** is installed on your system.

### Installation & Usage
To pull and run the container, open a terminal and execute:
```sh
docker run --privileged -d -p 5000:5000 -p 4442:4442 nuntiusdev/dropbear-stunnel
```
This command will start the Dropbear SSH server on port **5000** and the Stunnel TLS proxy on port **4442**.

### Resetting the Root Password
If you need to reset the root password inside the container, use:
```sh
docker exec -it <container_id> sh -c "echo 'root:new_password' | chpasswd"
```
Replace `<container_id>` with the actual running container ID and `new_password` with your desired password.

## Ports & Configuration
- **5000** → SSH access via Dropbear
- **4442** → TLS tunnel via Stunnel

Ensure that both ports are open and accessible to establish connections.

## Contributing
Feel free to contribute by opening issues or submitting pull requests.

## License
This project is open-source and available under the **MIT License**.

## Contact
For any questions or support, reach out to **[NuntiusDev](https://github.com/nuntius-dev)**.

