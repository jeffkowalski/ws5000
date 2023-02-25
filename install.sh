#!/usr/bin/env sh

SERVICE=ws5000
sudo systemctl --quiet stop $SERVICE
sudo systemctl --quiet disable $SERVICE
envsubst < $SERVICE.service.template > $SERVICE.service
chmod 700 $SERVICE.service
sudo rm -rf /etc/systemd/system/$SERVICE.service
sudo ln -s "$PWD/$SERVICE.service" /etc/systemd/system/ && \
  sudo systemctl daemon-reload && \
  sudo systemctl enable $SERVICE && \
  sudo systemctl start $SERVICE
sudo systemctl status $SERVICE
