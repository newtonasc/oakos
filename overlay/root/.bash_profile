# Entrou no console? O Oak assume.
# Defina OAK_NO_SHELL=1 para cair direto no bash (util pra depurar).
if [ -z "${OAK_NO_SHELL:-}" ] && [ -t 0 ]; then
    /usr/local/bin/oak
fi
