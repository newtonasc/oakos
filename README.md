# OakOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Um sistema operacional onde **o agente é a interface**.

Não há desktop, não há gerenciador de arquivos, não há um terminal esperando
que você saiba o nome do comando certo. Você boota, descreve o que quer, e o
sistema constrói.

## A ideia

Todo SO moderno define sua identidade no *userspace*, não no kernel. ChromeOS é
Linux com um navegador no lugar do desktop. SteamOS é Arch com uma loja de
jogos. O OakOS é Linux com um **agente** no lugar do shell.

O kernel, os drivers, a pilha de rede e o TLS vêm prontos do Debian — resolver
isso de novo custaria uma década e não é onde está a ideia. O esforço inteiro
vai para a camada de cima.

```
┌──────────────────────────────────────────────┐
│  oak            o agente É a interface       │  ← o projeto
├──────────────────────────────────────────────┤
│  userspace mínimo  systemd · rede · node     │  ← montado por nós
├──────────────────────────────────────────────┤
│  kernel Linux                                │  ← herdado do Debian
└──────────────────────────────────────────────┘
```

## Pré-requisitos

```bash
sudo apt install -y mmdebstrap uidmap debian-archive-keyring \
    e2fsprogs qemu-system-x86 qemu-utils
sudo usermod -aG kvm $USER    # depois reabra o terminal
```

Nada disso exige root na hora de construir: a imagem é montada dentro de um
*user namespace* (`mmdebstrap --mode=unshare`), onde o seu usuário aparece como
root sem de fato ser.

## Uso

```bash
make        # constrói o rootfs e a imagem (primeira vez: ~5-10 min)
make run    # boota no QEMU
```

Abra `http://localhost:8080` no navegador do seu computador — é a IDE
(code-server, com a extensão oficial do Claude Code), acessível assim que a VM
termina de subir. O QEMU encaminha a porta, e o WSL2 repassa pro Windows sem
configuração extra.

Para sair do QEMU: `ctrl-a` seguido de `x`.

Se o Oak quebrar e você precisar de um shell de verdade:

```bash
OAK_CMDLINE="OAK_NO_SHELL=1" ./run.sh
```

## Estrutura

| Caminho | O que é |
|---|---|
| `image/packages.list` | os pacotes do sistema base |
| `image/chroot-setup.sh` | roda dentro do rootfs: é onde o Debian vira OakOS |
| `image/build-rootfs.sh` | Debian → `build/rootfs.tar` |
| `image/build-image.sh` | tarball → disco ext4 + kernel + initrd |
| `overlay/` | arquivos copiados no rootfs (a identidade do sistema) |
| `overlay/usr/local/bin/oak` | **o agente** — o coração do projeto |
| `run.sh` | sobe a VM |
| `attic/bare-metal/` | kernel x86_64 do zero, parado (ver abaixo) |

## Decisões tomadas

**Boot direto pelo QEMU, sem bootloader.** `-kernel`/`-initrd` economiza ~10s
por ciclo de teste. Um bootloader (systemd-boot ou Limine) entra quando a
imagem precisar bootar fora do QEMU.

**Sem senha de root e autologin.** É uma VM de desenvolvimento local. Precisa
mudar antes de qualquer uso real.

**Uma partição só.** Sem ESP, sem swap, sem `/home` separado. Simplicidade
enquanto o formato do sistema ainda está em aberto.

**zsh como shell de login, mas sem desktop nenhum.** O `oak` roda em cima de
um terminal comum (serial + tty) — não há Xorg, Wayland ou compositor. A IDE e
o navegador do sistema são o **code-server** (VS Code no navegador) e o
**Chromium headless**, comandado por **Playwright**: o agente pode abrir
páginas, esperar elementos e tirar screenshot do que ele mesmo construiu, sem
que isso exija uma pilha gráfica dentro da VM. Se um dia fizer sentido um
desktop de verdade (Wayland + compositor), é uma decisão à parte — bem mais
cara em complexidade e tamanho de imagem, e destoa da premissa de "sem
desktop" do projeto.

**`attic/bare-metal/`** guarda um kernel x86_64 escrito do zero (Limine,
framebuffer, serial). Foi o começo do projeto, antes de ficar claro que o
objetivo exigia rodar Node.js e TLS. Está parado, mas é material de estudo
honesto sobre o que um kernel realmente faz.

**Docker vem do repositório oficial da Docker Inc., não do Debian.** O pacote
do Debian (`docker.io`) costuma estar bem atrasado. `docker compose` (o
plugin v2, com espaço) vem junto; um atalho em `/usr/local/bin/docker-compose`
cobre quem ainda digita com hífen por hábito.

**Portas de projeto: uma lista, não uma só.** `run.sh` encaminha `8080` (IDE)
mais um bloco dos padrões mais comuns de dev server (`3000-3002`, `5173-5174`,
`8000-8001`, `5000`) — dá pra rodar uns 3 projetos ao mesmo tempo e abrir cada
um no seu navegador sem editar nada. Precisa de mais alguma? `OAK_PORTS="4000
9000" ./run.sh`. Isso só afeta o que **você** vê de fora — projetos dentro da
VM já se enxergam livremente entre si por `localhost` (ou por nome de serviço,
se estiverem no mesmo `docker compose`), independente dessa lista.

## Estado atual

**v0.1** — boota, tem rede, o Oak assume o console (zsh por baixo), o Claude
Code vem instalado, com uma animação de entrada (a bolota virando carvalho,
o mascote do projeto). IDE (code-server + extensão oficial do Claude Code)
sobe sozinha em `:8080`. Chromium headless + Playwright disponíveis pro
agente testar o que ele mesmo constrói. Docker + `docker compose` prontos
pra orquestrar múltiplos projetos.

**Mais de um Claude ao mesmo tempo:** pela IDE já funciona sem nada especial
— cada painel de terminal do code-server é um zsh comum, independente do
Oak. No console cru, o comando `sessoes` abre um `tmux`, multiplexando a
única linha serial em várias janelas (`ctrl+b c` nova janela, `ctrl+b n`/`p`
alterna) — cada uma roda `claude` direto.

## Próximos passos

- [ ] Login persistente da conta Claude entre boots
- [ ] O agente operar o próprio sistema (pacotes, serviços, rede) por descrição
- [ ] Autenticação de verdade na IDE (hoje `--auth none`, aceitável só porque
      a porta não sai do seu próprio host)
- [ ] Imagem auto-bootável (bootloader + ESP) para pendrive e VPS
- [ ] Workspace persistente separado do sistema

## Licença

[MIT](LICENSE).
