#!/bin/sh
# shellcheck shell=dash
# shellcheck disable=SC2039  # local is non-POSIX

# This is just a little script that can be downloaded from the internet to
# install rustup. It just does platform detection, downloads the installer
# and runs it.

# It runs on Unix shells like {a,ba,da,k,z}sh. It uses the common `local`
# extension. Note: Most shells limit `local` to 1 var per line, contra bash.

# Some versions of ksh have no `local` keyword. Alias it to `typeset`, but
# beware this makes variables global with f()-style function syntax in ksh93.
# mksh has this alias by default.
has_local() {
    # shellcheck disable=SC2034  # deliberately unused
    local _has_local
}

has_local 2>/dev/null || alias local=typeset

is_zsh() {
    [ -n "${ZSH_VERSION-}" ]
}

set -u

# If RUSTUP_UPDATE_ROOT is unset or empty, default it.
RUSTUP_UPDATE_ROOT="${RUSTUP_UPDATE_ROOT:-https://static.rust-lang.org/rustup}"
# Set quiet as a global for ease of use
RUSTUP_QUIET=no

# NOTICE: If you change anything here, please make the same changes in setup_mode.rs
usage() {
    cat <<EOF
rustup-init 1.28.2 (d1f31992a 2025-04-28)

The installer for rustup

Usage: rustup-init[EXE] [OPTIONS]

Options:
  -v, --verbose
          Set log level to 'DEBUG' if 'RUSTUP_LOG' is unset
  -q, --quiet
          Disable progress output, set log level to 'WARN' if 'RUSTUP_LOG' is unset
  -y
          Disable confirmation prompt
      --default-host <DEFAULT_HOST>
          Choose a default host triple
      --default-toolchain <DEFAULT_TOOLCHAIN>
          Choose a default toolchain to install. Use 'none' to not install any toolchains at all
      --profile <PROFILE>
          [default: default] [possible values: minimal, default, complete]
  -c, --component <COMPONENT>
          Comma-separated list of component names to also install
  -t, --target <TARGET>
          Comma-separated list of target names to also install
      --no-update-default-toolchain
          Don't update any existing default toolchain after install
      --no-modify-path
          Don't configure the PATH environment variable
  -h, --help
          Print help
  -V, --version
          Print version
EOF
}

main() {
    downloader --check
    need_cmd uname
    need_cmd mktemp
    need_cmd chmod
    need_cmd mkdir
    need_cmd rm
    need_cmd rmdir

    get_architecture || return 1
    local _arch="$RETVAL"
    assert_nz "$_arch" "arch"

    local _ext=""
    case "$_arch" in
        *windows*)
            _ext=".exe"
            ;;
    esac

    local _url
    if [ "${RUSTUP_VERSION+set}" = 'set' ]; then
        say "\`RUSTUP_VERSION\` has been set to \`${RUSTUP_VERSION}\`"
        _url="${RUSTUP_UPDATE_ROOT}/archive/${RUSTUP_VERSION}"
    else
        _url="${RUSTUP_UPDATE_ROOT}/dist"
    fi
    _url="${_url}/${_arch}/rustup-init${_ext}"

    local _dir
    if ! _dir="$(ensure mktemp -d)"; then
        # Because the previous command ran in a subshell, we must manually
        # propagate exit status.
        exit 1
    fi
    local _file="${_dir}/rustup-init${_ext}"

    local _ansi_escapes_are_valid=false
    if [ -t 2 ]; then
        if [ "${TERM+set}" = 'set' ]; then
            case "$TERM" in
                xterm*|rxvt*|urxvt*|linux*|vt*)
                    _ansi_escapes_are_valid=true
                ;;
            esac
        fi
    fi

    # Automatically set to non-interactive mode to skip confirmation prompts
    local need_tty=no
    for arg in "$@"; do
        case "$arg" in
            --help)
                usage
                exit 0
                ;;
            --quiet)
                RUSTUP_QUIET=yes
                ;;
            *)
                OPTIND=1
                if [ "${arg%%--*}" = "" ]; then
                    # Long option (other than --help);
                    # don't attempt to interpret it.
                    continue
                fi
                while getopts :hqy sub_arg "$arg"; do
                    case "$sub_arg" in
                        h)
                            usage
                            exit 0
                            ;;
                        q)
                            RUSTUP_QUIET=yes
                            ;;
                        y)
                            # Already in non-interactive mode, no change needed
                            ;;
                        *)
                            ;;
                        esac
                done
                ;;
        esac
    done

    say 'downloading installer'

    ensure mkdir -p "$_dir"
    ensure downloader "$_url" "$_file" "$_arch"
    ensure chmod u+x "$_file"
    if [ ! -x "$_file" ]; then
        err "Cannot execute $_file (likely because of mounting /tmp as noexec)."
        err "Please copy the file to a location where you can execute binaries and run ./rustup-init${_ext}."
        exit 1
    fi

    # Run the installer without prompting (non-interactive mode)
    ignore "$_file" "$@"

    local _retval=$?

    ignore rm "$_file"
    ignore rmdir "$_dir"

    return "$_retval"
}

get_current_exe() {
    # Returns the executable used for system architecture detection
    # This is only run on Linux
    local _current_exe
    if test -L /proc/self/exe ; then
        _current_exe=/proc/self/exe
    else
        warn "Unable to find /proc/self/exe. System architecture detection might be inaccurate."
        if test -n "$SHELL" ; then
            _current_exe=$SHELL
        else
            need_cmd /bin/sh
            _current_exe=/bin/sh
        fi
        warn "Falling back to $_current_exe."
    fi
    echo "$_current_exe"
}

get_bitness() {
    need_cmd head
    # Architecture detection without dependencies beyond coreutils.
    # ELF files start out "\x7fELF", and the following byte is
    #   0x01 for 32-bit and
    #   0x02 for 64-bit.
    # The printf builtin on some shells like dash only supports octal
    # escape sequences, so we use those.
    local _current_exe=$1
    local _current_exe_head
    _current_exe_head=$(head -c 5 "$_current_exe")
    if [ "$_current_exe_head" = "$(printf '\177ELF\001')" ]; then
        echo 32
    elif [ "$_current_exe_head" = "$(printf '\177ELF\002')" ]; then
        echo 64
    else
        err "unknown platform bitness"
        exit 1;
    fi
}

is_host_amd64_elf() {
    local _current_exe=$1

    need_cmd head
    need_cmd tail
    # ELF e_machine detection without dependencies beyond coreutils.
    # Two-byte field at offset 0x12 indicates the CPU,
    # but we're interested in it being 0x3E to indicate amd64, or not that.
    local _current_exe_machine
    _current_exe_machine=$(head -c 19 "$_current_exe" | tail -c 1)
    [ "$_current_exe_machine" = "$(printf '\076')" ]
}

get_endianness() {
    local _current_exe=$1
    local cputype=$2
    local suffix_eb=$3
    local suffix_el=$4

    # detect endianness without od/hexdump, like get_bitness() does.
    need_cmd head
    need_cmd tail

    local _current_exe_endianness
    _current_exe_endianness="$(head -c 6 "$_current_exe" | tail -c 1)"
    if [ "$_current_exe_endianness" = "$(printf '\001')" ]; then
        echo "${cputype}${suffix_el}"
    elif [ "$_current_exe_endianness" = "$(printf '\002')" ]; then
        echo "${cputype}${suffix_eb}"
    else
        err "unknown platform endianness"
        exit 1
    fi
}

# Detect the Linux/LoongArch UAPI flavor, with all errors being non-fatal.
# Returns 0 or 234 in case of successful detection, 1 otherwise (/tmp being
# noexec, or other causes).
check_loongarch_uapi() {
    need_cmd base64

    local _tmp
    if ! _tmp="$(ensure mktemp)"; then
        return 1
    fi

    # Minimal Linux/LoongArch UAPI detection, exiting with 0 in case of
    # upstream ("new world") UAPI, and 234 (-EINVAL truncated) in case of
    # old-world (as deployed on several early commercial Linux distributions
    # for LoongArch).
    #
    # See https://gist.github.com/xen0n/5ee04aaa6cecc5c7794b9a0c3b65fc7f for
    # source to this helper binary.
    ignore base64 -d > "$_tmp" <<EOF
f0VMRgIBAQAAAAAAAAAAAAIAAgEBAAAAeAAgAAAAAABAAAAAAAAAAAAAAAAAAAAAQQAAAEAAOAAB
AAAAAAAAAAEAAAAFAAAAAAAAAAAAAAAAACAAAAAAAAAAIAAAAAAAJAAAAAAAAAAkAAAAAAAAAAAA
AQAAAAAABCiAAwUAFQAGABUAByCAAwsYggMAACsAC3iBAwAAKwAxen0n
EOF

    ignore chmod u+x "$_tmp"
    if [ ! -x "$_tmp" ]; then
        ignore rm "$_tmp"
        return 1
    fi

    "$_tmp"
    local _retval=$?

    ignore rm "$_tmp"
    return "$_retval"
}

ensure_loongarch_uapi() {
    check_loongarch_uapi
    case $? in
        0)
            return 0
            ;;
        234)
            err 'Your Linux kernel does not provide the ABI required by this Rust distribution.'
            err 'Please check with your OS provider for how to obtain a compatible Rust package for your system.'
            exit 1
            ;;
        *)
            warn "Cannot determine current system's ABI flavor, continuing anyway."
            warn 'Note that the official Rust distribution only works with the upstream kernel ABI.'
            warn 'Installation will fail if your running kernel happens to be incompatible.'
            ;;
    esac
}

get_architecture() {
    local _ostype _cputype _bitness _arch _clibtype
    _ostype="$(uname -s)"
    _cputype="$(uname -m)"
    _clibtype="gnu"

    if [ "$_ostype" = Linux ]; then
        if [ "$(uname -o)" = Android ]; then
            _ostype=Android
        fi
        if ldd --version 2>&1 | grep -q 'musl'; then
            _clibtype="musl"
        fi
    fi

    if [ "$_ostype" = Darwin ]; then
        # Darwin `uname -m` can lie due to Rosetta shenanigans. If you manage to
        # invoke a native shell binary and then a native uname binary, you can
        # get the real answer, but that's hard to ensure, so instead we use
        # `sysctl` (which doesn't lie) to check for the actual architecture.
        if [ "$_cputype" = i386 ]; then
            # Handling i386 compatibility mode in older macOS versions (<10.15)
            # running on x86_64-based Macs.
            # Starting from 10.15, macOS explicitly bans all i386 binaries from running.
            # See: <https://support.apple.com/en-us/HT208436>

            # Avoid `sysctl: unknown oid` stderr output and/or non-zero exit code.
            if sysctl hw.optional.x86_64 2> /dev/null || true | grep -q ': 1'; then
                _cputype=x86_64
            fi
        elif [ "$_cputype" = x86_64 ]; then
            # Handling x86-64 compatibility mode (a.k.a. Rosetta 2)
            # in newer macOS versions (>=11) running on arm64-based Macs.
            # Rosetta 2 is built exclusively for x86-64 and cannot run i386 binaries.

            # Avoid `sysctl: unknown oid` stderr output and/or non-zero exit code.
            if sysctl hw.optional.arm64 2> /dev/null || true | grep -q ': 1'; then
                _cputype=arm64
            fi
        fi
    fi

    if [ "$_ostype" = SunOS ]; then
        # Both Solaris and illumos presently announce as "SunOS" in "uname -s"
        # so use "uname -o" to disambiguate.  We use the full path to the
        # system uname in case the user has coreutils uname first in PATH,
        # which has historically sometimes printed the wrong value here.
        if [ "$(/usr/bin/uname -o)" = illumos ]; then
            _ostype=illumos
        fi

        # illumos systems have multi-arch userlands, and "uname -m" reports the
        # machine hardware name; e.g., "i86pc" on both 32- and 64-bit x86
        # systems.  Check for the native (widest) instruction set on the
        # running kernel:
        if [ "$_cputype" = i86pc ]; then
            _cputype="$(isainfo -n)"
        fi
    fi

    local _current_exe
    case "$_ostype" in

        Android)
            _ostype=linux-android
            ;;

        Linux)
            _current_exe=$(get_current_exe)
            _ostype=unknown-linux-$_clibtype
            _bitness=$(get_bitness "$_current_exe")
            ;;

        FreeBSD)
            _ostype=unknown-freebsd
            ;;

        NetBSD)
            _ostype=unknown-netbsd
            ;;

        DragonFly)
            _ostype=unknown-dragonfly
            ;;

        Darwin)
            _ostype=apple-darwin
            ;;

        illumos)
            _ostype=unknown-illumos
            ;;

        MINGW* | MSYS* | CYGWIN* | Windows_NT)
            _ostype=pc-windows-gnu
            ;;

        *)
            err "unrecognized OS type: $_ostype"
            exit 1
            ;;

    esac

    case "$_cputype" in

        i386 | i486 | i686 | i786 | x86)
            _cputype=i686
            ;;

        xscale | arm)
            _cputype=arm
            if [ "$_ostype" = "linux-android" ]; then
                _ostype=linux-androideabi
            fi
            ;;

        armv6l)
            _cputype=arm
            if [ "$_ostype" = "linux-android" ]; then
                _ostype=linux-androideabi
            else
                _ostype="${_ostype}eabihf"
            fi
            ;;

        armv7l | armv8l)
            _cputype=armv7
            if [ "$_ostype" = "linux-android" ]; then
                _ostype=linux-androideabi
            else
                _ostype="${_ostype}eabihf"
            fi
            ;;

        aarch64 | arm64)
            _cputype=aarch64
            ;;

        x86_64 | x86-64 | x64 | amd64)
            _cputype=x86_64
            ;;

        mips)
            _
