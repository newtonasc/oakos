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

O kernel, os drivers, a pilha de rede e o TLS vêm prontos do Debian: resolver
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
    e2fsprogs qemu-system-x86 qemu-utils gdisk mtools ovmf
sudo usermod -aG kvm $USER    # depois reabra o terminal
```

`gdisk`, `mtools` e `ovmf` só entram pela imagem auto-bootável (`make
bootable`/`make run-bootable`); se for só usar `make run`, os outros já
bastam.

Nada disso exige root na hora de construir: a imagem é montada dentro de um
*user namespace* (`mmdebstrap --mode=unshare`), onde o seu usuário aparece como
root sem de fato ser.

## Uso

```bash
make             # constrói o rootfs e a imagem (primeira vez: ~5-10 min)
make run         # boota rápido no QEMU (-kernel/-initrd, sem bootloader)
make run-bootable  # boota a imagem GPT via UEFI (OVMF) -- mais fiel a
                    # pendrive/VPS, mais lento de iterar
```

Abra `http://localhost:8080` no navegador do seu computador: é a IDE
(code-server, com a extensão oficial do Claude Code), acessível assim que a VM
termina de subir. O QEMU encaminha a porta, e o WSL2 repassa pro Windows sem
configuração extra.

Para sair do QEMU: `ctrl-a` seguido de `x`.

Uso do dia a dia (comandos do Oak, sessões, IDE, persistência): ver
[`MANUAL.md`](MANUAL.md).

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
| `image/build-data.sh` | cria (uma vez só) o disco de dados persistente |
| `image/build-bootable.sh` | rootfs → imagem GPT (ESP + systemd-boot) auto-bootável |
| `overlay/` | arquivos copiados no rootfs (a identidade do sistema) |
| `overlay/usr/local/bin/oak` | **o agente**, o coração do projeto |
| `run.sh` | sobe a VM (boot rápido, -kernel/-initrd) |
| `run-bootable.sh` | sobe a imagem GPT via firmware UEFI (OVMF) |
| `attic/bare-metal/` | kernel x86_64 do zero, parado (ver abaixo) |

## Decisões tomadas

**Dois caminhos de boot, não um só.** `make run` continua sem bootloader
(`-kernel`/`-initrd` direto no QEMU): economiza ~10s por ciclo, é o padrão
pro dia a dia. `make run-bootable` gera e sobe uma imagem GPT de verdade
(ESP + **systemd-boot**, via firmware UEFI/OVMF): é o que um pendrive ou
VPS entenderia sozinho, sem QEMU passando kernel na mão por fora. Escolhido
**systemd-boot** em vez de GRUB por ser mais simples de montar sem privilégio
(um binário `.efi` + duas entradas de texto, nada de `grub-mkconfig`) e por
já combinar com o resto do sistema, que é systemd de ponta a ponta.

**Sem senha de root e autologin.** É uma VM de desenvolvimento local. Precisa
mudar antes de qualquer uso real.

**Dois discos, cada um com uma partição só.** `oakos.ext4` (o sistema,
recriado do zero a cada `make`) e `oakos-data.ext4` (workspace, conta Claude,
config da IDE; nunca apagado por `make`/`make clean`). Nenhum dos dois tem
ESP ou swap. O bind mount (via `overlay/etc/fstab`) é o que faz caminhos como
`/root/workspace` apontarem pro disco de dados sem o resto do sistema
precisar saber disso.

**zsh como shell de login, sem desktop no boot.** O `oak` roda em cima de um
terminal comum (serial + tty): não há Xorg, Wayland ou compositor ligados por
padrão. A IDE e o navegador do sistema são o **code-server** (VS Code no
navegador) e o **Chromium headless**, comandado por **Playwright**: o agente
pode abrir páginas, esperar elementos e tirar screenshot do que ele mesmo
construiu.

Quando algo precisa mesmo de uma janela (um app Electron, o próprio Chromium
sem `--headless`), existe o comando `tela`: liga um framebuffer virtual
(**Xvfb**) com um window manager leve (**fluxbox**) e abre um totem em tela
cheia com seis ícones -- Shell, Claude, Chrome, Herdr, IDE e Explorer
(**pcmanfm**) -- cada um abrindo sua janela (terminal em tela cheia e
fundo preto, ou uma nova janela do Chromium). Tela cheia sem decoração,
mas de propósito **sem** o estado fullscreen de verdade do X11
(`_NET_WM_STATE_FULLSCREEN`, via `--kiosk`/`-fullscreen`): testado que o
fluxbox trava esse estado numa camada de empilhamento que nunca reordena
com janela nova nenhuma. Em vez disso, tamanho/posição/decoração vêm de
uma regra do próprio fluxbox (`overlay/root/.fluxbox/apps`), o que deixa
tudo na camada normal, onde "janela nova aparece por cima" funciona de
verdade. Como cada ícone abre em tela cheia e some com o totem, um botão
flutuante (**Tkinter**) fica sempre visível por cima -- clicar abre uma
instância nova do totem por cima de tudo. Servido por VNC/navegador
(**x11vnc** + **noVNC**).
Fica desligado até alguém pedir, para não pesar RAM em toda VM que nunca
usa tela gráfica (ver
`overlay/etc/systemd/system/{xvfb,wm,launcher,browser,totem-button,x11vnc,novnc}.service`,
nenhum `enabled`).

Não é um desktop: sem barra de tarefas, sem múltiplas janelas coordenadas,
sem nada além do que uma janela precisa pra existir. Um desktop de verdade
(Wayland + compositor completo) continua sendo uma decisão à parte: bem mais
cara em complexidade e tamanho de imagem.

**SSH sempre ligado, só por chave pública.** `openssh-server` sobe no boot
(`systemctl enable ssh`), mas como o root não tem senha (ver abaixo),
`PasswordAuthentication no` faz da chave pública o único jeito de entrar: sem
nenhuma configurada, ninguém acessa. `run.sh` encaminha a porta `2222` do
host pra `22` da VM (`ssh -p 2222 root@localhost`) -- serve de alternativa
ao console serial quando o QEMU não está aberto na sua frente. Ver
`overlay/etc/ssh/sshd_config.d/oakos.conf`.

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
`8000-8001`, `5000`): dá pra rodar uns 3 projetos ao mesmo tempo e abrir cada
um no seu navegador sem editar nada. Precisa de mais alguma? `OAK_PORTS="4000
9000" ./run.sh`. Isso só afeta o que **você** vê de fora; projetos dentro da
VM já se enxergam livremente entre si por `localhost` (ou por nome de serviço,
se estiverem no mesmo `docker compose`), independente dessa lista.

## Estado atual

**v0.1**: boota, tem rede, o Oak assume o console (zsh por baixo), o Claude
Code vem instalado, com uma animação de entrada (a bolota virando carvalho,
o mascote do projeto). IDE (code-server + extensão oficial do Claude Code)
sobe sozinha em `:8080`, com senha (gerada pelo próprio code-server no
primeiro boot; o `oak status` mostra qual é). Chromium headless + Playwright
disponíveis pro agente testar o que ele mesmo constrói. Docker + `docker
compose` prontos pra orquestrar múltiplos projetos.

**Persistência:** um segundo disco (`build/oakos-data.ext4`, criado uma vez
só por `image/build-data.sh`) guarda o workspace, a conta Claude logada e a
senha da IDE: sobrevive tanto a reinícios quanto a `make clean`/rebuild da
imagem do sistema, que é recriada do zero a cada `make`.

**Acesso e ferramentas de dev:** SSH sempre ligado, só por chave pública (ver
"Decisões tomadas" acima). Ferramentas nativas via `apt`: `build-essential`
(gcc/make), `python3` (+ `venv`/`pip`), `jq`, `zip`/`unzip`.

**Tela virtual:** desligada por padrão, liga sob demanda com o comando
`tela` dentro da VM. Ver "Decisões tomadas" acima.

**Mais de um Claude ao mesmo tempo:** pela IDE já funciona sem nada especial:
cada painel de terminal do code-server é um zsh comum, independente do
Oak. No console cru, o comando `sessoes` abre o [Herdr](https://herdr.dev/),
que mantém o `claude` rodando em background mesmo se você fechar o terminal
ou a conexão cair; na próxima vez, `sessoes` reanexa do jeito que ficou.
Substituiu o `tmux`, que fazia o mesmo multiplexing mas sem sobreviver a
desconexão.

**Imagem auto-bootável:** `make bootable` monta um disco GPT (ESP +
systemd-boot) a partir do mesmo rootfs; `make run-bootable` testa via
firmware UEFI (OVMF) real, sem `-kernel`/`-initrd`. Validado de ponta a
ponta: BdsDxe carrega o `BOOTX64.EFI` de fallback (sem entrada gravada na
NVRAM, do jeito que um pendrive ou VPS chegaria), o systemd-boot sobe o
kernel, e o Oak assume o console normalmente.

## Próximos passos

- [ ] Validar que o agente já opera o próprio sistema (pacotes, serviços,
      rede) por descrição via `claude` dentro do shell: hipótese é que já
      funciona hoje, sem nada novo pra construir; falta confirmar rodando
      (exige login de verdade, não dá pra automatizar)

## Licença

[MIT](LICENSE).
