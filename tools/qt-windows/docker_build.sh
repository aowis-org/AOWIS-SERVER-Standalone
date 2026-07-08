docker build \
  --network=host \
  -f Dockerfile.qt-windows \
  -t aowis-qt-windows:6.7 \
  .
