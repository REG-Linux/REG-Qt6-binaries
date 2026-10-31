#!/bin/sh

# Build the prebuilt QT6 tarballs uploaded to
# github.com/REG-Linux/REG-Qt6-binaries/releases/$(QT6_VERSION).
#
# Usage:   ./scripts/linux/prebuild/prebuild-qt6.sh [cpu...]
# Example: ./scripts/linux/prebuild/prebuild-qt6.sh cortex_a76_a55 x86_64_v3
#          With no argument every CPU in the table below is built.
#
# Output:  prebuilt/reglinux-qt6-${QT6_VERSION}-${cpu}.tar.xz
#
# Run from the project root.

set -e

# Grab the QT6 version from the source tree. This is the version the tarball is
# named after, exactly as build-QT6.yml derives it, so both producers agree.
QT6_MAJOR="$(awk -F'= ' '/^QT6_VERSION_MAJOR /{print $2; exit}' \
	custom/package/qt6/qt6.mk)"
QT6_VERSION_TPL="$(awk -F'= ' '/^QT6_VERSION /{print $2; exit}' \
	custom/package/qt6/qt6.mk)"
QT6_VERSION="$(echo "$QT6_VERSION_TPL" | sed "s|\$(QT6_VERSION_MAJOR)|$QT6_MAJOR|g")"

if [ -z "$QT6_VERSION" ]; then
	echo "Could not determine QT6 version, aborting"
	exit 1
fi

# The consumer fetches by REGLINUX_QT6_VERSION, which is bumped separately from
# buildroot's qt6.mk. If the two drift, these tarballs land under a tag nothing
# downloads.
CONSUMER_VERSION="$(awk -F'= ' '/^REGLINUX_QT6_VERSION /{print $2; exit}' \
	package/libraries/reglinux-qt6/reglinux-qt6.mk)"
if [ "${CONSUMER_VERSION}" != "${QT6_VERSION}" ]; then
	echo "WARNING: buildroot qt6 is ${QT6_VERSION} but reglinux-qt6.mk fetches"
	echo "         ${CONSUMER_VERSION}. Bump REGLINUX_QT6_VERSION once these are published."
fi

echo "Building QT6 ${QT6_VERSION} prebuilts"

# Create prebuilt output directory
mkdir -p prebuilt

# Enable BUILD_FROM_SOURCE in the shared defconfig fragment, otherwise each
# per-arch build just downloads the very tarball we are trying to produce.
sed -i 's|^#\?BR2_PACKAGE_REGLINUX_QT6=y|BR2_PACKAGE_REGLINUX_QT6=y|' \
	configs/reglinux-board.common
sed -i 's|^#\?BR2_PACKAGE_REGLINUX_QT6_BUILD_FROM_SOURCE=y|BR2_PACKAGE_REGLINUX_QT6_BUILD_FROM_SOURCE=y|' \
	configs/reglinux-board.common
sed -i 's|^#\?BR2_PACKAGE_QT6BASE_DEFAULT_QPA="wayland"|BR2_PACKAGE_QT6BASE_DEFAULT_QPA="wayland"|' \
	configs/reglinux-board.common

PROJECT_DIR="$(pwd)"

# Write one tarball from buildroot's own per-package manifests.
#
# Buildroot records exactly what each package installed in
#   build/<pkg>-<ver>/.files-list-host.txt     (paths relative to HOST_DIR)
#   build/<pkg>-<ver>/.files-list-staging.txt  (paths relative to STAGING_DIR)
#   build/<pkg>-<ver>/.files-list.txt          (paths relative to TARGET_DIR)
# as "<pkgname>,./path" lines, the same manifests prebuild-mames.sh uses.
#
# Package strictly from those. A build or output tree is NOT the set of files a
# package installed - with per-package directories buildroot pre-populates each
# one by rsyncing in every dependency - so sweeping it with a name heuristic
# like `find . | grep -i Qt` ships other packages' files. Those carry RUNPATHs
# pointing into this build tree, and buildroot's check-host-rpath then rejects
# them in whoever consumes the tarball.
#
# $1 = tarball to write, $2 = scratch list file, $3.. = build dirs owning files
make_tarball() {
	tarball="$1"; shift
	listname="$1"; shift

	: >"${listname}"

	for d in "$@"; do
		[ -d "${d}" ] || continue

		# The manifests' first field is the buildroot package name, which is
		# also its per-package directory name.
		pkg=""
		for m in .files-list-host.txt .files-list-staging.txt .files-list.txt; do
			if [ -f "${d}/${m}" ]; then
				pkg="$(cut -d ',' -f 1 "${d}/${m}" | head -1)"
				if [ -n "${pkg}" ]; then
					break
				fi
			fi
		done
		[ -n "${pkg}" ] || continue

		if [ -d per-package ]; then
			hostpfx="per-package/${pkg}/host"
			tgtpfx="per-package/${pkg}/target"
		else
			hostpfx="host"
			tgtpfx="target"
		fi

		# STAGING_DIR lives under HOST_DIR as <tuple>/sysroot
		sysroot="$(cd "${hostpfx}" 2>/dev/null && ls -d ./*/sysroot 2>/dev/null | sed 's|^\./||' | head -1 || true)"

		if [ -f "${d}/.files-list-host.txt" ]; then
			cut -d ',' -f 2- "${d}/.files-list-host.txt" \
				| sed -e "s+^\./+${hostpfx}/+" >>"${listname}"
		fi
		if [ -f "${d}/.files-list-staging.txt" ] && [ -n "${sysroot}" ]; then
			cut -d ',' -f 2- "${d}/.files-list-staging.txt" \
				| sed -e "s+^\./+${hostpfx}/${sysroot}/+" >>"${listname}"
		fi
		if [ -f "${d}/.files-list.txt" ]; then
			cut -d ',' -f 2- "${d}/.files-list.txt" \
				| sed -e "s+^\./+${tgtpfx}/+" >>"${listname}"
		fi
	done

	# An empty list means the qt6 packages were never built here, i.e. this tree
	# consumed the prebuilt tarball instead of producing one. Publishing that
	# would be worse than failing.
	if [ ! -s "${listname}" ]; then
		echo "ERROR: no qt6 manifests under $(pwd), so this tree was built against"
		echo "       the prebuilt QT6 rather than from source. Check"
		echo "       BR2_PACKAGE_REGLINUX_QT6_BUILD_FROM_SOURCE=y in configs/reglinux-board.common."
		exit 1
	fi

	# LC_ALL=C: under a UTF-8 locale sort ignores punctuation at the primary
	# collation level, so two real files whose names differ only by punctuation
	# compare equal and -u silently drops one. Found in prebuild-llvm.sh, where
	# "LLVM-Config.cmake" swallowed "LLVMConfig.cmake" and every dependent doing
	# find_package(LLVM) then failed; the same line was here.
	LC_ALL=C sort -u -o "${listname}" "${listname}"

	echo "    $(wc -l <"${listname}") files -> $(basename "${tarball}")"

	# With per-package directories the members are prefixed by
	# per-package/<pkg>/; strip that so the archive is always host/... plus
	# target/..., which is the layout REGLINUX_QT6_INSTALL_TARGET_CMDS expects
	# when it untars into $(HOST_DIR)/../
	XZ_OPT=-9 tar -cJf "${tarball}" \
		--transform='s|^per-package/[^/]*/||' \
		--verbatim-files-from -T "${listname}"
}

# One build per CPU, not per board: reglinux-qt6.mk picks the prebuilt by CPU
# (REGLINUX_QT6_CPU), so the target named here is just a representative board
# for that CPU and every other board sharing it takes the same tarball. Keep
# this list in step with the matrix in
# REG-Qt6-binaries/.github/workflows/build-QT6.yml.
#
# Picking a representative board is not arbitrary: the tarball inherits that
# board's ISA, toolchain and XORG7 state, and every board sharing the CPU label
# has to be able to load and execute the result. In priority order:
#
#   ISA dominates. An optional extension compiled in is an unconditional SIGILL
#   on a board without it. On RISC-V, k1 and k3 set BR2_RISCV_ISA_RVV
#   (-march=rv64imafdcv...) while jh7110 (sifive-u74) and th1520 (xt-c910) do
#   not, so a k1/k3-built tarball cannot run on jh7110/th1520. The reverse is
#   fine: base rv64gc code runs everywhere.
#
#   Toolchain next. Qt carries versioned GLIBCXX_3.4.xx requirements and
#   libstdc++ is only backward compatible, so build with the OLDEST GCC in the
#   group (riscv: jh7110/k3 are gcc15, k1/th1520 gcc16).
#
#   XORG7 last (from BR2_PACKAGE_REGLINUX_XWAYLAND, per board, not from
#   reglinux-board.common). With it on, libQt6Gui.so itself links libX11 - not
#   just libqxcb.so - so a board without libX11 cannot start ANY Qt app. Fatal,
#   not a skipped plugin. With it off the X boards merely lose the XCB platform
#   plugin and keep working under Wayland.
#
# riscv is the one group where no single board wins all three: the non-RVV
# boards (jh7110, th1520) both have XWAYLAND, and the boards without it (k1,
# k3) are RVV. ISA outranks the rest, so jh7110 stays - do NOT swap it for k3.
# The real fix, if a riscv board ever pulls reglinux-qt6, is to split the label
# the way reglinux-scummvm already does (riscv = jh7110/th1520, riscv_rvv =
# k1/k3), not to change the representative. Today nothing forces it: 7 of the 8
# consumers of reglinux-qt6 are gated to explicit x86_64/aarch64 SoC targets and
# the 8th (snes9x) needs BR2_PACKAGE_HAS_LIBGL, which those boards' GLES-only
# Imagination stack does not provide - verify that before relying on it.
#
# cortex_a55 IS split, for the reason above: odroidc5 has XORG7 and builds
# pcsx2, which needs QtGui/private/qtx11extras_p.h, while rk3568/s905gen3/t527
# have no libX11. cortex_a35 is mixed too (rk3326 no X, s9gen4 X) but stays on
# one label - nothing on s9gen4 needs the XCB plugin, so the rk3326 build serves
# both.
#
#   XORG7 (from BR2_PACKAGE_REGLINUX_XWAYLAND, per board, not from
#   reglinux-board.common) decides whether qt6base builds with FEATURE_xcb.
#   With it on, libQt6Gui.so itself links libX11 - not just libqxcb.so - so a
#   board without libX11 cannot start ANY Qt app. This is fatal, not a skipped
#   plugin. With it off the X boards merely lose the XCB platform plugin and
#   keep working under Wayland.
#
#   The toolchain cuts the other way: Qt carries versioned GLIBCXX_3.4.xx
#   requirements, and libstdc++ is only backward compatible, so a tarball built
#   with a newer GCC will not load on a board pinned to an older one.
#
# So the representative must be the LOWEST common denominator of its CPU group:
# oldest toolchain, and XORG7 off. riscv is the one mixed group - jh7110
# (gcc15, X) k3 (gcc15, no X) k1 (gcc16, no X) th1520 (gcc16, X) - where k3 is
# the correct pick and jh7110, the current one, is not. Left alone because no
# riscv board appears to pull reglinux-qt6 at all: 7 of its 8 consumers are
# gated to explicit x86_64/aarch64 SoC targets and the 8th (snes9x) needs
# BR2_PACKAGE_HAS_LIBGL, which those boards' GLES-only Imagination stack does
# not provide. Verify that before relying on it. cortex_a55 is mixed in XORG7
# and split into two labels instead; cortex_a35 is mixed too but stays on one.
#
# The 32-bit CPUs reglinux-qt6.mk also maps (arm1176jzf_s, cortex_a7, cortex_a9,
# cortex_a15_a7, jz4770) are absent on purpose: every package that selects
# BR2_PACKAGE_REGLINUX_QT6 is gated on BR2_ARCH_IS_64 / BR2_aarch64 / x86_64 in
# Config.in.emulators, so those boards never look for a tarball.
while read -r cpu target
do
	[ -n "${cpu}" ] || continue

	# Optional CPU filter from the command line
	if [ -n "$1" ]; then
		wanted=n
		for want in "$@"; do
			if [ "${want}" = "${cpu}" ]; then
				wanted=y
			fi
		done
		if [ "${wanted}" != y ]; then
			continue
		fi
	fi

	echo "==> Building QT6 for ${cpu} (via ${target})"

	# Clean
	make "${target}-clean"
	# Build
	PKG=reglinux-qt6 make "${target}-pkg" DEBUG_BUILD=n CCACHE_DISABLE=1
	# Package. Subshell: the tar runs from the output directory, but the next
	# iteration has to start back at the top of the tree.
	(
		cd "output/${target}" || exit 1
		# reglinux-qt6/Config.in now selects BR2_PACKAGE_QT6MULTIMEDIA_FFMPEG, so
		# qt6multimedia also ships plugins/multimedia/libffmpegmediaplugin.so. Without
		# a backend it built libQt6Multimedia.so and no plugins at all, and every
		# QMediaPlayer failed with "No QtMultimedia backends found" - the harvest was
		# never at fault, there was simply nothing to harvest.
		#
		# That plugin links the board's ffmpeg and pulseaudio (libavcodec.so.61,
		# libpulse.so.0 today). Neither belongs in this tarball - the board supplies
		# both - but it does couple the tarball to REG-WIP's ffmpeg SONAME: bump ffmpeg
		# to a new major and the plugin silently stops loading on every board still
		# using an old tarball. Re-cut these tarballs when ffmpeg's major changes.
		#
		# qt6* / host-qt6* cover every qt6 sub-package (qt6base,
		# qt6declarative, qt6multimedia, qt6shadertools, qt6svg, qt6tools,
		# qt6wayland, qt6websockets and their host counterparts). The
		# reglinux-qt6 wrapper installs nothing of its own, so it is not
		# listed here.
		#
		# The glob is exact only because of the clean above plus the
		# PKG=reglinux-qt6 build: build/ then holds precisely
		# REGLINUX_QT6_DEPENDENCIES' closure, and reglinux-qt6/Config.in selects
		# exactly those same eight modules - it used to also select qt6charts,
		# which nothing depended on and no tarball ever shipped. Run this against
		# a tree that already did a full board build and the glob would still
		# sweep in whatever other qt6 modules that tree enabled.
		make_tarball "${PROJECT_DIR}/prebuilt/reglinux-qt6-${QT6_VERSION}-${cpu}.tar.xz" \
			qt6-filelist.txt build/qt6* build/host-qt6*
	) || exit 1
	# Clean again
	make "${target}-clean"
done <<EOF
cortex_a17 rk3288
cortex_a35 rk3326
cortex_a53 h616
cortex_a55 rk3568
cortex_a55_x11 odroidc5
cortex_a72 bcm2711
cortex_a72_a53 rk3399
cortex_a73_a53 s922x
cortex_a75_a55 sdm845
cortex_a76 bcm2712
cortex_a76_a55 sm8250
riscv jh7110
saphira asahi
x86_64 x86_64
x86_64_v3 x86_64_v3
EOF

# Disable the flags to build QT6 from source
sed -i 's|^BR2_PACKAGE_REGLINUX_QT6=y|#BR2_PACKAGE_REGLINUX_QT6=y|' configs/reglinux-board.common
sed -i 's|^BR2_PACKAGE_REGLINUX_QT6_BUILD_FROM_SOURCE=y|#BR2_PACKAGE_REGLINUX_QT6_BUILD_FROM_SOURCE=y|' configs/reglinux-board.common
sed -i 's|^BR2_PACKAGE_QT6BASE_DEFAULT_QPA="wayland"|#BR2_PACKAGE_QT6BASE_DEFAULT_QPA="wayland"|' configs/reglinux-board.common

echo
echo "Tarballs in ./prebuilt/. Upload to:"
echo "  https://github.com/REG-Linux/REG-Qt6-binaries/releases/tag/${QT6_VERSION}"
