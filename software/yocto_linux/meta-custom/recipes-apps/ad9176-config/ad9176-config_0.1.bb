# ad9176-config_0.1.bb -- Linux user-space tool for the Phase B Agilex 5
# / AD9176-FMC-EBZ stack. Packages the binary into the dev-kit image.
#
# Source layout: this recipe pulls the C sources from the in-tree
# software/ad9176_config/ directory. The recipe is invoked from the
# Yocto build host (not from Quartus). See ../../README in the meta-custom
# layer root for layer-add instructions.

SUMMARY = "AD9176-FMC-EBZ Linux configuration tool (Phase B dev kit)"
DESCRIPTION = "User-space tool to bring up the AD9176 over the fabric SPI \
master and configure the FPGA SineWaveGen + JESD204B link release. \
Uses /dev/mem mmap of the lwhps2fpga window at 0x02000000."
HOMEPAGE = "https://github.com/<your-org>/Firmware_DevBoard_PhaseA"
LICENSE = "MIT"
LIC_FILES_CHKSUM = ""

SRC_URI = " \
    file://ad9176_config.c \
    file://ad9176_fmc_ebz.c \
    file://ad9176_fmc_ebz.h \
    file://ad9176_init.c \
    file://ad9176_init.h \
    file://dac_subsys_regs.h \
    file://Makefile \
"

S = "${WORKDIR}"

# Use the in-tree Makefile; no autotools.
do_compile() {
    oe_runmake CROSS=${TARGET_PREFIX}
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ad9176-config ${D}${bindir}/ad9176-config
}

FILES:${PN} = "${bindir}/ad9176-config"

# Image inclusion: append IMAGE_INSTALL += "ad9176-config" in the dev-kit
# image recipe (or set EXTRA_IMAGE_FEATURES_append = " ad9176-config").
