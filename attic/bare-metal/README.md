# attic/bare-metal

Kernel x86_64 escrito do zero (bootloader Limine, console de framebuffer com
fonte PSF embutida, driver de serial). Foi o começo do OakOS, antes de ficar
claro que o objetivo real exigia rodar Node.js e TLS -- coisa que um kernel
do zero levaria anos pra sustentar. Parado, mas honesto sobre o que um
kernel realmente faz. Ver a seção "Decisões tomadas" do README principal.

## `limine/`

Não versionado (é binário de terceiros, com `.git` próprio). Pra recriar:

```bash
cd attic/bare-metal
git clone https://github.com/limine-bootloader/limine.git --branch=v9.x-binary --depth=1 limine
```
