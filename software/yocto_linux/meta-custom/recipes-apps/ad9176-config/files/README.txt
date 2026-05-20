files/ -- staging area for the ad9176-config recipe

Yocto's SRC_URI = "file://*" looks here for the C sources at recipe-fetch
time. On the build host (Linux), populate this directory either by:

  1. Symlink (recommended for active development):
       cd files/
       ln -s ../../../../../ad9176_config/{ad9176_config.c,ad9176_fmc_ebz.c,ad9176_fmc_ebz.h,ad9176_init.c,ad9176_init.h,dac_subsys_regs.h,Makefile} .

  2. Copy (recommended for snapshot builds):
       cp ../../../../ad9176_config/{ad9176_config.c,ad9176_fmc_ebz.c,ad9176_fmc_ebz.h,ad9176_init.c,ad9176_init.h,dac_subsys_regs.h,Makefile} files/

Neither symlinks nor copies are checked into git from this directory --
the source of truth lives in software/ad9176_config/. This README
file is intentionally tracked so the directory exists in the repo.

To trigger the build (after sync):
    cd ../../..              # back up to software/yocto_linux/
    bitbake ad9176-config

To pull the binary into the dev-kit image, append the following to the
image recipe (e.g. core-image-minimal.bbappend):
    IMAGE_INSTALL:append = " ad9176-config"
