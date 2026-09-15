# Entrou no console? O Oak assume.
# Defina OAK_NO_SHELL=1 para cair direto no bash (util pra depurar).
if [ -z "${OAK_NO_SHELL:-}" ] && [ -t 0 ]; then
    # exec, nao so chamar: sem isso, quando o oak termina, o controle volta
    # pro .bash_profile e sobra um bash de login solto (achado testando --
    # zsh (.zprofile) ja fazia isso certo, este arquivo tinha ficado pra tras).
    exec /usr/local/bin/oak
fi
