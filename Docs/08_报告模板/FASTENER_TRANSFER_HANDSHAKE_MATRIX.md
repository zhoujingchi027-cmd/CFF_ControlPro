
# CFF元件传送握手矩阵

| Route | Source | Destination | Source Ready | Destination Ready | Transfer Owner | Timeout |
|---|---|---|---|---|---|---|
| Magazine | Fastener Station | Magazine | bFastenerReadyToSend | bReadyToReceive | Fastener Station | |
| Magazine | Magazine | Gun Head Feed | bFastenerReadyToSend | bReadyToReceive | Magazine | |
| Direct Blow | Fastener Station | Gun Head Feed | bFastenerReadyToSend | bReadyToReceive | Fastener Station | |
