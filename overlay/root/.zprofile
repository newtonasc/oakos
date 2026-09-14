# Entrou no console? O Oak assume.
# Defina OAK_NO_SHELL=1 para cair direto no shell (util pra depurar).
if [ -z "${OAK_NO_SHELL:-}" ] && [ -t 0 ]; then
    exec /usr/local/bin/oak
fi
