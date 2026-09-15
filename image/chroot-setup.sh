#!/bin/bash
# Roda DENTRO do rootfs em construcao, com rede do host disponivel.
# E aqui que o Debian generico vira OakOS.
set -euo pipefail

# O apt, por padrao, roda suas operacoes de rede como o usuario '_apt', sem
# privilegios -- uma boa pratica de seguranca. O problema e o user
# namespace do mmdebstrap: '_apt' nao tem um mapeamento de verdade ali, e
# depois que o apt (dentro do 'docker-setup' abaixo) chowna arquivos pra
# ele, mais ninguem consegue tomar posse de volta -- nem a propria limpeza
# final que o mmdebstrap faz sozinho, que morre com "Operation not
# permitted" tentando mexer em /var/lib/apt/lists. Desligamos o sandbox:
# tudo roda como root mesmo, o que e razoavel aqui -- ja somos root
# (fake ou nao) o chroot inteiro.
echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99oakos-no-sandbox

echo ">> configurando identidade do OakOS"

# Autologin no console serial e no tty1. Num SO onde o agente e a interface,
# um prompt "login:" nao faz sentido -- voce entra direto na conversa.
for unit in serial-getty@ttyS0 getty@tty1; do
    mkdir -p "/etc/systemd/system/${unit}.service.d"
    cat > "/etc/systemd/system/${unit}.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF
done

# Servicos que queremos ligados no boot.
systemctl enable systemd-networkd systemd-resolved systemd-timesyncd

# ssh liga sempre (e so por chave -- ver overlay/etc/ssh/sshd_config.d/
# oakos.conf). xvfb/x11vnc/novnc (tela grafica sob demanda) ficam de fora
# de proposito -- 'systemctl enable' delas nao roda em lugar nenhum deste
# script, so o comando 'tela' do oak da 'systemctl start' na hora que
# alguem precisar.
systemctl enable ssh

# Sem senha de root: e uma VM de desenvolvimento local, e pedir senha
# atrapalha o ciclo. ISSO PRECISA MUDAR antes de qualquer uso real.
passwd -d root

# zsh como shell de login do root. O overlay ja trouxe .zprofile (que chama
# o Oak) e .bash_profile (mantido para quando 'shell' cai em bash mesmo).
chsh -s "$(command -v zsh)" root

echo ">> instalando o Node.js (LTS atual -- o do Debian trava numa versao velha)"
# Tarball oficial de nodejs.org, verificado por sha256, extraido direto em
# /usr/local (--strip-components=1 tira a pasta versionada do meio: o
# tarball vira bin/, lib/, include/ direto onde precisam estar). Sem isso
# quebra TUDO que vem depois -- claude-code, code-server, playwright --
# entao, ao contrario dos outros passos, aqui um erro aborta o build
# (nao tem "|| true": nao tem OakOS sem Node de verdade).
NODE_VERSION="v24.21.0"
# .tar.gz, nao .tar.xz: o chroot minimo nao tem 'xz' instalado, e o tar ja
# sabe abrir gzip por conta propria (zlib embutido) -- um binario a menos
# pra instalar so pra descompactar isto uma vez.
NODE_TARBALL="node-${NODE_VERSION}-linux-x64.tar.gz"
curl -fsSLO "https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}"
curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" \
    | grep " ${NODE_TARBALL}$" | sha256sum -c -
tar -xzf "$NODE_TARBALL" -C /usr/local --strip-components=1
rm -f "$NODE_TARBALL"
node --version
npm --version

echo ">> instalando o Claude Code"
# --unsafe-perm porque estamos como root num chroot sem usuario real.
npm install -g --unsafe-perm @anthropic-ai/claude-code || {
    echo "!! falhou instalar o Claude Code (sem rede no chroot?)"
    echo "!! da pra instalar depois, dentro da VM, com: npm i -g @anthropic-ai/claude-code"
}

echo ">> instalando o Herdr"
# Runtime de sessoes de agente (https://herdr.dev): mantem o 'claude' vivo
# em background, sobrevivendo a desconexao, com deteccao de estado
# (idle/working/blocked). E quem sustenta o comando 'sessoes' do oak --
# substituiu o tmux (avaliado e comparado lado a lado antes da troca).
#
# Binario estatico, sem servico systemd -- o proprio 'herdr' sobe o daemon
# na primeira chamada. HERDR_INSTALL_DIR=/usr/local/bin em vez do
# $HOME/.local/bin padrao do instalador: aqui dentro root nao tem uma
# sessao de login "normal" que garanta esse PATH, e /usr/local/bin ja e
# onde o code-server e o docker-compose shim vivem.
HERDR_INSTALL_DIR=/usr/local/bin bash -c 'curl -fsSL https://herdr.dev/install.sh | sh' || {
    echo "!! falhou instalar o Herdr (sem rede no chroot?)"
}

# 'herdr integration install claude' NAO roda aqui de proposito: ele exige
# que ~/.claude ja exista, e esse diretorio so aparece depois que o
# 'claude' roda pela primeira vez -- o que nunca acontece durante o build
# da imagem (sem TTY, sem login). Rodar aqui falharia sempre. Quem instala
# a integracao, de fato, e o comando 'sessoes' do oak, na primeira vez que
# achar ~/.claude presente dentro da VM (achado rodando o build de
# verdade, nao suposto: a tentativa aqui falhava com "claude directory
# not found").

echo ">> instalando o code-server (IDE)"
# --method=standalone: baixa o binario pronto do GitHub e nao chama systemctl
# em lugar nenhum -- funciona dentro de um chroot sem PID 1 de verdade, que e
# exatamente onde estamos agora. --prefix=/usr/local poe o binario direto no
# PATH do sistema, em vez de enterrado num ~/.local que ninguem vai olhar.
curl -fsSL https://code-server.dev/install.sh | sh -s -- \
    --method=standalone --prefix=/usr/local || {
    echo "!! falhou instalar o code-server (sem rede no chroot?)"
}

# /root/workspace, /root/.claude e /root/.config/code-server precisam
# existir como diretorios reais na imagem, mesmo vazios: sao os PONTOS DE
# MONTAGEM dos binds pro disco de dados persistente (ver overlay/etc/fstab
# e image/build-data.sh). Sem essa pasta aqui, o bind mount de boot nao tem
# onde grudar. Incondicional -- nao depende do code-server ter instalado
# certo.
mkdir -p /root/workspace /root/.claude /root/.config/code-server /root/.config/x11vnc
cat > /root/workspace/README.md <<'MSG'
# workspace

Pasta padrao aberta pelo code-server. Normalmente isto e so um fallback:
o disco de dados persistente (ver 'Estrutura' no README do projeto) fica
montado por cima, e o que voce ve aqui de verdade sobrevive a rebuilds da
imagem -- nao so a reinicios.
MSG

if command -v code-server >/dev/null; then
    # A extensao oficial do Claude Code, publicada pela propria Anthropic no
    # Open VSX (o registro que o code-server usa -- nao e a marketplace da
    # Microsoft). Mostra diffs inline e integra o agente ao editor.
    code-server --install-extension anthropic.claude-code || {
        echo "!! nao deu pra instalar a extensao do Claude Code agora"
        echo "!! tente depois, dentro da VM: code-server --install-extension anthropic.claude-code"
    }

    systemctl enable code-server
else
    echo "!! code-server ausente -- pulando extensao e servico"
fi

echo ">> instalando o Playwright"
# O Chromium ja veio do apt (pacote 'chromium' acima) -- entao pulamos o
# download do binario proprio do Playwright (PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD),
# que seria um segundo Chromium identico so que mais pesado. O agente aponta
# executablePath para /usr/bin/chromium na hora de abrir o navegador.
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install -g playwright || {
    echo "!! falhou instalar o playwright (sem rede no chroot?)"
}
# O apt ja resolveu as bibliotecas que o proprio pacote chromium precisa pra
# rodar headless. Se faltar algo mais especifico do Playwright, da pra
# resolver depois, dentro da VM, com: npx playwright install-deps

echo ">> instalando o Docker"
# O Debian empacota o Docker como 'docker.io', geralmente atrasado. Usamos o
# repositorio oficial da Docker Inc. pra ter o motor atual e o plugin
# 'docker compose' (v2) -- o mesmo processo de sempre: chave, fonte, update.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# NAO le /etc/os-release pra pegar o codinome: a essa altura ele ja e o
# nosso, sobrescrito pelo overlay (identidade do OakOS), sem
# VERSION_CODENAME nenhum. O codinome real do Debian de base vem por env,
# passado pelo build-rootfs.sh (que ja sabe qual suite pediu ao mmdebstrap).
: "${OAK_SUITE:?defina OAK_SUITE (veja build-rootfs.sh)}"
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${OAK_SUITE} stable
EOF

apt-get update
# iptables entra explicito: o mmdebstrap roda em modo minimo (sem
# Recommends), e o bridge padrao do Docker (NAT pros containers alcancarem
# a rede) depende dele.
apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    iptables || {
    echo "!! falhou instalar o docker (sem rede no chroot?)"
}

# Atalho de compatibilidade: muito tutorial/script por ai ainda chama
# 'docker-compose' com hifen (o binario standalone, hoje descontinuado).
# O pacote novo so registra 'docker compose', com espaco -- este atalho
# cobre os dois sem voce precisar lembrar qual e o certo.
if command -v docker >/dev/null; then
    cat > /usr/local/bin/docker-compose <<'SHIM'
#!/bin/sh
exec docker compose "$@"
SHIM
    chmod +x /usr/local/bin/docker-compose
    systemctl enable docker
else
    echo "!! docker ausente -- pulando servico e atalho do compose"
fi

echo ">> instalando TypeScript"
# tsc global pra qualquer projeto, mais tsx pra rodar .ts direto sem
# compilar antes (util pra scripts rapidos e depuracao). React, antd, e
# tudo mais especifico de projeto ficam de fora de proposito -- essas sao
# devDependencies de cada repositorio, nao coisa pra instalar no sistema.
npm install -g typescript tsx || {
    echo "!! falhou instalar typescript/tsx (sem rede no chroot?)"
}

echo ">> instalando o acli (CLI oficial da Atlassian, Jira)"
# So cobre Jira -- a Atlassian nao tem CLI oficial pra Bitbucket. Repos
# la ficam por git puro (chave SSH ou app password, configurados uma vez
# com 'login' ou na mao). Binario estatico, sem apt nem chave nenhuma.
curl -fsSL -o /usr/local/bin/acli \
    https://acli.atlassian.com/linux/latest/acli_linux_amd64/acli && \
    chmod +x /usr/local/bin/acli || {
    echo "!! falhou instalar o acli (sem rede no chroot?)"
}

# Limpeza de cache que NAO e do apt: so npm. NUNCA "rm -rf /tmp/*" aqui --
# o mmdebstrap deixa um arquivo de config dele mesmo dentro do /tmp deste
# rootfs (algo como /tmp/mmdebstrap.apt.conf.XXXXXX), que ele precisa DEPOIS
# que todo customize-hook termina, pra fazer a propria limpeza automatica
# do apt (lists/cache). Um "rm -rf /tmp/*" nosso apaga esse arquivo, a
# limpeza dele quebra tentando reabrir algo que nao existe mais, e o build
# inteiro morre no ultimo passo -- sem nada de errado com a imagem em si.
# Foi descoberto assim, doeu, e o aviso fica registrado por isso.
rm -rf /root/.npm /root/.cache || true

echo ">> chroot pronto"
