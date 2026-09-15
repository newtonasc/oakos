# Manual do OakOS

Guia de uso do dia a dia. Para instalar e construir a imagem, veja o
`README.md`. Este documento assume que a VM já está rodando.

## O console: o Oak assume tudo

Ao logar (autologin de root, console serial ou `tty1`), o `.zprofile`
lança o `oak` na hora. Não existe um shell "cru" esperando comando: você
cai direto numa conversa.

```
oak > _
```

Digite o que você quer, em português mesmo:

```
oak > cria um servidor http em go que responde a hora atual
```

Isso vira um pedido pro `claude`, que trabalha dentro da VM com acesso
normal a bash, git, docker, o que precisar.

## Comandos nativos

Só estes sete têm tratamento especial. Qualquer outra coisa digitada,
mesmo que pareça um comando de shell (`ls`, `curl`, `docker ps`),
vira pedido pro agente, não execução direta.

| Comando | O que faz |
|---|---|
| `login` | conecta a conta Claude a esta VM (`claude /login`) |
| `status` | mostra rede, agente, conta, IDE e tela |
| `shell` | cai num zsh de verdade, sem o Oak no meio |
| `tela` (ou `gui`/`vnc`) | liga a tela virtual (janela de verdade via VNC/navegador) |
| `sessoes` (ou `agentes`) | abre o Herdr, pra rodar mais de um `claude` ao mesmo tempo |
| `ajuda` | esta lista, direto no console |
| `desligar` | encerra a VM |

Aliases aceitos: `sessions`/`herdr` também abrem o Herdr; `sair`/`exit`
também desligam.

## `shell`: acesso direto, sem o agente

`git clone`, `docker compose up`, `npm install`: qualquer coisa que você
já sabe fazer de cor roda ali direto. Além do básico (git, docker), já vêm
instalados `python3` (com `venv`/`pip`), `build-essential` (gcc/make, pra
dependência nativa de pacote npm), `jq` e `zip`/`unzip`.

```
oak > shell
  (digite 'exit' pra voltar ao Oak)
# git clone git@bitbucket.org:algumaorg/algumrepo.git
...
# exit
oak > _
```

`exit` te devolve pro Oak. Isso não é um modo de emergência: é o jeito
certo de fazer qualquer coisa que você prefere digitar do que descrever.

## Mais de um Claude ao mesmo tempo

Pela IDE (abaixo), cada painel de terminal do code-server já é
independente. Um `claude` por painel, sem configurar nada.

No console cru, use `sessoes`. Isso abre o [Herdr](https://herdr.dev/),
que mantém cada sessão de agente rodando em background mesmo se você
fechar o terminal ou a conexão cair. Na próxima vez que digitar `sessoes`,
reanexa do jeito que ficou, com o `claude` ainda de pé.

Pra sair sem encerrar: `prefix+q`, ou fechar o terminal.

## A IDE

Code-server (VS Code no navegador) sobe sozinho em `:8080`, com a
extensão oficial do Claude Code. Abra `http://localhost:8080` no
navegador do seu computador.

A senha é gerada pelo próprio code-server no primeiro boot e fica
guardada dentro da VM. Pra descobrir qual é, rode `status` no console:

```
oak > status

  rede      ok
  claude    ok
  conta     ok
  ide       ok  http://localhost:8080
              senha: <sua senha aqui>
  tela      nao
              digite 'tela' pra ligar
```

## Tela virtual: rodar algo com janela de verdade

Não há desktop na VM, mas alguma coisa às vezes precisa mesmo de uma
janela: um app Electron, o Chromium sem `--headless` pra ver o que ele está
renderizando. Pra isso existe `tela`:

```
oak > tela
  Tela ligada.
  http://localhost:6080/vnc.html
  senha: <gerada na primeira vez>
```

Abra a URL no navegador do seu computador (a porta `6080` é encaminhada
pelo QEMU, igual a IDE) e entre com a senha. Você cai direto no Chromium,
já aberto e maximizado -- navegue pra onde quiser, inclusive num projeto
seu rodando na própria VM (`localhost:3000`, por exemplo).

Fica desligada por padrão pra não gastar RAM à toa. A senha é gerada na
primeira vez que você liga, fica guardada no disco de dados (sobrevive a
reinícios e rebuilds), e `status` sempre mostra qual é enquanto a tela
estiver ligada.

## Acesso por SSH

```bash
ssh -p 2222 root@localhost
```

`run.sh` encaminha a porta `2222` do host pra `22` da VM. O SSH já sobe
sozinho no boot, mas só aceita chave pública -- o root não tem senha, então
sem uma chave configurada, ninguém entra. Pra configurar a sua, dentro da
VM (via console ou `shell`):

```bash
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAA... voce@sua-maquina" >> /root/.ssh/authorized_keys
```

`/root/.ssh` não está no disco de dados persistente: some a cada `make`
(rebuild do sistema) e precisa ser adicionada de novo. Útil como
alternativa ao console serial quando o QEMU não está aberto na sua frente
(ex: outro terminal, outra máquina na mesma rede).

## O que sobrevive e o que não

A VM roda em dois discos separados:

- **O sistema** (`build/oakos.ext4`): recriado do zero a cada `make`.
  Nada que você mudar fora das pastas abaixo sobrevive a um rebuild.
- **Os dados** (`build/oakos-data.ext4`): nunca é apagado por
  `make`/`make clean`. Guarda quatro coisas, montadas por bind:
  - `/root/workspace`: a pasta que a IDE abre por padrão
  - `/root/.claude`: sua conta Claude logada
  - `/root/.config/code-server`: a senha da IDE
  - `/root/.config/x11vnc`: a senha da tela virtual
  - (`/root/.ssh` **não** está nessa lista -- ver "Acesso por SSH" acima)

Precisa que alguma coisa sobreviva sempre? Coloque em
`image/chroot-setup.sh`, não instale na mão dentro da VM.

## Vários projetos ao mesmo tempo

`run.sh` encaminha a porta `8080` (IDE) mais um bloco dos padrões mais
comuns de dev server: `3000-3002`, `5173-5174`, `8000-8001`, `5000`.
Dá pra rodar uns três projetos simultâneos e abrir cada um no navegador
sem editar nada. Precisa de mais alguma porta?

```bash
OAK_PORTS="4000 9000" ./run.sh
```

Docker e `docker compose` já vêm prontos, do repositório oficial da
Docker Inc. Dentro da VM, os projetos se enxergam livremente entre si por
`localhost` (ou por nome de serviço, no mesmo `docker compose`),
independente de qualquer encaminhamento de porta.

## Levar o OakOS pra outro lugar

O boot padrão (`make run`) é rápido pra iterar, mas só funciona dentro do
QEMU: o kernel é carregado por fora, direto pela linha de comando
(`-kernel`/`-initrd`), sem bootloader nenhum.

Pra rodar em hardware de verdade, pendrive ou VPS, é outra imagem:

```bash
make bootable       # monta o disco GPT (ESP + systemd-boot)
make run-bootable    # testa via firmware UEFI real (OVMF), sem atalho
```

O resultado, `build/oakos-bootable.img`, é um disco raw comum. Pra gravar
num pendrive: `dd if=build/oakos-bootable.img of=/dev/sdX`. Pra outro
hypervisor (Hyper-V, VirtualBox), converta o formato primeiro:

```bash
qemu-img convert -f raw -O vhdx build/oakos-bootable.img oakos.vhdx
```

Antes de expor essa imagem numa rede de verdade (IP público, VPS),
lembre que o root não tem senha e o autologin está ligado de propósito,
pensado pra uma VM de dev local. Isso precisa mudar primeiro.

## Resolução de problemas

**O Oak travou ou não entra no console certo.** Bota a VM de novo com
`OAK_NO_SHELL=1`, que pula o `oak` e cai direto no zsh:

```bash
OAK_CMDLINE="OAK_NO_SHELL=1" ./run.sh
```

**`sessoes` não está funcionando.** Confira `status`: se `claude` estiver
marcado `nao`, o Herdr ainda funciona, só não tem a integração de detectar
se o agente está parado, trabalhando ou bloqueado. Isso se resolve
sozinho na primeira vez que você usa o `claude` de verdade.

**Perdi a senha da IDE.** `status` mostra de novo, sempre que a IDE
estiver rodando. Ela não muda entre boots, só se o disco de dados for
apagado.
