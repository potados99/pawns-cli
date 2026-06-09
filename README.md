# pawns-cli

Run [IPRoyal Pawns](https://pawns.app) CLI without Docker on Linux (x86_64/aarch64).

Extracts the statically-linked binary from the official `iproyal/pawns-cli` Docker image so you can run it directly.

## Install

```sh
wget -qO- https://raw.githubusercontent.com/potados99/pawns-cli/main/install.sh | bash
```

## Usage

```sh
pawns-cli -email you@example.com -password yourpass -device-name my-device -device-id my-id -accept-tos
```

## Run as systemd service

```sh
sudo cp systemd/pawns-cli.service /etc/systemd/system/
sudo systemctl edit pawns-cli   # set EMAIL, PASSWORD, DEVICE_NAME, DEVICE_ID
sudo systemctl enable --now pawns-cli
```

## Update

Re-run the install script. The binary is a single static executable — just overwrite it.

## Extract (for maintainers)

```sh
./extract.sh
```
