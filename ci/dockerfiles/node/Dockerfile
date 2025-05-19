FROM golang:1.23.6

WORKDIR /app

# Установим необходимые зависимости
RUN apt-get update && apt-get install -y make git gcc curl jq && apt-get clean

# Копируем исходники
COPY . .

# ENV для отключения Ledger и установки testnet chain-id
ENV CHAIN_ID=localchain_90001-1
ENV BLOCK_TIME=1000ms

# По умолчанию — запуск локального тестнета
CMD ["make", "sh-testnet"]

